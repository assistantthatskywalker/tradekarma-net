// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {KarmaShard} from "./KarmaShard.sol";

/**
 * @title Treasury — backs KSHRD redemption
 * @notice Holds the USDC that platform fees pay in, plus a KDEX reserve. KSHRD
 *         holders redeem for USDC at 1 KSHRD = 1 USDC. Multi-sig owned (n-of-m)
 *         in production.
 * @dev Redemption BURNS the caller's KSHRD before paying out, so the shard
 *      supply always equals outstanding claims. This contract must hold
 *      BURNER_ROLE on the KarmaShard token.
 *
 *      Fees are NOT deposited here directly — they go through
 *      `Staking.depositFees`, which pulls the USDC into this contract and, in
 *      the same transaction, credits it to the stakers who are entitled to it.
 *      Splitting those two would let the treasury's balance and the pool's
 *      accounting drift apart, which is precisely the v1 failure this redesign
 *      removes. USDC arriving by any other route (a stray transfer, a donation)
 *      is simply unallocated backing: it raises `collateralRatio` and is owed to
 *      nobody.
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

    /// @notice Fixed-point one, the scale of `collateralRatio`.
    uint256 public constant SCALE = 1e18;

    /// @notice Extra KDEX paid on the keepback branch, on top of the priced
    ///         conversion, when that branch is enabled.
    uint256 public constant KDEX_KEEPBACK_BONUS_BPS = 1000; // +10% if redeemed as KDEX

    /**
     * @notice Price of one KDEX expressed in KSHRD, 1e18-scaled. Since
     *         1 KSHRD == 1 USDC, this is simply the USD price of KDEX.
     *         **Zero disables the KDEX redemption branch entirely, and zero is
     *         the deployed default.**
     * @dev v1 paid a flat 1.1 KDEX per KSHRD with no price anywhere in the
     *      system, which overpaid by 450% at $5/KDEX (audit H-02). There is no
     *      KDEX market yet, so there is no honest rate to hardcode and no feed
     *      to read; the branch therefore ships off, and the owner turns it on
     *      once a price exists. Governance-settable rather than immutable for
     *      the same reason — a rate that cannot follow the market is the bug.
     */
    uint256 public kshrdPerKdexRate;

    event Redeemed(address indexed user, uint256 kshrd, bool asUsdc, uint256 paid);
    event KeepbackRateSet(uint256 oldRate, uint256 newRate);
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

    /*//////////////////////////////////////////////////////////////
                          SOLVENCY, READABLE ON-CHAIN
    //////////////////////////////////////////////////////////////*/

    /// @notice KSHRD minted and not yet redeemed, 18 decimals.
    function totalKshrdOutstanding() public view returns (uint256) {
        return kshrd.totalSupply();
    }

    /**
     * @notice The same claim expressed in USDC base units — what this contract
     *         would have to pay if every holder redeemed right now.
     * @dev Floored, which matches `redeem`: sub-unit KSHRD dust buys nothing, so
     *      counting it as debt would overstate the obligation.
     */
    function totalOutstandingLiability() public view returns (uint256) {
        return kshrd.totalSupply() / usdcScale;
    }

    /**
     * @notice USDC held ÷ outstanding liability, 1e18-scaled. 1e18 is exactly
     *         collateralised; below that the treasury is insolvent.
     * @return type(uint256).max when nothing is owed — no finite ratio is
     *         meaningful against a zero denominator, and the caller should read
     *         it as "unbounded", not as a number to compare against a target.
     * @dev With pool-share accounting this is >= 1e18 by construction: KSHRD is
     *      only ever minted against USDC that has already arrived here, and both
     *      sides of the ratio fall by the same amount on redemption. The read
     *      exists so that the property is checkable by anyone rather than
     *      believed, and so a front-end can show it.
     */
    function collateralRatio() public view returns (uint256) {
        uint256 liability = totalOutstandingLiability();
        if (liability == 0) return type(uint256).max;
        return Math.mulDiv(usdc.balanceOf(address(this)), SCALE, liability);
    }

    /*//////////////////////////////////////////////////////////////
                                REDEMPTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Redeem KSHRD held in the caller's wallet (minted by Staking on
     *         unstake). 1 KSHRD == 1 USDC. The redeemed shards are burned before
     *         payout.
     * @dev The caller must first approve this contract for `kshrdAmount` of
     *      KSHRD: the burn spends that allowance, which is what makes it
     *      impossible for a burner to destroy a balance its holder never
     *      offered up. The USDC path burns only what it paid for, so it spends
     *      no more of the allowance than that.
     * @param kshrdAmount 18-decimal KSHRD to redeem.
     * @param asUsdc true to be paid in USDC, false to be paid in KDEX + keepback
     *        bonus. The KDEX branch reverts unless `kshrdPerKdexRate` has been
     *        set — see that variable.
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
            require(kshrdPerKdexRate > 0, "TREAS: KDEX redemption disabled");
            // KDEX is 18-decimal like KSHRD, so the only conversion is the price.
            burned = kshrdAmount;
            uint256 base = Math.mulDiv(kshrdAmount, SCALE, kshrdPerKdexRate);
            paid = base + (base * KDEX_KEEPBACK_BONUS_BPS) / 10000;
            require(paid > 0, "TREAS: below one KDEX unit");
            require(kdex.balanceOf(address(this)) >= paid, "TREAS: insufficient KDEX");
            kshrd.burnFrom(msg.sender, burned);
            kdex.safeTransfer(msg.sender, paid);
        }

        emit Redeemed(msg.sender, burned, asUsdc, paid);
    }

    /**
     * @notice Set the KDEX price used by the keepback branch, or set it to 0 to
     *         switch that branch off again.
     * @param rate KSHRD per KDEX, 1e18-scaled. 1e18 means 1 KDEX = 1 KSHRD = $1.
     * @dev Deliberately unbounded in both directions: a floor would be a price
     *      opinion baked into an immutable contract, and a ceiling would stop the
     *      owner from following a KDEX rally upward. The only value with special
     *      meaning is 0, which closes the branch.
     */
    function setKshrdPerKdexRate(uint256 rate) external onlyOwner {
        emit KeepbackRateSet(kshrdPerKdexRate, rate);
        kshrdPerKdexRate = rate;
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
     *         everyone, and would freeze `kshrdPerKdexRate` at whatever it
     *         happened to be. Use `transferOwnership`, which stays available.
     */
    function renounceOwnership() public pure override {
        revert("TREAS: renounce disabled");
    }
}
