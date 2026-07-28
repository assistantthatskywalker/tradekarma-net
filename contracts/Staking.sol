// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {KarmaShard} from "./KarmaShard.sol";

/**
 * @title Staking — KRUNE + KDEX → KSHRD yield
 * @notice The anti-whale mechanic ON-CHAIN. To open a stake you must deposit
 *         BOTH earned KRUNE and purchased KDEX. A wallet with millions of KDEX
 *         but zero KRUNE cannot stake — the require() reverts. Yield accrues on
 *         the geometric mean sqrt(krune * kdex), so both halves matter.
 * @dev Accrued yield is MINTED as KSHRD to the staker on unstake; the holder
 *      then redeems that KSHRD at the Treasury. This contract must hold
 *      MINTER_ROLE on the KarmaShard token.
 */
contract Staking is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable krune;
    IERC20 public immutable kdex;
    KarmaShard public immutable kshrd;

    uint256 public constant LOCK_PERIOD = 90 days;

    /**
     * ~1% annual on the geometric mean, expressed per second (scaled 1e18):
     *   0.01e18 / 365 days = 1e16 / 31_536_000 = 317_097_919.83… → 317097919
     * Round-trip check over one year:
     *   317097919 * 31_536_000 / 1e18 = 0.009999999973584
     * i.e. 0.9999999974% per year — correct, the truncation costs 2.6e-8 of the
     * rate. Yield is denominated in KSHRD (18 decimals), same scale as the
     * geometric mean of two 18-decimal balances.
     */
    uint256 public constant YIELD_RATE_PER_SEC = 317097919;

    struct Position {
        uint256 krune;
        uint256 kdex;
        uint256 startedAt;
        uint256 lastAccrued;
        uint256 accruedKshrd;
        bool active;
    }

    mapping(address => Position) public positions;

    /**
     * @notice Yield that was accrued and settled, but could not be minted at
     *         unstake time because KarmaShard refused the mint. Claimable in
     *         full via `claimYield()` once minting works again.
     */
    mapping(address => uint256) public unclaimedYield;

    event Staked(address indexed user, uint256 krune, uint256 kdex);
    event Accrued(address indexed user, uint256 kshrd);
    event Unstaked(address indexed user, uint256 krune, uint256 kdex, uint256 kshrd);
    event YieldMintDeferred(address indexed user, uint256 kshrd);
    event YieldClaimed(address indexed user, uint256 kshrd);

    constructor(address _krune, address _kdex, address _kshrd, address initialOwner) Ownable(initialOwner) {
        require(_krune != address(0) && _kdex != address(0) && _kshrd != address(0), "STAKE: zero token");
        krune = IERC20(_krune);
        kdex = IERC20(_kdex);
        kshrd = KarmaShard(_kshrd);
    }

    /**
     * @notice Open or add to a stake. Requires BOTH tokens (anti-whale gate).
     * @dev Every deposit restarts the 90-day lock on the WHOLE position, not just
     *      on the tokens being added. That is deliberate and it is the only
     *      version of this rule that holds unconditionally: if `startedAt` only
     *      tracked the first deposit, one 1-wei position left to mature for 90
     *      days would exempt that wallet from the lock forever — deposit
     *      millions, withdraw in the same block, repeat.
     *
     *      A per-deposit weighted average (shifting `startedAt` by the new
     *      tranche's share of the geometric mean) was considered and rejected: it
     *      is kinder to honest top-ups, but it leaves the same attack intact at
     *      larger scale, since a top-up small relative to a matured position
     *      still comes out almost immediately. The lock is this design's only
     *      commitment device, so it gets the guarantee with no residue.
     *
     *      The cost is real and falls on honest stakers: adding to a nearly
     *      matured position re-locks principal that had almost finished its term.
     *      It is self-inflicted (only `msg.sender` can top up their own position),
     *      fully visible in `positions[user].startedAt` before and after, and the
     *      alternative — leave it, restake later — is always available.
     */
    function stake(uint256 kruneAmount, uint256 kdexAmount) external nonReentrant whenNotPaused {
        require(kruneAmount > 0, "STAKE: need earned KRUNE (reputation)");
        require(kdexAmount > 0, "STAKE: need invested KDEX (capital)");

        _accrue(msg.sender);

        krune.safeTransferFrom(msg.sender, address(this), kruneAmount);
        kdex.safeTransferFrom(msg.sender, address(this), kdexAmount);

        Position storage p = positions[msg.sender];
        if (!p.active) {
            p.active = true;
            p.lastAccrued = block.timestamp;
        }
        p.startedAt = block.timestamp;
        p.krune += kruneAmount;
        p.kdex += kdexAmount;

        emit Staked(msg.sender, kruneAmount, kdexAmount);
    }

    /**
     * @dev sqrt(a * b) reverts on overflow once a * b exceeds ~1.15e77, which is
     *      reachable with two 18-decimal balances. sqrt(a) * sqrt(b) is
     *      mathematically <= sqrt(a * b) and can never overflow (both factors are
     *      at most 2**128 - 1), at the cost of rounding each root down first —
     *      exact for perfect squares, and otherwise short by at most
     *      sqrt(a) + sqrt(b): about 63 gwei on two 1000-token balances, growing
     *      with the square root of the position rather than with it. The
     *      shortfall is always in the protocol's favour, never the staker's.
     */
    function _geometricMean(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.sqrt(a) * Math.sqrt(b);
    }

    /// @dev mulDiv keeps the intermediate product in 512 bits, so a large
    ///      geometric mean cannot overflow before the 1e18 divide.
    function _yieldFor(uint256 geometric, uint256 elapsed) internal pure returns (uint256) {
        return Math.mulDiv(geometric, YIELD_RATE_PER_SEC * elapsed, 1e18);
    }

    function _accrue(address user) internal {
        Position storage p = positions[user];
        if (!p.active) return;
        uint256 elapsed = block.timestamp - p.lastAccrued;
        if (elapsed == 0) return;
        uint256 yield_ = _yieldFor(_geometricMean(p.krune, p.kdex), elapsed);
        p.accruedKshrd += yield_;
        p.lastAccrued = block.timestamp;
        if (yield_ > 0) emit Accrued(user, yield_);
    }

    function pendingKshrd(address user) external view returns (uint256) {
        Position storage p = positions[user];
        if (!p.active) return 0;
        uint256 elapsed = block.timestamp - p.lastAccrued;
        return p.accruedKshrd + _yieldFor(_geometricMean(p.krune, p.kdex), elapsed);
    }

    /**
     * @notice Close the stake after the lock period. Returns both principals and
     *         MINTS the accrued yield as KSHRD to the staker, who redeems it at
     *         the Treasury.
     * @return kshrdMinted the yield settled by this call. It is minted straight
     *         to the staker unless KarmaShard refuses, in which case the same
     *         amount is recorded in `unclaimedYield` and `claimYield()` pays it.
     * @dev Nothing here may stand between a matured staker and their principal.
     *      Pausing does not — `unstake` is deliberately not pausable — and
     *      neither does the yield mint, which is wrapped so that a revert inside
     *      KarmaShard cannot take the withdrawal down with it. That mint depends
     *      on a role held on a THIRD contract, which an admin can revoke and a
     *      botched deploy can forget to grant; before it was wrapped, either one
     *      trapped the principal permanently and no pause or owner action could
     *      free it.
     */
    function unstake() external nonReentrant returns (uint256 kshrdMinted) {
        Position storage p = positions[msg.sender];
        require(p.active, "STAKE: none");
        // A validator can nudge block.timestamp by seconds; the lock is 90 days.
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp >= p.startedAt + LOCK_PERIOD, "STAKE: locked");

        _accrue(msg.sender);
        kshrdMinted = p.accruedKshrd;
        uint256 kruneAmt = p.krune;
        uint256 kdexAmt = p.kdex;

        delete positions[msg.sender];

        if (kshrdMinted > 0) {
            try kshrd.mint(msg.sender, kshrdMinted) {}
            catch {
                unclaimedYield[msg.sender] += kshrdMinted;
                emit YieldMintDeferred(msg.sender, kshrdMinted);
            }
        }
        krune.safeTransfer(msg.sender, kruneAmt);
        kdex.safeTransfer(msg.sender, kdexAmt);

        emit Unstaked(msg.sender, kruneAmt, kdexAmt, kshrdMinted);
    }

    /**
     * @notice Mint yield that `unstake()` had to defer because KarmaShard would
     *         not mint at the time. Callable by the staker once minting works.
     * @dev The debt is recorded in KSHRD terms at settlement, so waiting neither
     *      earns nor loses anything. Reverts if there is nothing owed, and still
     *      reverts if minting is broken — but by then the principal is long since
     *      home, which is the whole point of splitting the two.
     */
    function claimYield() external nonReentrant returns (uint256 amount) {
        amount = unclaimedYield[msg.sender];
        require(amount > 0, "STAKE: nothing to claim");
        unclaimedYield[msg.sender] = 0;
        kshrd.mint(msg.sender, amount);
        emit YieldClaimed(msg.sender, amount);
    }

    /// @notice Emergency stop for new stakes. Emits Paused / Unpaused.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Disabled. The owner's only power here is `pause` / `unpause`, and
     *         renouncing would destroy that emergency stop irreversibly for a
     *         gain of nothing. Hand the role over with `transferOwnership`
     *         instead, which stays available.
     */
    function renounceOwnership() public pure override {
        revert("STAKE: renounce disabled");
    }
}
