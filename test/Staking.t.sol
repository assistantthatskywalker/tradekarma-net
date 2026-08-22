// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {KarmaRune} from "../contracts/KarmaRune.sol";
import {KarmaDex} from "../contracts/KarmaDex.sol";
import {KarmaShard} from "../contracts/KarmaShard.sol";
import {Staking} from "../contracts/Staking.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {StakingHarness} from "./harness/StakingHarness.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract StakingTest is Test {
    KarmaRune internal krune;
    KarmaDex internal kdex;
    KarmaShard internal kshrd;
    Treasury internal treasury;
    Staking internal staking;
    StakingHarness internal harness;
    MockERC20 internal usdc;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant OWNER = address(0xB0B);
    address internal constant KDEX_TREASURY = address(0x7EA5);
    address internal constant ALICE = address(0xA11);
    address internal constant BOB = address(0xB0B0);
    address internal constant WHALE = address(0x1A26E);
    address internal constant STRANGER = address(0xDEAD);
    address internal constant FEE_PAYER = address(0xFEE);

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 internal constant ADMIN_ROLE = bytes32(0);

    uint256 internal constant KDEX_SUPPLY = 100_000_000e18;
    bytes32 internal constant REASON = keccak256("earned");

    /**
     * Reference weights, computed independently of the implementation:
     *   ALICE  100e18 KRUNE + 400e18 KDEX
     *     = sqrt(1e20) * sqrt(4e20) = 1e10 * 2e10 = 2e20   (exact, perfect squares)
     *   BOB    400e18 KRUNE + 100e18 KDEX
     *     = sqrt(4e20) * sqrt(1e20) = 2e10 * 1e10 = 2e20   (symmetric — same product)
     *
     * With ALICE alone staked and 1,000 USDC of fees deposited:
     *   delta   = 1_000e6 * 1e18 / 2e20 = 1e27 / 2e20 = 5_000_000
     *   earned  = 2e20 * 5_000_000 / 1e18 = 1e9 base units = 1,000.000000 USDC
     *   KSHRD   = 1e9 * 1e12 = 1_000e18
     * i.e. the only staker takes the entire pool, and 1 KSHRD still redeems for
     * exactly 1 USDC.
     */
    uint256 internal constant STAKE_KRUNE = 100e18;
    uint256 internal constant STAKE_KDEX = 400e18;
    uint256 internal constant ALICE_WEIGHT = 2e20;
    uint256 internal constant FEE_1000 = 1_000e6;
    uint256 internal constant KSHRD_1000 = 1_000e18;

    event Staked(address indexed user, uint256 krune, uint256 kdex);
    event Accrued(address indexed user, uint256 usdcAmount);
    event Unstaked(address indexed user, uint256 krune, uint256 kdex, uint256 kshrd);
    event YieldMintDeferred(address indexed user, uint256 kshrd);
    event YieldClaimed(address indexed user, uint256 kshrd);
    event FeeDeposited(address indexed from, uint256 usdcAmount, uint256 allocated, uint256 rewardPerWeight);
    event CollateralRatioUpdated(uint256 ratio, uint256 outstandingLiability, uint256 treasuryUsdc);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        krune = new KarmaRune(ADMIN);
        kdex = new KarmaDex(KDEX_SUPPLY, KDEX_TREASURY);
        kshrd = new KarmaShard(ADMIN);
        treasury = new Treasury(address(usdc), address(kdex), address(kshrd), OWNER);
        staking = new Staking(address(krune), address(kdex), address(kshrd), address(treasury), OWNER);

        vm.startPrank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));
        kshrd.grantRole(BURNER_ROLE, address(treasury));
        vm.stopPrank();

        _fund(ALICE, 1_000e18, 10_000e18);

        harness = new StakingHarness(address(krune), address(kdex), address(kshrd), address(treasury), OWNER);
    }

    /// @dev Each mint gets its own reason hash: KRUNE settles an earning event
    ///      exactly once on-chain, so a shared constant would revert on the
    ///      second staker. See test_mintEarned_* in KarmaRune.t.sol.
    uint256 internal reasonNonce;

    function _reason() internal returns (bytes32) {
        return keccak256(abi.encode(REASON, ++reasonNonce));
    }

    /// @dev Only KDEX gets an approval. KRUNE is soulbound — `approve` reverts,
    ///      and Staking never moves it.
    function _fund(address who, uint256 kruneAmt, uint256 kdexAmt) internal {
        vm.prank(ADMIN);
        krune.mintEarned(who, kruneAmt, _reason());
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(who, kdexAmt));
        vm.prank(who);
        kdex.approve(address(staking), type(uint256).max);
    }

    function _earnKrune(address who, uint256 amount) internal {
        vm.prank(ADMIN);
        krune.mintEarned(who, amount, _reason());
    }

    function _depositFees(uint256 amount) internal {
        usdc.mint(FEE_PAYER, amount);
        vm.startPrank(FEE_PAYER);
        usdc.approve(address(staking), amount);
        staking.depositFees(amount);
        vm.stopPrank();
    }

    struct Pos {
        uint256 krune;
        uint256 kdex;
        uint256 weight;
        uint256 startedAt;
        uint256 rewardPerWeightPaid;
        uint256 accruedUsdc;
        bool active;
    }

    function _position(address who) internal view returns (Pos memory p) {
        (p.krune, p.kdex, p.weight, p.startedAt, p.rewardPerWeightPaid, p.accruedUsdc, p.active) =
            staking.positions(who);
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTION & CONSTANTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_wiring() public view {
        assertEq(address(staking.krune()), address(krune));
        assertEq(address(staking.kdex()), address(kdex));
        assertEq(address(staking.kshrd()), address(kshrd));
        assertEq(address(staking.treasury()), address(treasury));
        assertEq(address(staking.usdc()), address(usdc), "the fee token is read from the Treasury");
        assertEq(staking.usdcScale(), 1e12, "so is its decimal scale");
        assertEq(staking.owner(), OWNER);
        assertFalse(staking.paused());
        assertEq(staking.totalWeight(), 0);
        assertEq(staking.rewardPerWeightStored(), 0);
        assertEq(staking.unallocatedFees(), 0);
    }

    function test_constructor_revertsOnZeroTokens() public {
        vm.expectRevert("STAKE: zero token");
        new Staking(address(0), address(kdex), address(kshrd), address(treasury), OWNER);
        vm.expectRevert("STAKE: zero token");
        new Staking(address(krune), address(0), address(kshrd), address(treasury), OWNER);
        vm.expectRevert("STAKE: zero token");
        new Staking(address(krune), address(kdex), address(0), address(treasury), OWNER);
    }

    function test_constructor_revertsOnZeroTreasury() public {
        vm.expectRevert("STAKE: zero treasury");
        new Staking(address(krune), address(kdex), address(kshrd), address(0), OWNER);
    }

    /// @notice Minting shards against one Treasury while another redeems them is
    ///         silent, unrecoverable and immutable. The constructor refuses.
    function test_constructor_revertsWhenTreasuryRedeemsADifferentShard() public {
        KarmaShard otherShard = new KarmaShard(ADMIN);
        Treasury otherTreasury = new Treasury(address(usdc), address(kdex), address(otherShard), OWNER);

        vm.expectRevert("STAKE: treasury/KSHRD mismatch");
        new Staking(address(krune), address(kdex), address(kshrd), address(otherTreasury), OWNER);

        // Control: the matching pair deploys fine.
        Staking ok = new Staking(address(krune), address(kdex), address(otherShard), address(otherTreasury), OWNER);
        assertEq(address(ok.kshrd()), address(otherShard));
    }

    function test_constructor_revertsOnZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Staking(address(krune), address(kdex), address(kshrd), address(treasury), address(0));
    }

    function test_constants() public view {
        assertEq(staking.LOCK_PERIOD(), 90 days);
        assertEq(staking.SCALE(), 1e18);
    }

    /**
     * @notice REGRESSION (was HIGH, economics): yield used to be a fixed
     *         `YIELD_RATE_PER_SEC` of token quantities, paid out in dollars,
     *         with nothing funding it. There is no rate any more — there is
     *         nothing to set, and nothing that accrues without revenue.
     */
    function test_thereIsNoYieldRateConstant() public {
        (bool ok,) = address(staking).call(abi.encodeWithSignature("YIELD_RATE_PER_SEC()"));
        assertFalse(ok, "the fixed dollar rate must be gone, not merely set to zero");
        (ok,) = address(staking).call(abi.encodeWithSignature("setYieldRate(uint256)", 1));
        assertFalse(ok);
    }

    /*//////////////////////////////////////////////////////////////
        DEPOSIT FEES — THE ONLY SOURCE OF YIELD
    //////////////////////////////////////////////////////////////*/

    function test_depositFees_movesUsdcToTheTreasuryAndCreditsStakers() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        assertEq(staking.totalWeight(), ALICE_WEIGHT);

        usdc.mint(FEE_PAYER, FEE_1000);
        vm.startPrank(FEE_PAYER);
        usdc.approve(address(staking), FEE_1000);

        // delta = 1e9 * 1e18 / 2e20 = 5_000_000
        vm.expectEmit(true, false, false, true, address(staking));
        emit FeeDeposited(FEE_PAYER, FEE_1000, FEE_1000, 5_000_000);
        staking.depositFees(FEE_1000);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(treasury)), FEE_1000, "fees land in the Treasury, not here");
        assertEq(usdc.balanceOf(address(staking)), 0);
        assertEq(staking.rewardPerWeightStored(), 5_000_000);
        assertEq(staking.unallocatedFees(), 0, "an exact division leaves no carry");
        assertEq(staking.pendingKshrd(ALICE), KSHRD_1000, "the only staker takes the whole pool");
    }

    function test_depositFees_emitsTheCollateralRatio() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);

        // Nothing is outstanding yet, so the ratio is unbounded.
        vm.expectEmit(false, false, false, true, address(staking));
        emit CollateralRatioUpdated(type(uint256).max, 0, FEE_1000);
        _depositFees(FEE_1000);

        // Close the position: 1,000 USDC of liability against 1,000 USDC held.
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();
        assertEq(treasury.totalOutstandingLiability(), FEE_1000);

        vm.expectEmit(false, false, false, true, address(staking));
        emit CollateralRatioUpdated(2e18, FEE_1000, 2 * FEE_1000);
        _depositFees(FEE_1000);
    }

    function test_depositFees_revertsWithoutAllowance() public {
        usdc.mint(STRANGER, 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(staking), 0, 1e6)
        );
        vm.prank(STRANGER);
        staking.depositFees(1e6);
    }

    /// @notice Fees deposited with nobody staked must not divide by zero and
    ///         must not vanish. They wait.
    function test_depositFees_withNoStakersIsHeldAsUnallocated() public {
        assertEq(staking.totalWeight(), 0);

        vm.expectEmit(true, false, false, true, address(staking));
        emit FeeDeposited(FEE_PAYER, FEE_1000, 0, 0);
        _depositFees(FEE_1000);

        assertEq(staking.rewardPerWeightStored(), 0, "nothing to divide by, so nothing is credited");
        assertEq(staking.unallocatedFees(), FEE_1000, "and nothing is lost either");
        assertEq(usdc.balanceOf(address(treasury)), FEE_1000, "the money is in the Treasury the whole time");
    }

    /// @notice The carry is folded into the next deposit that has weight — the
    ///         first stakers after a dry spell collect the backlog.
    function test_depositFees_unallocatedBacklogIsFoldedInOnTheNextDeposit() public {
        _depositFees(FEE_1000);
        assertEq(staking.unallocatedFees(), FEE_1000);

        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        assertEq(staking.pendingKshrd(ALICE), 0, "staking alone does not release the backlog");

        // The next deposit divides 1,000 carried + 1,000 new over Alice's weight.
        _depositFees(FEE_1000);

        assertEq(staking.unallocatedFees(), 0);
        assertEq(staking.pendingKshrd(ALICE), 2 * KSHRD_1000, "backlog plus new fees");
    }

    /// @notice A staker who joins after a deposit gets none of it.
    function test_depositFees_areNotRetroactive() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);

        _fund(BOB, 400e18, 100e18);
        vm.prank(BOB);
        staking.stake(400e18, 100e18);

        assertEq(staking.pendingKshrd(BOB), 0, "the checkpoint starts at the current accumulator");
        assertEq(staking.pendingKshrd(ALICE), KSHRD_1000, "and the earlier deposit is untouched");
    }

    /**
     * @notice Indivisible dust is carried, not credited. 1 USDC base unit over a
     *         weight of 3e20 rounds the per-weight delta down to 3, which pays
     *         out 0 — the unit stays in `unallocatedFees` (rounded up out of the
     *         pool) so it can never be claimed twice.
     */
    function test_depositFees_subUnitRemainderIsNeverPaidTwice() public {
        _fund(BOB, 900e18, 100e18); // weight = sqrt(9e20)*sqrt(1e20) = 3e10*1e10 = 3e20
        vm.prank(BOB);
        staking.stake(900e18, 100e18);
        assertEq(staking.totalWeight(), 3e20);

        _depositFees(1);

        // delta = floor(1 * 1e18 / 3e20) = 0 -> nothing becomes claimable at all.
        assertEq(staking.rewardPerWeightStored(), 0);
        assertEq(staking.unallocatedFees(), 1, "an unallocatable unit is carried, not credited");
        assertEq(staking.pendingKshrd(BOB), 0);
    }

    /// @notice The allocation can never hand out more than was put in, at any
    ///         weight or amount. This is the arithmetic the solvency invariant
    ///         rests on.
    function testFuzz_depositFees_allocatedNeverExceedsThePool(uint256 kruneAmt, uint256 kdexAmt, uint256 fee)
        public
    {
        kruneAmt = bound(kruneAmt, 1, 1_000e18);
        kdexAmt = bound(kdexAmt, 1, 10_000e18);
        fee = bound(fee, 0, 1_000_000e6);

        vm.prank(ALICE);
        staking.stake(kruneAmt, kdexAmt);

        uint256 carriedBefore = staking.unallocatedFees();
        _depositFees(fee);

        uint256 pool = carriedBefore + fee;
        uint256 allocated = pool - staking.unallocatedFees();
        assertLe(allocated, pool, "the pool cannot allocate more than it holds");
        assertLe(staking.pendingKshrd(ALICE) / staking.usdcScale(), pool, "nor can the sole staker earn more");
    }

    /*//////////////////////////////////////////////////////////////
        POOL SHARE — PROPORTIONAL, NOT SCHEDULED
    //////////////////////////////////////////////////////////////*/

    /// @notice The whitepaper's "the pool sits at 0% until there is revenue",
    ///         now true by construction: time alone accrues nothing.
    function test_noFeesMeansNoYieldNoMatterHowLongYouWait() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);

        vm.warp(block.timestamp + 3650 days);
        assertEq(staking.pendingKshrd(ALICE), 0, "ten years of nothing is still nothing");

        vm.prank(ALICE);
        assertEq(staking.unstake(), 0);
        assertEq(kshrd.totalSupply(), 0, "no revenue, no shards");
    }

    function test_poolShare_twoEqualWeightsSplitEvenly() public {
        _fund(BOB, 400e18, 100e18);
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.prank(BOB);
        staking.stake(400e18, 100e18);
        assertEq(staking.totalWeight(), 2 * ALICE_WEIGHT, "the geometric mean is symmetric");

        _depositFees(FEE_1000);

        assertEq(staking.pendingKshrd(ALICE), KSHRD_1000 / 2);
        assertEq(staking.pendingKshrd(BOB), KSHRD_1000 / 2);
    }

    /**
     * @notice The property the accumulator exists for: deposits made at
     *         different times are shared only among who was staked at the time.
     *
     *         t0  Alice stakes                       weights: A=2e20
     *         t1  deposit 1,000 -> all to Alice
     *         t2  Bob stakes                         weights: A=2e20, B=2e20
     *         t3  deposit 1,000 -> 500 each
     *         t4  Alice unstakes (1,500)             weights: B=2e20
     *         t5  deposit 1,000 -> all to Bob
     *         Totals: Alice 1,500, Bob 1,500, deposited 3,000. Nothing left over.
     */
    function test_poolShare_distributesAcrossDepositsAtDifferentTimes() public {
        _fund(BOB, 400e18, 100e18);

        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);

        vm.prank(BOB);
        staking.stake(400e18, 100e18);
        _depositFees(FEE_1000);

        assertEq(staking.pendingKshrd(ALICE), KSHRD_1000 + KSHRD_1000 / 2);
        assertEq(staking.pendingKshrd(BOB), KSHRD_1000 / 2);

        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        uint256 aliceMinted = staking.unstake();
        assertEq(aliceMinted, KSHRD_1000 + KSHRD_1000 / 2);
        assertEq(staking.totalWeight(), ALICE_WEIGHT, "only Bob's weight remains");

        _depositFees(FEE_1000);
        assertEq(staking.pendingKshrd(BOB), KSHRD_1000 + KSHRD_1000 / 2, "Bob alone takes the third deposit");

        vm.prank(BOB);
        uint256 bobMinted = staking.unstake();

        assertEq(aliceMinted + bobMinted, 3 * KSHRD_1000, "every deposited dollar reached a staker");
        assertEq(kshrd.totalSupply(), 3 * KSHRD_1000);
        assertEq(usdc.balanceOf(address(treasury)), 3 * FEE_1000, "and is sitting in the Treasury to pay it");
        assertEq(staking.unallocatedFees(), 0);
    }

    /// @notice A closed position stops earning immediately.
    function test_poolShare_aClosedPositionEarnsNothingFromLaterDeposits() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();

        _fund(BOB, 400e18, 100e18);
        vm.prank(BOB);
        staking.stake(400e18, 100e18);
        _depositFees(FEE_1000);

        assertEq(staking.pendingKshrd(ALICE), 0);
        assertEq(staking.pendingKshrd(BOB), KSHRD_1000);
    }

    /// @notice Topping up must settle the old weight first, or the new capital
    ///         would retroactively claim fees it was not present for.
    function test_poolShare_topUpDoesNotBackdate() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);

        vm.expectEmit(true, false, false, true, address(staking));
        emit Accrued(ALICE, FEE_1000);
        vm.prank(ALICE);
        staking.stake(300e18, 3_600e18); // -> 400e18 / 4_000e18, weight 4e20

        Pos memory p = _position(ALICE);
        assertEq(p.accruedUsdc, FEE_1000, "the earlier period is settled at the earlier weight");
        assertEq(p.weight, 4e20);
        assertEq(staking.totalWeight(), 4e20);
        assertEq(staking.pendingKshrd(ALICE), KSHRD_1000, "and the top-up adds nothing by itself");
    }

    /// @notice A whale that scrapes together 1 wei of KRUNE gets in, but the
    ///         geometric mean crushes their share of the pool.
    function test_geometricMeanSuppressesLopsidedWhale() public {
        _earnKrune(WHALE, 1);
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(WHALE, 50_000_000e18));
        vm.startPrank(WHALE);
        kdex.approve(address(staking), type(uint256).max);
        staking.stake(1, 50_000_000e18);
        vm.stopPrank();

        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);

        _depositFees(FEE_1000);

        uint256 whaleYield = staking.pendingKshrd(WHALE);
        uint256 aliceYield = staking.pendingKshrd(ALICE);

        // sqrt(1) * sqrt(5e25) = 7_071_067_811 against Alice's 2e20.
        assertLt(whaleYield, aliceYield / 1_000_000, "50M KDEX must not out-earn 100 KRUNE + 400 KDEX");
        assertGt(aliceYield, 0);
    }

    /*//////////////////////////////////////////////////////////////
                              TOTAL WEIGHT
    //////////////////////////////////////////////////////////////*/

    function test_totalWeight_tracksStakesAndExitsWithoutIterating() public {
        _fund(BOB, 400e18, 100e18);
        assertEq(staking.totalWeight(), 0);

        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        assertEq(staking.totalWeight(), ALICE_WEIGHT);

        vm.prank(BOB);
        staking.stake(400e18, 100e18);
        assertEq(staking.totalWeight(), 2 * ALICE_WEIGHT);

        // Top-up replaces the old weight rather than adding a second one.
        vm.prank(ALICE);
        staking.stake(300e18, 3_600e18);
        assertEq(staking.totalWeight(), 4e20 + ALICE_WEIGHT);

        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();
        assertEq(staking.totalWeight(), ALICE_WEIGHT);
        vm.prank(BOB);
        staking.unstake();
        assertEq(staking.totalWeight(), 0, "the last exit leaves it exactly empty");
    }

    function testFuzz_totalWeightEqualsTheSumOfActivePositions(uint256 aK, uint256 aD, uint256 bK, uint256 bD)
        public
    {
        aK = bound(aK, 1, 1_000e18);
        aD = bound(aD, 1, 10_000e18);
        bK = bound(bK, 1, 1_000e18);
        bD = bound(bD, 1, 10_000e18);
        _fund(BOB, 1_000e18, 10_000e18);

        vm.prank(ALICE);
        staking.stake(aK, aD);
        vm.prank(BOB);
        staking.stake(bK, bD);

        assertEq(staking.totalWeight(), _position(ALICE).weight + _position(BOB).weight);

        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();
        assertEq(staking.totalWeight(), _position(BOB).weight);
    }

    /*//////////////////////////////////////////////////////////////
        STAKE — KRUNE IS REFERENCED, KDEX IS ESCROWED
    //////////////////////////////////////////////////////////////*/

    function test_stake_happyPath() public {
        uint256 t0 = block.timestamp;

        vm.expectEmit(true, false, false, true, address(staking));
        emit Staked(ALICE, STAKE_KRUNE, STAKE_KDEX);
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);

        assertEq(krune.balanceOf(address(staking)), 0, "KRUNE never moves - it cannot");
        assertEq(krune.balanceOf(ALICE), 1_000e18, "the staker keeps every rune");
        assertEq(kdex.balanceOf(address(staking)), STAKE_KDEX, "only KDEX is escrowed");
        assertEq(kdex.balanceOf(ALICE), 10_000e18 - STAKE_KDEX);

        Pos memory p = _position(ALICE);
        assertEq(p.krune, STAKE_KRUNE);
        assertEq(p.kdex, STAKE_KDEX);
        assertEq(p.weight, ALICE_WEIGHT);
        assertEq(p.startedAt, t0);
        assertEq(p.rewardPerWeightPaid, 0);
        assertEq(p.accruedUsdc, 0);
        assertTrue(p.active);
    }

    /*//////////////////////////////////////////////////////////////
        ANTI-WHALE GATE — BOTH TOKENS REQUIRED
    //////////////////////////////////////////////////////////////*/

    function test_stake_revertsWithZeroKrune() public {
        vm.expectRevert("STAKE: need earned KRUNE (reputation)");
        vm.prank(ALICE);
        staking.stake(0, STAKE_KDEX);
    }

    function test_stake_revertsWithZeroKdex() public {
        vm.expectRevert("STAKE: need invested KDEX (capital)");
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, 0);
    }

    /// @notice The headline invariant: money alone buys nothing. A wallet
    ///         holding 50 million KDEX and zero KRUNE cannot open a position —
    ///         and since KRUNE is soulbound, it cannot buy its way to one either.
    function test_stake_whaleWithNoKruneCannotStake() public {
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(WHALE, 50_000_000e18));
        vm.startPrank(WHALE);
        kdex.approve(address(staking), type(uint256).max);

        assertEq(krune.balanceOf(WHALE), 0);

        vm.expectRevert("STAKE: need earned KRUNE (reputation)");
        staking.stake(0, 50_000_000e18);

        // Claiming KRUNE they do not hold fails on the balance check.
        vm.expectRevert("STAKE: KRUNE already staked or not held");
        staking.stake(1, 50_000_000e18);
        vm.stopPrank();

        assertFalse(_position(WHALE).active, "whale must have no position");
        assertEq(kdex.balanceOf(address(staking)), 0, "not a single KDEX may enter without KRUNE");
    }

    /// @notice Alice's reputation is not a resource anyone else can spend.
    function test_stake_cannotReferenceSomeoneElsesKrune() public {
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(BOB, 1_000e18));
        vm.startPrank(BOB);
        kdex.approve(address(staking), type(uint256).max);
        vm.expectRevert("STAKE: KRUNE already staked or not held");
        staking.stake(1, 1_000e18);
        vm.stopPrank();
        assertEq(krune.balanceOf(ALICE), 1_000e18, "untouched");
    }

    function test_stake_revertsWithoutKdexApproval() public {
        _earnKrune(STRANGER, 10e18);
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(STRANGER, 10e18));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(staking), 0, 1e18)
        );
        vm.prank(STRANGER);
        staking.stake(1e18, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
        STAKING BY REFERENCE — THE DOUBLE-COUNT GUARD
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The attack the balance check exists for: KRUNE is never escrowed,
     *         so a naive `balanceOf(msg.sender) >= kruneAmount` would let the
     *         SAME 1,000 KRUNE back an unbounded stack of top-ups. The check is
     *         against the position's running total instead.
     */
    function test_stake_topUpCannotReferenceTheSameKruneTwice() public {
        vm.prank(ALICE);
        staking.stake(1_000e18, 1e18); // the entire balance, referenced once
        assertEq(krune.balanceOf(ALICE), 1_000e18, "still in her wallet");

        vm.expectRevert("STAKE: KRUNE already staked or not held");
        vm.prank(ALICE);
        staking.stake(1_000e18, 1e18);

        vm.expectRevert("STAKE: KRUNE already staked or not held");
        vm.prank(ALICE);
        staking.stake(1, 1e18);

        assertEq(_position(ALICE).krune, 1_000e18, "the position never grew");
    }

    /// @notice ...and the same check lets an honest top-up through the moment
    ///         the reputation behind it actually exists.
    function test_stake_topUpIsAllowedOnceMoreKruneIsEarned() public {
        vm.prank(ALICE);
        staking.stake(1_000e18, 1e18);

        _earnKrune(ALICE, 500e18);
        vm.prank(ALICE);
        staking.stake(500e18, 1e18);

        assertEq(_position(ALICE).krune, 1_500e18);
        assertEq(krune.balanceOf(ALICE), 1_500e18, "and it is still all in her wallet");

        vm.expectRevert("STAKE: KRUNE already staked or not held");
        vm.prank(ALICE);
        staking.stake(1, 1e18);
    }

    /**
     * @notice Why the reference is safe at all: a staked balance cannot leave.
     *         Every transfer path on KRUNE reverts, so `p.krune` can never come
     *         to exceed what the staker holds.
     */
    function test_stake_referencedKruneCannotBeMovedAway() public {
        vm.prank(ALICE);
        staking.stake(1_000e18, 1e18);

        vm.startPrank(ALICE);
        vm.expectRevert("KRUNE: soulbound");
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        krune.transfer(BOB, 1_000e18);
        vm.expectRevert("KRUNE: soulbound");
        krune.approve(BOB, 1_000e18);
        vm.stopPrank();

        vm.expectRevert("KRUNE: soulbound");
        vm.prank(BOB);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        krune.transferFrom(ALICE, BOB, 1_000e18);

        assertEq(krune.balanceOf(ALICE), 1_000e18);
        assertGe(krune.balanceOf(ALICE), _position(ALICE).krune, "the reference is still fully backed");
    }

    /// @notice A closed position releases the reference, so the same KRUNE backs
    ///         the next stake — one at a time, forever.
    function test_stake_referenceIsReleasedOnUnstake() public {
        vm.prank(ALICE);
        staking.stake(1_000e18, 1e18);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();

        assertEq(_position(ALICE).krune, 0);
        vm.prank(ALICE);
        staking.stake(1_000e18, 1e18);
        assertEq(_position(ALICE).krune, 1_000e18);
    }

    /// @notice Generalised: whatever the sequence of stakes, a position can never
    ///         reference more KRUNE than its owner holds.
    function testFuzz_referencedKruneNeverExceedsTheBalance(uint256 first, uint256 second, uint256 earned) public {
        first = bound(first, 1, 1_000e18);
        second = bound(second, 1, 2_000e18);
        earned = bound(earned, 0, 1_000e18);

        vm.prank(ALICE);
        staking.stake(first, 1e18);
        _earnKrune(ALICE, earned);

        vm.prank(ALICE);
        try staking.stake(second, 1e18) {}
        catch (bytes memory) {}

        assertLe(_position(ALICE).krune, krune.balanceOf(ALICE), "a reference is always fully backed");
    }

    /*//////////////////////////////////////////////////////////////
                             STAKE — LOCK
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Topping up restarts the 90-day lock on the WHOLE position. Capital
     *         added on day 89 is not withdrawable on day 90 - it, and everything
     *         beside it, is locked until day 179. This is the deliberate cost of
     *         making the lock unconditional; see the note on `stake()`.
     */
    function test_stake_topUpRestartsTheLockOnTheWholePosition() public {
        vm.prank(ALICE);
        staking.stake(1e18, 1e18);
        uint256 t0 = block.timestamp;

        vm.warp(t0 + 90 days - 1);
        uint256 topUpAt = block.timestamp;
        vm.prank(ALICE);
        staking.stake(500e18, 5_000e18);

        assertEq(_position(ALICE).startedAt, topUpAt, "startedAt IS refreshed on top-up");

        // The old deposit was one second from maturing; it now waits again.
        vm.warp(t0 + 90 days);
        vm.expectRevert("STAKE: locked");
        vm.prank(ALICE);
        staking.unstake();

        vm.warp(topUpAt + 90 days - 1);
        vm.expectRevert("STAKE: locked");
        vm.prank(ALICE);
        staking.unstake();

        vm.warp(topUpAt + 90 days);
        vm.prank(ALICE);
        staking.unstake();
        assertEq(kdex.balanceOf(ALICE), 10_000e18, "principal comes back once the new term is served");
    }

    function test_stake_multipleUsersAreIndependent() public {
        _fund(WHALE, 500e18, 500e18);
        vm.prank(ALICE);
        staking.stake(100e18, 400e18);
        vm.prank(WHALE);
        staking.stake(500e18, 500e18);

        assertEq(_position(ALICE).kdex, 400e18);
        assertEq(_position(WHALE).kdex, 500e18);
        assertEq(krune.balanceOf(address(staking)), 0);
        assertEq(kdex.balanceOf(address(staking)), 900e18);
    }

    /*//////////////////////////////////////////////////////////////
                                 UNSTAKE
    //////////////////////////////////////////////////////////////*/

    function test_unstake_revertsBeforeLockElapses() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 90 days - 1);
        vm.expectRevert("STAKE: locked");
        vm.prank(ALICE);
        staking.unstake();
    }

    function test_unstake_succeedsAtExactly90Days() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);

        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        uint256 minted = staking.unstake();

        assertEq(minted, KSHRD_1000);
        assertEq(kshrd.balanceOf(ALICE), KSHRD_1000);
        assertEq(krune.balanceOf(ALICE), 1_000e18, "KRUNE was never taken, so nothing is returned");
        assertEq(kdex.balanceOf(ALICE), 10_000e18, "KDEX comes back in full");
    }

    function test_unstake_emitsAccruedThenUnstakedAndClearsPosition() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);
        vm.warp(block.timestamp + 90 days);

        vm.expectEmit(true, false, false, true, address(staking));
        emit Accrued(ALICE, FEE_1000);
        vm.expectEmit(true, false, false, true, address(staking));
        emit Unstaked(ALICE, STAKE_KRUNE, STAKE_KDEX, KSHRD_1000);
        vm.prank(ALICE);
        staking.unstake();

        Pos memory p = _position(ALICE);
        assertEq(p.krune, 0);
        assertEq(p.kdex, 0);
        assertEq(p.weight, 0);
        assertEq(p.startedAt, 0);
        assertEq(p.rewardPerWeightPaid, 0);
        assertEq(p.accruedUsdc, 0);
        assertFalse(p.active);
        assertEq(kdex.balanceOf(address(staking)), 0);
    }

    function test_unstake_revertsWithoutPosition() public {
        vm.expectRevert("STAKE: none");
        vm.prank(STRANGER);
        staking.unstake();
    }

    function test_unstake_cannotBeCalledTwice() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 90 days);
        vm.startPrank(ALICE);
        staking.unstake();
        vm.expectRevert("STAKE: none");
        staking.unstake();
        vm.stopPrank();
    }

    function test_unstake_dustShareMintsNothing() public {
        vm.prank(ALICE);
        staking.stake(1, 1); // weight 1
        _depositFees(1); // delta = 1e18, earned = 1 * 1e18 / 1e18 = 1 base unit

        vm.prank(ALICE);
        staking.stake(1, 1);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        assertEq(staking.unstake(), 1e12, "1 USDC base unit == 1e12 KSHRD");
    }

    /**
     * @notice The deployment-ordering hazard: a Staking deployed before (or
     *         instead of) its MINTER_ROLE grant cannot mint yield. That must
     *         cost the staker a delay, never their principal.
     */
    function test_unstake_returnsPrincipalWhenStakingLacksMinterRole() public {
        Staking orphan = new Staking(address(krune), address(kdex), address(kshrd), address(treasury), OWNER);
        vm.prank(ALICE);
        kdex.approve(address(orphan), type(uint256).max);
        vm.prank(ALICE);
        orphan.stake(STAKE_KRUNE, STAKE_KDEX);

        usdc.mint(FEE_PAYER, FEE_1000);
        vm.startPrank(FEE_PAYER);
        usdc.approve(address(orphan), FEE_1000);
        orphan.depositFees(FEE_1000);
        vm.stopPrank();

        // Control: the mint really would revert right now.
        assertFalse(kshrd.hasRole(MINTER_ROLE, address(orphan)));

        vm.warp(block.timestamp + 90 days);

        vm.expectEmit(true, false, false, true, address(orphan));
        emit YieldMintDeferred(ALICE, KSHRD_1000);
        vm.prank(ALICE);
        uint256 settled = orphan.unstake();

        assertEq(settled, KSHRD_1000, "unstake still reports the yield it settled");
        assertEq(kdex.balanceOf(ALICE), 10_000e18, "KDEX principal is out in full");
        assertEq(kdex.balanceOf(address(orphan)), 0, "nothing is left behind");

        // The yield is owed, not lost - and not mintable yet.
        assertEq(kshrd.balanceOf(ALICE), 0);
        assertEq(orphan.unclaimedYield(ALICE), KSHRD_1000);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(orphan), MINTER_ROLE
            )
        );
        vm.prank(ALICE);
        orphan.claimYield();

        // Once the wiring is repaired, the debt pays out in full, exactly once.
        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(orphan));

        vm.expectEmit(true, false, false, true, address(orphan));
        emit YieldClaimed(ALICE, KSHRD_1000);
        vm.prank(ALICE);
        assertEq(orphan.claimYield(), KSHRD_1000);

        assertEq(kshrd.balanceOf(ALICE), KSHRD_1000);
        assertEq(orphan.unclaimedYield(ALICE), 0);
        vm.expectRevert("STAKE: nothing to claim");
        vm.prank(ALICE);
        orphan.claimYield();
    }

    /**
     * @notice The revoke variant: an admin pulling MINTER_ROLE out from under a
     *         live Staking used to trap every staker's principal permanently,
     *         with no pause or owner action able to free it.
     */
    function test_unstake_returnsPrincipalAfterMinterRoleIsRevoked() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);
        vm.warp(block.timestamp + 90 days);

        vm.prank(ADMIN);
        kshrd.revokeRole(MINTER_ROLE, address(staking));

        vm.prank(ALICE);
        uint256 settled = staking.unstake();

        assertEq(settled, KSHRD_1000);
        assertEq(kdex.balanceOf(ALICE), 10_000e18, "principal does not depend on the yield path");
        assertEq(staking.unclaimedYield(ALICE), KSHRD_1000, "the claim survives the revoke");
        assertEq(kshrd.totalSupply(), 0);

        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));
        vm.prank(ALICE);
        staking.claimYield();
        assertEq(kshrd.balanceOf(ALICE), KSHRD_1000);
    }

    /// @notice A pause on top of a broken minter still cannot hold the principal.
    function test_unstake_returnsPrincipalWhenPausedAndMintingIsBroken() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);
        vm.warp(block.timestamp + 90 days);

        vm.prank(ADMIN);
        kshrd.revokeRole(MINTER_ROLE, address(staking));
        vm.prank(OWNER);
        staking.pause();

        vm.prank(ALICE);
        staking.unstake();

        assertEq(kdex.balanceOf(ALICE), 10_000e18);
        assertEq(staking.unclaimedYield(ALICE), KSHRD_1000);
    }

    /// @notice Deferred yield accumulates across cycles rather than overwriting.
    function test_claimYield_accumulatesAcrossDeferredUnstakes() public {
        vm.prank(ADMIN);
        kshrd.revokeRole(MINTER_ROLE, address(staking));

        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();

        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();

        assertEq(staking.unclaimedYield(ALICE), 2 * KSHRD_1000);

        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));
        vm.prank(ALICE);
        assertEq(staking.claimYield(), 2 * KSHRD_1000);
        assertEq(kshrd.balanceOf(ALICE), 2 * KSHRD_1000);
    }

    /// @notice On the happy path nothing is deferred - the mint is direct and
    ///         `unclaimedYield` stays empty, so `claimYield` has nothing to pay.
    function test_claimYield_isEmptyWhenMintingWorks() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();

        assertEq(kshrd.balanceOf(ALICE), KSHRD_1000);
        assertEq(staking.unclaimedYield(ALICE), 0);
        vm.expectRevert("STAKE: nothing to claim");
        vm.prank(ALICE);
        staking.claimYield();
    }

    /// @notice The deferral path must not become a way to mint someone else's
    ///         yield, or to mint the same debt twice.
    function test_claimYield_isPerUserAndCannotBeDoubleSpent() public {
        _fund(WHALE, 1_000e18, 10_000e18);
        vm.prank(ADMIN);
        kshrd.revokeRole(MINTER_ROLE, address(staking));

        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();

        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));

        assertEq(staking.unclaimedYield(WHALE), 0);
        vm.expectRevert("STAKE: nothing to claim");
        vm.prank(WHALE);
        staking.claimYield();

        vm.startPrank(ALICE);
        staking.claimYield();
        vm.expectRevert("STAKE: nothing to claim");
        staking.claimYield();
        vm.stopPrank();

        assertEq(kshrd.totalSupply(), KSHRD_1000, "the debt minted exactly once");
    }

    /*//////////////////////////////////////////////////////////////
                            PENDING KSHRD VIEW
    //////////////////////////////////////////////////////////////*/

    function test_pendingKshrd_zeroWithoutPosition() public view {
        assertEq(staking.pendingKshrd(STRANGER), 0);
    }

    function test_pendingKshrd_matchesMintedAmount() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(137e6);
        vm.warp(block.timestamp + 137 days);

        uint256 pending = staking.pendingKshrd(ALICE);
        vm.prank(ALICE);
        uint256 minted = staking.unstake();
        assertEq(minted, pending, "the view must not lie about what unstake will pay");
    }

    /*//////////////////////////////////////////////////////////////
        PAUSE — BLOCKS DEPOSITS, NEVER TRAPS PRINCIPAL
    //////////////////////////////////////////////////////////////*/

    function test_pause_blocksStake() public {
        vm.expectEmit(false, false, false, true, address(staking));
        emit Paused(OWNER);
        vm.prank(OWNER);
        staking.pause();
        assertTrue(staking.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
    }

    /// @notice The load-bearing safety property: a pause must never trap a
    ///         user's principal. unstake() is deliberately NOT pausable.
    function test_pause_doesNotBlockUnstake() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        _depositFees(FEE_1000);
        vm.warp(block.timestamp + 90 days);

        vm.prank(OWNER);
        staking.pause();
        assertTrue(staking.paused());

        vm.prank(ALICE);
        uint256 minted = staking.unstake();

        assertEq(minted, KSHRD_1000, "yield is still paid while paused");
        assertEq(kdex.balanceOf(ALICE), 10_000e18, "KDEX principal returned while paused");
        assertTrue(staking.paused(), "still paused afterwards - unstake does not unpause");
    }

    /// @notice Nor may a pause stop the pool being funded — fees paid while
    ///         paused still belong to the stakers who are locked in.
    function test_pause_doesNotBlockDepositFees() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.prank(OWNER);
        staking.pause();

        _depositFees(FEE_1000);
        assertEq(staking.pendingKshrd(ALICE), KSHRD_1000);
    }

    function test_unpause_reopensStaking() public {
        vm.startPrank(OWNER);
        staking.pause();
        vm.expectEmit(false, false, false, true, address(staking));
        emit Unpaused(OWNER);
        staking.unpause();
        vm.stopPrank();

        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        assertTrue(_position(ALICE).active);
    }

    function test_pause_revertsForNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        staking.pause();
    }

    function test_unpause_revertsForNonOwner() public {
        vm.prank(OWNER);
        staking.pause();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        staking.unpause();
    }

    function test_pause_revertsWhenAlreadyPaused() public {
        vm.startPrank(OWNER);
        staking.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        staking.pause();
        vm.stopPrank();
    }

    function test_unpause_revertsWhenNotPaused() public {
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vm.prank(OWNER);
        staking.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          FINDINGS — REGRESSION GUARDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice REGRESSION (was HIGH, design): the 90-day lock was bypassable.
     *         `stake()` did not refresh `startedAt` when topping up, so a wallet
     *         that opened a 1-wei position once and let it mature could, from
     *         then on, deposit ANY amount and withdraw it in the SAME BLOCK -
     *         5,000,000 KDEX locked for 2 seconds, at a setup cost of 2 wei.
     *         The lock now binds every deposit.
     */
    function test_seasonedDustPositionNoLongerBypassesTheLock() public {
        // Day 0: open a throwaway 1-wei position.
        vm.prank(ALICE);
        staking.stake(1, 1);
        uint256 t0 = block.timestamp;

        // Day 90: the dust position matured. Nothing else has happened.
        vm.warp(t0 + 90 days);

        // Deposit a real position. It is NOT withdrawable in the same block.
        vm.startPrank(ALICE);
        staking.stake(500e18, 5_000e18);
        assertEq(_position(ALICE).startedAt, t0 + 90 days, "startedAt IS refreshed by the top-up");

        vm.expectRevert("STAKE: locked");
        staking.unstake();

        // Nor at any point before the new term is served.
        vm.warp(t0 + 180 days - 1);
        vm.expectRevert("STAKE: locked");
        staking.unstake();
        vm.stopPrank();

        assertEq(kdex.balanceOf(address(staking)), 5_000e18 + 1, "the capital is still locked up");

        // A full 90 days after the deposit, and only then, it comes out.
        vm.warp(t0 + 180 days);
        vm.prank(ALICE);
        staking.unstake();
        assertEq(kdex.balanceOf(ALICE), 10_000e18);
    }

    /// @notice There is no early exit at all: no forfeiture path, no partial
    ///         withdrawal, no owner override.
    function test_thereIsNoEarlyExitPath() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 45 days);

        vm.expectRevert("STAKE: locked");
        vm.prank(ALICE);
        staking.unstake();

        (bool ok,) = address(staking).call(abi.encodeWithSignature("exitEarly()"));
        assertFalse(ok, "no early-exit function exists");
        (ok,) = address(staking).call(abi.encodeWithSignature("emergencyWithdraw()"));
        assertFalse(ok);
        (ok,) = address(staking).call(abi.encodeWithSignature("unstakePartial(uint256)", 1));
        assertFalse(ok);
        assertEq(kdex.balanceOf(address(staking)), STAKE_KDEX);
    }

    /// @notice The property above, generalised: no deposit is ever withdrawable
    ///         sooner than 90 days after it was made, whatever the history.
    function testFuzz_noDepositEscapesTheLock(uint32 seasoning, uint32 wait) public {
        seasoning = uint32(bound(seasoning, 0, 365 days));
        wait = uint32(bound(wait, 0, 90 days - 1));

        vm.prank(ALICE);
        staking.stake(1, 1);
        vm.warp(block.timestamp + seasoning);

        _earnKrune(ALICE, 500e18);
        vm.prank(ALICE);
        staking.stake(500e18, 5_000e18);
        uint256 depositedAt = block.timestamp;

        vm.warp(depositedAt + wait);
        vm.expectRevert("STAKE: locked");
        vm.prank(ALICE);
        staking.unstake();

        vm.warp(depositedAt + 90 days);
        vm.prank(ALICE);
        staking.unstake();
        assertEq(kdex.balanceOf(ALICE), 10_000e18);
    }

    /**
     * @notice REGRESSION (was MEDIUM, ops): `renounceOwnership()` was exposed and
     *         irreversible, and one call permanently destroyed the emergency
     *         pause. It now reverts for everyone, owner included.
     */
    function test_renounceOwnershipIsDisabled() public {
        vm.expectRevert("STAKE: renounce disabled");
        vm.prank(OWNER);
        staking.renounceOwnership();

        vm.expectRevert("STAKE: renounce disabled");
        vm.prank(STRANGER);
        staking.renounceOwnership();

        assertEq(staking.owner(), OWNER, "ownership is intact");

        // The pause survives, so deposits can still be stopped.
        vm.prank(OWNER);
        staking.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
    }

    /// @notice Disabling renounce must not disable handover.
    function test_transferOwnershipStillWorks() public {
        vm.prank(OWNER);
        staking.transferOwnership(STRANGER);
        assertEq(staking.owner(), STRANGER);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OWNER));
        vm.prank(OWNER);
        staking.pause();

        vm.prank(STRANGER);
        staking.pause();
        assertTrue(staking.paused(), "the new owner holds a working pause");

        vm.expectRevert("STAKE: renounce disabled");
        vm.prank(STRANGER);
        staking.renounceOwnership();
    }

    /*//////////////////////////////////////////////////////////////
                        GEOMETRIC MEAN — FUZZ / OVERFLOW
    //////////////////////////////////////////////////////////////*/

    /// @notice The whole point of sqrt(a)*sqrt(b): it must never revert, for
    ///         ANY pair of uint256 inputs.
    function testFuzz_geometricMeanNeverReverts(uint256 a, uint256 b) public view {
        uint256 g = harness.geometricMean(a, b);
        assertEq(g, harness.geometricMean(b, a), "geometric mean must be symmetric");
        assertEq(g, Math.sqrt(a) * Math.sqrt(b));
    }

    function test_geometricMeanSurvivesTheFullUint256Boundary() public view {
        uint256 max = type(uint256).max;
        uint256 root = Math.sqrt(max); // 2**128 - 1
        assertEq(root, 2 ** 128 - 1);
        assertEq(harness.geometricMean(max, max), root * root);
    }

    /// @notice Regression guard: the PREVIOUS sqrt(a*b) implementation panics on
    ///         exactly the inputs the current one handles. Two 18-decimal
    ///         balances of 2**128 wei each are enough to break it.
    function test_naiveSqrtOfProductOverflowsWhereCurrentImplSurvives() public {
        uint256 boundary = 2 ** 128;

        vm.expectRevert(stdError.arithmeticError);
        harness.naiveGeometricMean(boundary, boundary);

        vm.expectRevert(stdError.arithmeticError);
        harness.naiveGeometricMean(type(uint256).max, type(uint256).max);

        assertEq(harness.geometricMean(boundary, boundary), boundary, "current impl returns the exact answer");
    }

    function testFuzz_geometricMeanIsExactForPerfectSquares(uint128 x, uint128 y) public view {
        uint256 a = uint256(x) * uint256(x);
        uint256 b = uint256(y) * uint256(y);
        assertEq(harness.geometricMean(a, b), uint256(x) * uint256(y));
    }

    /// @notice sqrt(a)*sqrt(b) <= sqrt(a*b) always, and the shortfall is bounded
    ///         by sqrt(a) + sqrt(b) — i.e. rounding is always in the protocol's
    ///         favour, never the staker's.
    function testFuzz_geometricMeanUnderestimatesWithinBound(uint256 a, uint256 b) public view {
        // Bounded so that a * b itself still fits in uint256 and the exact
        // reference sqrt(a * b) can be computed at all.
        a = bound(a, 0, 1e38);
        b = bound(b, 0, 1e38);
        uint256 exact = Math.sqrt(a * b);
        uint256 g = harness.geometricMean(a, b);
        assertLe(g, exact, "must never over-pay");
        assertLe(exact - g, Math.sqrt(a) + Math.sqrt(b), "shortfall bound");
    }

    function testFuzz_geometricMeanIsMonotonic(uint256 a, uint256 b, uint256 delta) public view {
        a = bound(a, 0, 1e60);
        b = bound(b, 0, 1e60);
        delta = bound(delta, 0, 1e60);
        assertLe(harness.geometricMean(a, b), harness.geometricMean(a + delta, b));
        assertLe(harness.geometricMean(a, b), harness.geometricMean(a, b + delta));
    }

    /*//////////////////////////////////////////////////////////////
                             SOLVENCY (UNIT + FUZZ)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice THE invariant this redesign exists for, at unit scale: however the
     *         stakes and the deposits are arranged, the KSHRD minted against
     *         them never exceeds the USDC that funded them.
     */
    function testFuzz_mintedKshrdNeverExceedsDepositedFees(
        uint256 aK,
        uint256 aD,
        uint256 bK,
        uint256 bD,
        uint256 fee1,
        uint256 fee2
    ) public {
        aK = bound(aK, 1, 1_000e18);
        aD = bound(aD, 1, 10_000e18);
        bK = bound(bK, 1, 1_000e18);
        bD = bound(bD, 1, 10_000e18);
        fee1 = bound(fee1, 0, 500_000e6);
        fee2 = bound(fee2, 0, 500_000e6);
        _fund(BOB, 1_000e18, 10_000e18);

        _depositFees(fee1); // arrives with nobody staked -> carried

        vm.prank(ALICE);
        staking.stake(aK, aD);
        _depositFees(fee2);

        vm.prank(BOB);
        staking.stake(bK, bD);

        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();
        vm.prank(BOB);
        staking.unstake();

        assertLe(
            kshrd.totalSupply(),
            (fee1 + fee2) * staking.usdcScale(),
            "KSHRD minted must never exceed USDC deposited as fees"
        );
        assertGe(usdc.balanceOf(address(treasury)), treasury.totalOutstandingLiability(), "every claim is funded");
    }

    /// @notice The escrow side: KDEX held here always covers every open position.
    function testFuzz_contractHoldsEveryEscrowedPrincipal(uint256 aK, uint256 aD, uint256 bK, uint256 bD) public {
        aK = bound(aK, 1, 1_000e18);
        aD = bound(aD, 1, 10_000e18);
        bK = bound(bK, 1, 1_000e18);
        bD = bound(bD, 1, 10_000e18);
        _fund(WHALE, 1_000e18, 10_000e18);

        vm.prank(ALICE);
        staking.stake(aK, aD);
        vm.prank(WHALE);
        staking.stake(bK, bD);

        assertGe(kdex.balanceOf(address(staking)), _position(ALICE).kdex + _position(WHALE).kdex);
        assertEq(krune.balanceOf(address(staking)), 0, "no KRUNE is ever held here");

        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();
        assertGe(kdex.balanceOf(address(staking)), _position(WHALE).kdex, "Alice's exit must not eat Whale's KDEX");
    }
}
