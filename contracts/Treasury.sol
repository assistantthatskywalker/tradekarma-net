// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {KarmaShard} from "./KarmaShard.sol";

/**
 * @title Treasury — backs KSHRD redemption
 * @notice Holds USDC and KDEX funded by real platform fees. KSHRD holders
 *         redeem for USDC, or for KDEX with a keepback bonus that keeps value
 *         inside the system. Multi-sig owned (n-of-m) in production.
 * @dev Redemption BURNS the caller's KSHRD before paying out, so the shard
 *      supply always equals outstanding claims. This contract must hold
 *      BURNER_ROLE on the KarmaShard token.
 */
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    IERC20 public immutable kdex;
    KarmaShard public immutable kshrd;

    /**
     * @notice Divisor converting 18-decimal KSHRD to USDC base units,
     *         = 10 ** (18 - usdc.decimals()). Read from the USDC contract at
     *         construction rather than hardcoded, since the stablecoin's decimals
     *         differ per chain (6 on Base). Without it, redeeming 1e18 KSHRD
     *         would try to pay 1e18 USDC base units — one trillion dollars.
     */
    uint256 public immutable usdcScale;

    uint256 public constant KDEX_KEEPBACK_BONUS_BPS = 1000; // +10% if redeemed as KDEX

    event Redeemed(address indexed user, uint256 kshrd, bool asUsdc, uint256 paid);
    event FeeDeposited(address indexed from, uint256 usdcAmount);
    event TokenRecovered(address indexed token, address indexed to, uint256 amount);

    constructor(address _usdc, address _kdex, address _kshrd, address initialOwner) Ownable(initialOwner) {
        require(_usdc != address(0) && _kdex != address(0) && _kshrd != address(0), "TREAS: zero token");
        uint8 usdcDecimals = IERC20Metadata(_usdc).decimals();
        require(usdcDecimals <= 18, "TREAS: USDC decimals > 18");
        usdc = IERC20(_usdc);
        kdex = IERC20(_kdex);
        kshrd = KarmaShard(_kshrd);
        usdcScale = 10 ** (18 - usdcDecimals);
    }

    /// @notice Deposit platform fees (USDC) that back the yield.
    function depositFees(uint256 usdcAmount) external nonReentrant {
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        emit FeeDeposited(msg.sender, usdcAmount);
    }

    /**
     * @notice Redeem KSHRD held in the caller's wallet (minted by Staking on
     *         unstake). 1 KSHRD == 1 USDC baseline; choosing KDEX adds a 10%
     *         bonus. The redeemed shards are burned before payout.
     * @dev The caller must first approve this contract for `kshrdAmount` of
     *      KSHRD: the burn spends that allowance, which is what makes it
     *      impossible for a burner to destroy a balance its holder never
     *      offered up. The USDC path burns only what it paid for, so it spends
     *      no more of the allowance than that.
     * @param kshrdAmount 18-decimal KSHRD to redeem.
     * @param asUsdc true to be paid in USDC, false to be paid in KDEX + bonus.
     * @return paid amount transferred, in the payout token's own decimals.
     */
    function redeem(uint256 kshrdAmount, bool asUsdc) external nonReentrant returns (uint256 paid) {
        require(kshrdAmount > 0, "TREAS: zero amount");
        uint256 burned;

        if (asUsdc) {
            paid = kshrdAmount / usdcScale;
            require(paid > 0, "TREAS: below one USDC unit");
            // Burn only what was actually paid for; sub-unit dust stays with the
            // holder instead of being destroyed for nothing.
            burned = paid * usdcScale;
            require(usdc.balanceOf(address(this)) >= paid, "TREAS: insufficient USDC");
            kshrd.burnFrom(msg.sender, burned);
            usdc.safeTransfer(msg.sender, paid);
        } else {
            // KDEX is 18-decimal like KSHRD, so no scaling is needed here.
            burned = kshrdAmount;
            paid = kshrdAmount + (kshrdAmount * KDEX_KEEPBACK_BONUS_BPS) / 10000;
            require(kdex.balanceOf(address(this)) >= paid, "TREAS: insufficient KDEX");
            kshrd.burnFrom(msg.sender, burned);
            kdex.safeTransfer(msg.sender, paid);
        }

        emit Redeemed(msg.sender, burned, asUsdc, paid);
    }

    /**
     * @notice Recover tokens sent here by mistake. The USDC and KDEX backing the
     *         redemption promise is deliberately out of reach.
     */
    function recoverToken(address token, address to, uint256 amount) external onlyOwner {
        require(token != address(usdc) && token != address(kdex), "TREAS: backing asset");
        require(to != address(0), "TREAS: zero recipient");
        IERC20(token).safeTransfer(to, amount);
        emit TokenRecovered(token, to, amount);
    }

    /**
     * @notice Disabled. Renouncing would leave `recoverToken` uncallable, which
     *         strands every token ever sent here by mistake, permanently and for
     *         everyone. Use `transferOwnership`, which stays available.
     */
    function renounceOwnership() public pure override {
        revert("TREAS: renounce disabled");
    }
}
