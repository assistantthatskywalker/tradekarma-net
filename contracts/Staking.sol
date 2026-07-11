// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/**
 * @title Staking — KRUNE + KDEX → KSHRD yield
 * @notice The anti-whale mechanic ON-CHAIN. To open a stake you must deposit
 *         BOTH earned KRUNE and purchased KDEX. A wallet with millions of KDEX
 *         but zero KRUNE cannot stake — the require() reverts. Yield accrues on
 *         the geometric mean sqrt(krune * kdex), so both halves matter.
 */
contract Staking {
    IERC20 public immutable krune;
    IERC20 public immutable kdex;

    uint256 public constant LOCK_PERIOD = 90 days;
    // ~1% annual on the geometric mean, expressed per second (scaled 1e18).
    uint256 public constant YIELD_RATE_PER_SEC = 317097919; // ~0.01e18 / 365d

    struct Position {
        uint256 krune;
        uint256 kdex;
        uint256 startedAt;
        uint256 lastAccrued;
        uint256 accruedKshrd;
        bool active;
    }

    mapping(address => Position) public positions;

    event Staked(address indexed user, uint256 krune, uint256 kdex);
    event Accrued(address indexed user, uint256 kshrd);
    event Unstaked(address indexed user, uint256 krune, uint256 kdex, uint256 kshrd);

    constructor(address _krune, address _kdex) {
        krune = IERC20(_krune);
        kdex = IERC20(_kdex);
    }

    /**
     * @notice Open or add to a stake. Requires BOTH tokens (anti-whale gate).
     */
    function stake(uint256 kruneAmount, uint256 kdexAmount) external {
        require(kruneAmount > 0, "STAKE: need earned KRUNE (reputation)");
        require(kdexAmount > 0, "STAKE: need invested KDEX (capital)");

        _accrue(msg.sender);

        require(krune.transferFrom(msg.sender, address(this), kruneAmount), "STAKE: KRUNE transfer");
        require(kdex.transferFrom(msg.sender, address(this), kdexAmount), "STAKE: KDEX transfer");

        Position storage p = positions[msg.sender];
        if (!p.active) {
            p.active = true;
            p.startedAt = block.timestamp;
            p.lastAccrued = block.timestamp;
        }
        p.krune += kruneAmount;
        p.kdex += kdexAmount;

        emit Staked(msg.sender, kruneAmount, kdexAmount);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function _accrue(address user) internal {
        Position storage p = positions[user];
        if (!p.active) return;
        uint256 elapsed = block.timestamp - p.lastAccrued;
        if (elapsed == 0) return;
        uint256 geometric = _sqrt(p.krune * p.kdex);
        uint256 yield_ = (geometric * YIELD_RATE_PER_SEC * elapsed) / 1e18;
        p.accruedKshrd += yield_;
        p.lastAccrued = block.timestamp;
        if (yield_ > 0) emit Accrued(user, yield_);
    }

    function pendingKshrd(address user) external view returns (uint256) {
        Position storage p = positions[user];
        if (!p.active) return 0;
        uint256 elapsed = block.timestamp - p.lastAccrued;
        uint256 geometric = _sqrt(p.krune * p.kdex);
        return p.accruedKshrd + (geometric * YIELD_RATE_PER_SEC * elapsed) / 1e18;
    }

    /**
     * @notice Close the stake after the lock period. Returns both principals and
     *         the accrued KSHRD amount (minted by the treasury off this event).
     */
    function unstake() external returns (uint256 kshrd) {
        Position storage p = positions[msg.sender];
        require(p.active, "STAKE: none");
        require(block.timestamp >= p.startedAt + LOCK_PERIOD, "STAKE: locked");

        _accrue(msg.sender);
        kshrd = p.accruedKshrd;
        uint256 kruneAmt = p.krune;
        uint256 kdexAmt = p.kdex;

        delete positions[msg.sender];

        require(krune.transfer(msg.sender, kruneAmt), "STAKE: KRUNE return");
        require(kdex.transfer(msg.sender, kdexAmt), "STAKE: KDEX return");

        emit Unstaked(msg.sender, kruneAmt, kdexAmt, kshrd);
    }
}
