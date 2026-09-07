// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {KarmaShard} from "./KarmaShard.sol";
import {Treasury} from "./Treasury.sol";

/**
 * @title Staking — KRUNE + KDEX → a share of real fee revenue
 * @notice The anti-whale mechanic ON-CHAIN. To open a stake you must bring
 *         BOTH earned KRUNE and purchased KDEX. A wallet with millions of KDEX
 *         and zero KRUNE cannot stake — the require() reverts. A position's
 *         share of the pool is the geometric mean sqrt(krune * kdex), so both
 *         halves matter.
 * @dev v2 replaced a fixed 1%/yr rate paid in dollars with pool-share
 *      accounting, because the v1 scheme minted a dollar-denominated liability
 *      out of token counts and elapsed time with nothing funding it. Yield here
 *      is a share of USDC that has ALREADY been deposited as platform fees:
 *
 *          KSHRD minted can never exceed USDC deposited as fees.
 *
 *      That is a structural property of the arithmetic below, not something an
 *      operator has to watch. `depositFees` is the only function that can
 *      increase what anyone is owed, and it cannot run without USDC changing
 *      hands in the same call.
 *
 *      The distribution mechanism is Synthetix `StakingRewards`, unchanged in
 *      substance: a single global accumulator `rewardPerWeightStored`, a
 *      per-position checkpoint `rewardPerWeightPaid`, and `totalWeight`
 *      maintained incrementally so no function ever iterates positions.
 *
 *      Accrual is NOT a function of time. A position that sits through a period
 *      with no fee revenue earns nothing, which is what the whitepaper always
 *      claimed and v1 never implemented.
 *
 *      This contract must hold MINTER_ROLE on the KarmaShard token.
 */
