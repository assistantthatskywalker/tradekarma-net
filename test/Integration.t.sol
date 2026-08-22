// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {KarmaRune} from "../contracts/KarmaRune.sol";
import {KarmaDex} from "../contracts/KarmaDex.sol";
import {KarmaShard} from "../contracts/KarmaShard.sol";
import {Staking} from "../contracts/Staking.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @notice The full loop: earn KRUNE -> stake it alongside KDEX -> platform fees
 *         arrive -> unstake -> receive KSHRD -> redeem at the Treasury for USDC.
 *         Exact balances asserted at every hop.
 *
 *         The v2 shape of this loop is that step 3 is not optional. Nothing
 *         accrues from waiting; a staker's yield is a share of USDC that real
 *         revenue already put in the Treasury.
 */
contract IntegrationTest is Test {
    KarmaRune internal krune;
    KarmaDex internal kdex;
    KarmaShard internal kshrd;
    Staking internal staking;
    Treasury internal treasury;
    MockERC20 internal usdc;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant OWNER = address(0xB0B);
    address internal constant DISTRIBUTOR = address(0x7EA5);
    address internal constant ALICE = address(0xA11);
    address internal constant WHALE = address(0x1A26E);
    address internal constant FEE_PAYER = address(0xFEE);

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 internal constant ADMIN_ROLE = bytes32(0);

    uint256 internal constant KDEX_SUPPLY = 100_000_000e18;

    // Weight = sqrt(100e18) * sqrt(400e18) = 1e10 * 2e10 = 2e20 (exact).
    uint256 internal constant EARNED_KRUNE = 100e18;
    uint256 internal constant BOUGHT_KDEX = 400e18;
    uint256 internal constant FEES = 1_000e6; // 1,000.000000 USDC of platform fees
    uint256 internal constant YIELD = 1_000e18; // the sole staker's share, in KSHRD

    bytes32 internal constant REASON = keccak256("shipped:on-time");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        krune = new KarmaRune(ADMIN);
        kdex = new KarmaDex(KDEX_SUPPLY, DISTRIBUTOR);
        kshrd = new KarmaShard(ADMIN);
        treasury = new Treasury(address(usdc), address(kdex), address(kshrd), OWNER);
        staking = new Staking(address(krune), address(kdex), address(kshrd), address(treasury), OWNER);

        vm.startPrank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));
        kshrd.grantRole(BURNER_ROLE, address(treasury));
        vm.stopPrank();

        // Treasury also holds KDEX for the keepback path.
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(address(treasury), 1_000_000e18));
    }

    function _depositFees(uint256 amount) internal {
        usdc.mint(FEE_PAYER, amount);
        vm.startPrank(FEE_PAYER);
        usdc.approve(address(staking), amount);
        staking.depositFees(amount);
        vm.stopPrank();
    }

    function test_fullLifecycle_earnStakeFundUnstakeRedeem() public {
        // ---------- 1. EARN. KRUNE is minted, never bought. ----------
        assertEq(krune.balanceOf(ALICE), 0);
        vm.prank(ADMIN);
        krune.mintEarned(ALICE, EARNED_KRUNE, REASON);
        assertEq(krune.balanceOf(ALICE), EARNED_KRUNE);

        // ---------- 2. BUY. KDEX is acquired on the open market. ----------
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(ALICE, BOUGHT_KDEX));

        // ---------- 3. STAKE. Both halves required; only KDEX moves. ----------
        uint256 t0 = block.timestamp;
        vm.startPrank(ALICE);
        kdex.approve(address(staking), BOUGHT_KDEX);
        staking.stake(EARNED_KRUNE, BOUGHT_KDEX);
        vm.stopPrank();

        assertEq(krune.balanceOf(ALICE), EARNED_KRUNE, "reputation stays with its owner");
        assertEq(krune.balanceOf(address(staking)), 0);
        assertEq(kdex.balanceOf(ALICE), 0);
        assertEq(kdex.balanceOf(address(staking)), BOUGHT_KDEX);
        assertEq(staking.totalWeight(), 2e20);
        assertEq(staking.pendingKshrd(ALICE), 0);

        // ---------- 4. REVENUE. Waiting alone earns nothing. ----------
        vm.warp(t0 + 45 days);
        assertEq(staking.pendingKshrd(ALICE), 0, "no fees, no yield");
        _depositFees(FEES);
        assertEq(staking.pendingKshrd(ALICE), YIELD, "the sole staker takes the whole pool");
        assertEq(usdc.balanceOf(address(treasury)), FEES, "and the money to pay it is already here");

        // ---------- 5. UNSTAKE. KDEX back + KSHRD minted. ----------
        vm.warp(t0 + 90 days);
        vm.prank(ALICE);
        uint256 minted = staking.unstake();

        assertEq(minted, YIELD);
        assertEq(kdex.balanceOf(ALICE), BOUGHT_KDEX, "KDEX principal returned in full");
        assertEq(krune.balanceOf(ALICE), EARNED_KRUNE, "KRUNE was never held by anyone else");
        assertEq(kshrd.totalSupply(), YIELD, "KSHRD supply == outstanding claims");
        assertEq(treasury.collateralRatio(), 1e18, "exactly collateralised, by construction");

        // ---------- 6. REDEEM at the Treasury for USDC. ----------
        vm.startPrank(ALICE);
        kshrd.approve(address(treasury), YIELD);
        uint256 paid = treasury.redeem(YIELD, true);
        vm.stopPrank();

        assertEq(paid, FEES, "every fee dollar deposited comes back out as a redemption");
        assertEq(usdc.balanceOf(ALICE), FEES);
        assertEq(usdc.balanceOf(address(treasury)), 0);
        assertEq(kshrd.balanceOf(ALICE), 0, "pool-share yield is a whole number of USDC units - no dust");
        assertEq(kshrd.totalSupply(), 0);

        // ---------- 7. Ledger closes. ----------
        assertEq(krune.totalSupply(), EARNED_KRUNE, "no KRUNE was created or destroyed by the loop");
        assertEq(kdex.totalSupply(), KDEX_SUPPLY, "KDEX supply is still fixed");
    }

    /// @notice The KDEX keepback branch ships OFF and stays off until the owner
    ///         supplies a price. There is no KDEX market, so there is no honest
    ///         rate to hardcode.
    function test_fullLifecycle_kdexKeepbackIsDisabledUntilPriced() public {
        _stakeAndEarn();

        vm.startPrank(ALICE);
        kshrd.approve(address(treasury), YIELD);
        vm.expectRevert("TREAS: KDEX redemption disabled");
        treasury.redeem(YIELD, false);
        vm.stopPrank();

        assertEq(kshrd.balanceOf(ALICE), YIELD, "nothing burned while the branch is shut");

        // A market appears and the owner prices it at $2 per KDEX.
        vm.prank(OWNER);
        treasury.setKshrdPerKdexRate(2e18);

        vm.prank(ALICE);
        uint256 paid = treasury.redeem(YIELD, false);

        // 1,000 KSHRD / $2 = 500 KDEX, +10% keepback = 550 KDEX.
        assertEq(paid, 550e18);
        assertEq(kdex.balanceOf(ALICE), BOUGHT_KDEX + 550e18, "principal plus the KDEX payout");
        assertEq(kshrd.totalSupply(), 0);
        assertEq(usdc.balanceOf(address(treasury)), FEES, "USDC float untouched by the KDEX branch");
    }

    /// @dev Runs the loop up to "Alice holds YIELD KSHRD and her KDEX back".
    function _stakeAndEarn() internal {
        vm.prank(ADMIN);
        krune.mintEarned(ALICE, EARNED_KRUNE, REASON);
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(ALICE, BOUGHT_KDEX));

        vm.startPrank(ALICE);
        kdex.approve(address(staking), BOUGHT_KDEX);
        staking.stake(EARNED_KRUNE, BOUGHT_KDEX);
        vm.stopPrank();

        _depositFees(FEES);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        assertEq(staking.unstake(), YIELD);
    }

    /// @notice The same loop, attempted by a wallet that bought its way in.
    ///         It cannot even start, and with KRUNE soulbound there is no OTC
    ///         market to start it from either.
    function test_fullLifecycle_isClosedToPureCapital() public {
        vm.prank(ADMIN);
        krune.mintEarned(ALICE, EARNED_KRUNE, REASON);
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(WHALE, 10_000_000e18));

        vm.startPrank(WHALE);
        kdex.approve(address(staking), type(uint256).max);
        vm.expectRevert("STAKE: need earned KRUNE (reputation)");
        staking.stake(0, 10_000_000e18);
        vm.expectRevert("STAKE: KRUNE already staked or not held");
        staking.stake(1, 10_000_000e18);
        vm.stopPrank();

        // Nor can the whale buy the reputation it lacks, at any price.
        vm.expectRevert("KRUNE: soulbound");
        vm.prank(ALICE);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        krune.transfer(WHALE, EARNED_KRUNE);

        assertEq(kshrd.totalSupply(), 0);
        assertEq(usdc.balanceOf(WHALE), 0, "no capital-only path to the Treasury exists");
    }

    /// @notice Two stakers over the same window: payouts are proportional to the
    ///         geometric mean, and the Treasury settles both exactly.
    function test_twoStakersSplitTheSamePool() public {
        // Distinct reason hashes: one earning event mints once, on-chain.
        vm.startPrank(ADMIN);
        krune.mintEarned(ALICE, 100e18, keccak256("shipped:on-time:alice"));
        krune.mintEarned(WHALE, 400e18, keccak256("shipped:on-time:whale"));
        vm.stopPrank();
        vm.startPrank(DISTRIBUTOR);
        assertTrue(kdex.transfer(ALICE, 400e18));
        assertTrue(kdex.transfer(WHALE, 100e18));
        vm.stopPrank();

        vm.startPrank(ALICE);
        kdex.approve(address(staking), type(uint256).max);
        staking.stake(100e18, 400e18);
        vm.stopPrank();

        vm.startPrank(WHALE);
        kdex.approve(address(staking), type(uint256).max);
        staking.stake(400e18, 100e18);
        vm.stopPrank();

        _depositFees(FEES);
        vm.warp(block.timestamp + 90 days);

        vm.prank(ALICE);
        uint256 aliceYield = staking.unstake();
        vm.prank(WHALE);
        uint256 whaleYield = staking.unstake();

        assertEq(aliceYield, YIELD / 2);
        assertEq(whaleYield, YIELD / 2, "geometric mean is symmetric - same product, same share");
        assertEq(kshrd.totalSupply(), YIELD);

        vm.startPrank(ALICE);
        kshrd.approve(address(treasury), aliceYield);
        treasury.redeem(aliceYield, true);
        vm.stopPrank();
        vm.startPrank(WHALE);
        kshrd.approve(address(treasury), whaleYield);
        treasury.redeem(whaleYield, true);
        vm.stopPrank();

        assertEq(usdc.balanceOf(ALICE), FEES / 2);
        assertEq(usdc.balanceOf(WHALE), FEES / 2);
        assertEq(usdc.balanceOf(address(treasury)), 0, "the pool paid out exactly what went in");
        assertEq(kshrd.totalSupply(), 0);
    }

    /// @notice Restaking after a full cycle works: the position is cleanly reset
    ///         and the KRUNE reference is free to back the next one.
    function test_lifecycleRepeats() public {
        vm.prank(ADMIN);
        krune.mintEarned(ALICE, EARNED_KRUNE, REASON);
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(ALICE, BOUGHT_KDEX));

        vm.prank(ALICE);
        kdex.approve(address(staking), type(uint256).max);

        vm.prank(ALICE);
        staking.stake(EARNED_KRUNE, BOUGHT_KDEX);
        _depositFees(FEES);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();

        uint256 t1 = block.timestamp;
        vm.prank(ALICE);
        staking.stake(EARNED_KRUNE, BOUGHT_KDEX);
        (,,, uint256 startedAt,,,) = staking.positions(ALICE);
        assertEq(startedAt, t1, "the second cycle starts a fresh lock");

        vm.expectRevert("STAKE: locked");
        vm.prank(ALICE);
        staking.unstake();

        _depositFees(FEES);
        vm.warp(t1 + 90 days);
        vm.prank(ALICE);
        uint256 second = staking.unstake();

        assertEq(second, YIELD);
        assertEq(kshrd.balanceOf(ALICE), 2 * YIELD, "two funded cycles, two full payouts");
    }

    /**
     * @notice The system-level statement of the redesign: across an arbitrary
     *         interleaving of stakes, fee deposits and exits, the Treasury never
     *         owes more USDC than it holds.
     */
    function test_treasuryIsNeverUnderCollateralised() public {
        vm.startPrank(ADMIN);
        krune.mintEarned(ALICE, 100e18, keccak256("a"));
        krune.mintEarned(WHALE, 400e18, keccak256("w"));
        vm.stopPrank();
        vm.startPrank(DISTRIBUTOR);
        assertTrue(kdex.transfer(ALICE, 400e18));
        assertTrue(kdex.transfer(WHALE, 100e18));
        vm.stopPrank();

        _depositFees(FEES); // before anyone stakes at all

        vm.startPrank(ALICE);
        kdex.approve(address(staking), type(uint256).max);
        staking.stake(100e18, 400e18);
        vm.stopPrank();
        _assertSolvent();

        _depositFees(FEES);
        _assertSolvent();

        vm.startPrank(WHALE);
        kdex.approve(address(staking), type(uint256).max);
        staking.stake(400e18, 100e18);
        vm.stopPrank();
        _depositFees(FEES);
        _assertSolvent();

        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();
        _assertSolvent();
        vm.prank(WHALE);
        staking.unstake();
        _assertSolvent();

        vm.startPrank(ALICE);
        kshrd.approve(address(treasury), type(uint256).max);
        treasury.redeem(kshrd.balanceOf(ALICE), true);
        vm.stopPrank();
        _assertSolvent();

        assertLe(kshrd.totalSupply() / 1e12, 3 * FEES, "claims never exceeded the fees that funded them");
    }

    function _assertSolvent() internal view {
        assertGe(
            usdc.balanceOf(address(treasury)),
            treasury.totalOutstandingLiability(),
            "the Treasury must always hold every dollar it owes"
        );
        if (treasury.totalOutstandingLiability() > 0) {
            assertGe(treasury.collateralRatio(), 1e18, "collateral ratio must never fall below 1");
        }
    }
}
