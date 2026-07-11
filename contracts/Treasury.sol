// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20T {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/**
 * @title Treasury — backs KSHRD redemption
 * @notice Holds USDC and KDEX funded by real platform fees. KSHRD holders
 *         redeem for USDC, or for KDEX with a keepback bonus that keeps value
 *         inside the system. Multi-sig owned (n-of-m) in production.
 */
contract Treasury {
    IERC20T public immutable usdc;
    IERC20T public immutable kdex;
    address public staking; // authorized to authorize redemptions
    address public owner;

    uint256 public constant KDEX_KEEPBACK_BONUS_BPS = 1000; // +10% if redeemed as KDEX

    event Redeemed(address indexed user, uint256 kshrd, bool asUsdc, uint256 paid);
    event FeeDeposited(address indexed from, uint256 usdcAmount);

    modifier onlyOwner() {
        require(msg.sender == owner, "TREAS: not owner");
        _;
    }

    constructor(address _usdc, address _kdex) {
        usdc = IERC20T(_usdc);
        kdex = IERC20T(_kdex);
        owner = msg.sender;
    }

    function setStaking(address _staking) external onlyOwner {
        staking = _staking;
    }

    /// @notice Deposit platform fees (USDC) that back the yield.
    function depositFees(uint256 usdcAmount) external {
        require(usdc.transferFrom(msg.sender, address(this), usdcAmount), "TREAS: deposit");
        emit FeeDeposited(msg.sender, usdcAmount);
    }

    /**
     * @notice Redeem accrued KSHRD. Called by the staking flow on the user's
     *         behalf. 1 KSHRD == 1 USDC baseline; choosing KDEX adds a 10% bonus.
     */
    function redeem(address user, uint256 kshrd, bool asUsdc) external returns (uint256 paid) {
        require(msg.sender == staking, "TREAS: only staking");
        if (asUsdc) {
            paid = kshrd;
            require(usdc.balanceOf(address(this)) >= paid, "TREAS: insufficient USDC");
            require(usdc.transfer(user, paid), "TREAS: USDC pay");
        } else {
            paid = kshrd + (kshrd * KDEX_KEEPBACK_BONUS_BPS) / 10000;
            require(kdex.balanceOf(address(this)) >= paid, "TREAS: insufficient KDEX");
            require(kdex.transfer(user, paid), "TREAS: KDEX pay");
        }
        emit Redeemed(user, kshrd, asUsdc, paid);
    }
}