contract Staking is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Referenced, never escrowed — KRUNE is soulbound and cannot move.
    IERC20 public immutable krune;
    /// @notice Escrowed here for the duration of the position.
    IERC20 public immutable kdex;
    KarmaShard public immutable kshrd;
    /// @notice Where deposited fees land and where KSHRD is redeemed.
    Treasury public immutable treasury;
    /// @notice The fee token, read from the Treasury so the two cannot disagree.
    IERC20 public immutable usdc;
    /// @notice 10 ** (18 - usdc.decimals()), likewise read from the Treasury.
    uint256 public immutable usdcScale;

    uint256 public constant LOCK_PERIOD = 90 days;

    /// @notice Fixed-point one, the scale of `rewardPerWeightStored`.
    uint256 public constant SCALE = 1e18;

    struct Position {
        /// @notice KRUNE referenced by this position. It stays in the staker's
        ///         wallet; this is a claim on their balance, not custody of it.
        uint256 krune;
        /// @notice KDEX actually held by this contract.
        uint256 kdex;
        /// @notice Cached `_geometricMean(krune, kdex)`. Stored rather than
        ///         recomputed so that `totalWeight` can be adjusted by exactly
        ///         the amount that was added — the geometric mean is not
        ///         additive, so subtracting a recomputed value could drift.
        uint256 weight;
        uint256 startedAt;
        /// @notice Accumulator value at this position's last settlement.
        uint256 rewardPerWeightPaid;
        /// @notice Settled reward, in USDC base units.
        uint256 accruedUsdc;
        bool active;
    }

    mapping(address => Position) public positions;

    /**
     * @notice Yield that was accrued and settled, but could not be minted at
     *         unstake time because KarmaShard refused the mint. Claimable in
     *         full via `claimYield()` once minting works again.
     */
    mapping(address => uint256) public unclaimedYield;

    /// @notice Sum of every active position's weight. Maintained incrementally.
    uint256 public totalWeight;

    /// @notice USDC base units earned per unit of weight, 1e18-scaled and
    ///         monotonically increasing. Only `depositFees` moves it.
    uint256 public rewardPerWeightStored;

    /**
     * @notice Deposited USDC not yet attributable to anyone: fees that arrived
     *         while `totalWeight` was zero, plus the sub-unit remainder of every
     *         allocation. Folded into the next deposit that has weight to divide
     *         by. It sits in the Treasury the whole time — this counter says how
     *         much of the balance is still unspoken for, not where it is.
     */
    uint256 public unallocatedFees;
    /// @notice Conservative reserve for allocated, unminted rewards (including rounding dust).
    uint256 public unmintedReserveUsdc;

    /// @notice All reserved USDC: minted claims, unminted allocations, and carried fees.
    function totalReservedUsdc() public view returns (uint256) {
        return treasury.totalOutstandingLiability() + unmintedReserveUsdc + unallocatedFees;
    }

    function reservesCovered() external view returns (bool) {
        return usdc.balanceOf(address(treasury)) >= totalReservedUsdc();
    }

    event Staked(address indexed user, uint256 krune, uint256 kdex);
    event Accrued(address indexed user, uint256 usdcAmount);
    event Unstaked(address indexed user, uint256 krune, uint256 kdex, uint256 kshrd);
    event YieldMintDeferred(address indexed user, uint256 kshrd);
    event YieldClaimed(address indexed user, uint256 kshrd);
    event FeeDeposited(address indexed from, uint256 usdcAmount, uint256 allocated, uint256 rewardPerWeight);
    event CollateralRatioUpdated(uint256 ratio, uint256 outstandingLiability, uint256 treasuryUsdc);

    /**
     * @param _treasury must already be deployed — this contract reads the fee
     *        token and its decimal scale from it, so the two can never be wired
     *        to different stablecoins.
     */
    constructor(address _krune, address _kdex, address _kshrd, address _treasury, address initialOwner)
        Ownable(initialOwner)
    {
        require(_krune != address(0) && _kdex != address(0) && _kshrd != address(0), "STAKE: zero token");
        require(_treasury != address(0), "STAKE: zero treasury");
        // Minting shards against one Treasury while a different one redeems them
        // is unrecoverable and silent, and both addresses here are immutable.
        require(address(Treasury(_treasury).kshrd()) == _kshrd, "STAKE: treasury/KSHRD mismatch");

        krune = IERC20(_krune);
        kdex = IERC20(_kdex);
        kshrd = KarmaShard(_kshrd);
        treasury = Treasury(_treasury);
        usdc = Treasury(_treasury).usdc();
        usdcScale = Treasury(_treasury).usdcScale();
    }

    /*//////////////////////////////////////////////////////////////
                              THE FEE POOL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit platform fees. The USDC moves to the Treasury and, in the
     *         same call, becomes claimable by everyone currently staked, in
     *         proportion to their weight. Permissionless: paying the pool is
     *         never something to gate.
     * @dev This is the ONLY function that increases `rewardPerWeightStored`, and
     *      it cannot run without the transfer succeeding first. That ordering is
     *      the solvency invariant: nothing becomes claimable until the money to
     *      pay it is in the Treasury.
     *
     *      Arithmetic, with `pool` = new fees plus whatever was carried:
     *          delta     = floor(pool * SCALE / totalWeight)
     *          allocated = ceil(delta * totalWeight / SCALE)      <= pool
     *      `delta` is floored so the pool can never promise more than it holds.
     *      `allocated` is CEILED on purpose: it is the amount removed from
     *      `unallocatedFees`, so it has to be an upper bound on what the delta
     *      can pay out. Flooring it there would return up to one base unit per
     *      deposit to the carry AND leave it claimable, letting cumulative mints
     *      exceed cumulative deposits by up to one base unit per deposit. The
     *      cost of ceiling is that up to 1e-6 USDC per deposit stops being
     *      attributable; it stays in the Treasury as excess backing, which is
     *      the direction an error is allowed to point.
     *
     *      With `totalWeight == 0` there is nobody to divide by. The fees are
     *      held in `unallocatedFees` and folded into the next deposit that has
     *      weight — never discarded, and never a division by zero.
     */
    function depositFees(uint256 usdcAmount) external nonReentrant {
        uint256 beforeBalance = usdc.balanceOf(address(treasury));
        usdc.safeTransferFrom(msg.sender, address(treasury), usdcAmount);
        require(usdc.balanceOf(address(treasury)) - beforeBalance == usdcAmount, "STAKE: unsupported fee token");

        uint256 weight = totalWeight;
        uint256 pool = unallocatedFees + usdcAmount;
        uint256 allocated;
        if (weight > 0) {
            uint256 delta = Math.mulDiv(pool, SCALE, weight);
            rewardPerWeightStored += delta;
            allocated = Math.mulDiv(delta, weight, SCALE, Math.Rounding.Ceil);
        }
        unallocatedFees = pool - allocated;
        unmintedReserveUsdc += allocated;

        emit FeeDeposited(msg.sender, usdcAmount, allocated, rewardPerWeightStored);
        emit CollateralRatioUpdated(
            treasury.collateralRatio(), treasury.totalOutstandingLiability(), usdc.balanceOf(address(treasury))
        );
    }

    /*//////////////////////////////////////////////////////////////
                                  STAKE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Open or add to a stake. Requires BOTH tokens (anti-whale gate).
     * @param kruneAmount KRUNE to reference. It is NOT transferred — the caller
     *        must simply hold at least this much on top of anything their
     *        position already references.
     * @param kdexAmount KDEX to escrow. This one does move.
     * @dev KRUNE is soulbound, so `safeTransferFrom` on it would revert; the
     *      position records a claim on the staker's balance instead. That is
     *      sound for one reason and it is worth stating plainly: a soulbound
     *      balance is monotonically non-decreasing, so a reference taken today
     *      cannot be invalidated tomorrow. Double-counting is closed by checking
     *      the balance against the position's RUNNING TOTAL — `p.krune +
     *      kruneAmount`, not `kruneAmount` — because there is one position per
     *      address and a top-up would otherwise let the same 100 KRUNE back two
     *      100-KRUNE claims. No `lockedOf` ledger is needed: with one position
     *      per address and a balance that cannot fall, the balance IS the ledger.
     *
     *      Every deposit restarts the 90-day lock on the WHOLE position, not just
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

        _settle(msg.sender);

        Position storage p = positions[msg.sender];
        uint256 newKrune = p.krune + kruneAmount;
        require(krune.balanceOf(msg.sender) >= newKrune, "STAKE: KRUNE already staked or not held");

        if (!p.active) {
            p.active = true;
            p.rewardPerWeightPaid = rewardPerWeightStored;
        }
        p.startedAt = block.timestamp;
        p.krune = newKrune;
        p.kdex += kdexAmount;

        uint256 newWeight = _geometricMean(newKrune, p.kdex);
        totalWeight = totalWeight - p.weight + newWeight;
        p.weight = newWeight;

        kdex.safeTransferFrom(msg.sender, address(this), kdexAmount);

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

    /**
     * @dev Move everything the accumulator owes this position into
     *      `accruedUsdc` and checkpoint it. Must run before any change to the
     *      position's weight, so the period just ended is valued at the weight
     *      that actually earned it.
     */
    function _settle(address user) internal {
        Position storage p = positions[user];
        if (!p.active) return;
        uint256 stored = rewardPerWeightStored;
        uint256 owed = Math.mulDiv(p.weight, stored - p.rewardPerWeightPaid, SCALE);
        p.rewardPerWeightPaid = stored;
        if (owed > 0) {
            p.accruedUsdc += owed;
            emit Accrued(user, owed);
        }
    }

    /// @dev Settled plus unsettled reward, in USDC base units.
    function _earnedUsdc(address user) internal view returns (uint256) {
        Position storage p = positions[user];
        if (!p.active) return 0;
        return p.accruedUsdc + Math.mulDiv(p.weight, rewardPerWeightStored - p.rewardPerWeightPaid, SCALE);
    }

    /// @notice KSHRD this position would mint if it closed now. Exactly what
    ///         `unstake()` returns, so a UI can quote it without lying.
    function pendingKshrd(address user) external view returns (uint256) {
        return _earnedUsdc(user) * usdcScale;
    }

    /*//////////////////////////////////////////////////////////////
                                 UNSTAKE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Close the stake after the lock period. Returns the escrowed KDEX
     *         and MINTS the accrued yield as KSHRD to the staker, who redeems it
     *         at the Treasury.
     * @return kshrdMinted the yield settled by this call. It is minted straight
     *         to the staker unless KarmaShard refuses, in which case the same
     *         amount is recorded in `unclaimedYield` and `claimYield()` pays it.
     * @dev No KRUNE is returned because none was ever taken — the position only
     *      ever held a reference, which this call releases. The event still
     *      reports the amount so an indexer can see the reference close.
     *
     *      There is no early exit. `unstake` reverts while locked, with no
     *      forfeiture path and no partial withdrawal.
     *
     *      Nothing here may stand between a matured staker and their principal.
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

        _settle(msg.sender);

        uint256 earned = p.accruedUsdc;
        uint256 kruneAmt = p.krune;
        uint256 kdexAmt = p.kdex;

        totalWeight -= p.weight;
        delete positions[msg.sender];

        // Reward is carried in USDC base units; KSHRD is 18-decimal and redeems
        // one-for-one against a whole USDC, so the scale is applied once, here.
        kshrdMinted = earned * usdcScale;

        if (kshrdMinted > 0) {
            try kshrd.mint(msg.sender, kshrdMinted) {
                unmintedReserveUsdc -= earned;
            }
            catch {
                unclaimedYield[msg.sender] += kshrdMinted;
                emit YieldMintDeferred(msg.sender, kshrdMinted);
            }
        }
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
        unmintedReserveUsdc -= amount / usdcScale;
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
