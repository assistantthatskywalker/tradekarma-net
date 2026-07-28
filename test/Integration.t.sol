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
 * @notice The full loop the previous architecture left broken:
 *         earn KRUNE -> stake with KDEX -> wait 90 days -> unstake -> receive
 *         KSHRD -> redeem at the Treasury for USDC. Exact balances asserted at
 *         every hop.
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

    // Derivation in Staking.t.sol: sqrt(100e18)*sqrt(400e18) = 2e20;
    // 2e20 * (317_097_919 * 7_776_000) / 1e18 = 493_150_683_628_800_000
    uint256 internal constant EARNED_KRUNE = 100e18;
    uint256 internal constant BOUGHT_KDEX = 400e18;
    uint256 internal constant YIELD_90D = 493_150_683_628_800_000;
    uint256 internal constant USDC_PAID = 493_150; // 0.493150 USDC
    uint256 internal constant KSHRD_DUST = YIELD_90D - USDC_PAID * 1e12;

    bytes32 internal constant REASON = keccak256("shipped:on-time");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        krune = new KarmaRune(ADMIN);
        kdex = new KarmaDex(KDEX_SUPPLY, DISTRIBUTOR);
        kshrd = new KarmaShard(ADMIN);
        staking = new Staking(address(krune), address(kdex), address(kshrd), OWNER);
        treasury = new Treasury(address(usdc), address(kdex), address(kshrd), OWNER);

        vm.startPrank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));
        kshrd.grantRole(BURNER_ROLE, address(treasury));
        vm.stopPrank();

        // Platform fees back the yield.
        usdc.mint(FEE_PAYER, 10_000e6);
        vm.startPrank(FEE_PAYER);
        usdc.approve(address(treasury), 10_000e6);
        treasury.depositFees(10_000e6);
        vm.stopPrank();

        // Treasury also holds KDEX for the keepback path.
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(address(treasury), 1_000_000e18));
    }

    function test_fullLifecycle_earnStakeWaitUnstakeRedeem() public {
        // ---------- 1. EARN. KRUNE is minted, never bought. ----------
        assertEq(krune.balanceOf(ALICE), 0);
        vm.prank(ADMIN);
        krune.mintEarned(ALICE, EARNED_KRUNE, REASON);
        assertEq(krune.balanceOf(ALICE), EARNED_KRUNE);
        assertEq(krune.totalSupply(), EARNED_KRUNE);

        // ---------- 2. BUY. KDEX is acquired on the open market. ----------
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(ALICE, BOUGHT_KDEX));
        assertEq(kdex.balanceOf(ALICE), BOUGHT_KDEX);

        // ---------- 3. STAKE. Both halves required. ----------
        uint256 t0 = block.timestamp;
        vm.startPrank(ALICE);
        krune.approve(address(staking), EARNED_KRUNE);
        kdex.approve(address(staking), BOUGHT_KDEX);
        staking.stake(EARNED_KRUNE, BOUGHT_KDEX);
        vm.stopPrank();

        assertEq(krune.balanceOf(ALICE), 0);
        assertEq(kdex.balanceOf(ALICE), 0);
        assertEq(krune.balanceOf(address(staking)), EARNED_KRUNE);
        assertEq(kdex.balanceOf(address(staking)), BOUGHT_KDEX);
        assertEq(staking.pendingKshrd(ALICE), 0);

        // ---------- 4. WAIT 90 days. ----------
        vm.warp(t0 + 90 days);
        assertEq(staking.pendingKshrd(ALICE), YIELD_90D);

        // ---------- 5. UNSTAKE. Principal back + KSHRD minted. ----------
        vm.prank(ALICE);
        uint256 minted = staking.unstake();

        assertEq(minted, YIELD_90D);
        assertEq(krune.balanceOf(ALICE), EARNED_KRUNE, "KRUNE principal returned in full");
        assertEq(kdex.balanceOf(ALICE), BOUGHT_KDEX, "KDEX principal returned in full");
        assertEq(kshrd.balanceOf(ALICE), YIELD_90D);
        assertEq(kshrd.totalSupply(), YIELD_90D, "KSHRD supply == outstanding claims");
        assertEq(krune.balanceOf(address(staking)), 0);
        assertEq(kdex.balanceOf(address(staking)), 0);

        // ---------- 6. REDEEM at the Treasury for USDC. ----------
        uint256 treasuryUsdcBefore = usdc.balanceOf(address(treasury));
        vm.prank(ALICE);
        kshrd.approve(address(treasury), YIELD_90D);
        vm.prank(ALICE);
        uint256 paid = treasury.redeem(YIELD_90D, true);

        assertEq(paid, USDC_PAID, "0.493150 USDC for 0.4931506836288 KSHRD");
        assertEq(usdc.balanceOf(ALICE), USDC_PAID);
        assertEq(usdc.balanceOf(address(treasury)), treasuryUsdcBefore - USDC_PAID);
        assertEq(kshrd.balanceOf(ALICE), KSHRD_DUST, "sub-unit dust survives the redemption");
        assertEq(kshrd.totalSupply(), KSHRD_DUST, "supply still equals outstanding claims");

        // ---------- 7. Ledger closes. ----------
        assertEq(krune.totalSupply(), EARNED_KRUNE, "no KRUNE was created or destroyed by the loop");
        assertEq(kdex.totalSupply(), KDEX_SUPPLY, "KDEX supply is still fixed");
    }

    function test_fullLifecycle_redeemAsKdexTakesTheKeepbackBonus() public {
        vm.prank(ADMIN);
        krune.mintEarned(ALICE, EARNED_KRUNE, REASON);
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(ALICE, BOUGHT_KDEX));

        vm.startPrank(ALICE);
        krune.approve(address(staking), EARNED_KRUNE);
        kdex.approve(address(staking), BOUGHT_KDEX);
        staking.stake(EARNED_KRUNE, BOUGHT_KDEX);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();

        vm.prank(ALICE);
        kshrd.approve(address(treasury), YIELD_90D);
        vm.prank(ALICE);
        uint256 paid = treasury.redeem(YIELD_90D, false);

        assertEq(paid, YIELD_90D + YIELD_90D / 10);
        assertEq(kdex.balanceOf(ALICE), BOUGHT_KDEX + paid, "principal plus the KDEX payout");
        assertEq(kshrd.balanceOf(ALICE), 0, "no dust in the KDEX path - everything burns");
        assertEq(kshrd.totalSupply(), 0);
        assertEq(usdc.balanceOf(address(treasury)), 10_000e6, "USDC float untouched");
    }

    /// @notice The same loop, attempted by a wallet that bought its way in.
    ///         It cannot even start.
    function test_fullLifecycle_isClosedToPureCapital() public {
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(WHALE, 10_000_000e18));

        vm.startPrank(WHALE);
        kdex.approve(address(staking), type(uint256).max);
        krune.approve(address(staking), type(uint256).max);
        vm.expectRevert("STAKE: need earned KRUNE (reputation)");
        staking.stake(0, 10_000_000e18);
        vm.stopPrank();

        assertEq(kshrd.totalSupply(), 0);
        assertEq(usdc.balanceOf(WHALE), 0, "no capital-only path to the Treasury exists");
    }

    /// @notice Two stakers over the same window: payouts are proportional to the
    ///         geometric mean, and the Treasury settles both exactly.
    function test_twoStakersSettleIndependently() public {
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
        krune.approve(address(staking), type(uint256).max);
        kdex.approve(address(staking), type(uint256).max);
        staking.stake(100e18, 400e18);
        vm.stopPrank();

        vm.startPrank(WHALE);
        krune.approve(address(staking), type(uint256).max);
        kdex.approve(address(staking), type(uint256).max);
        staking.stake(400e18, 100e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);

        vm.prank(ALICE);
        uint256 aliceYield = staking.unstake();
        vm.prank(WHALE);
        uint256 whaleYield = staking.unstake();

        assertEq(aliceYield, YIELD_90D);
        assertEq(whaleYield, YIELD_90D, "geometric mean is symmetric - same product, same yield");
        assertEq(kshrd.totalSupply(), 2 * YIELD_90D);

        vm.startPrank(ALICE);
        kshrd.approve(address(treasury), aliceYield);
        treasury.redeem(aliceYield, true);
        vm.stopPrank();
        vm.startPrank(WHALE);
        kshrd.approve(address(treasury), whaleYield);
        treasury.redeem(whaleYield, true);
        vm.stopPrank();

        assertEq(usdc.balanceOf(ALICE), USDC_PAID);
        assertEq(usdc.balanceOf(WHALE), USDC_PAID);
        assertEq(kshrd.totalSupply(), 2 * KSHRD_DUST);
    }

    /// @notice Restaking after a full cycle works: the position is cleanly reset.
    function test_lifecycleRepeats() public {
        vm.prank(ADMIN);
        krune.mintEarned(ALICE, EARNED_KRUNE, REASON);
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(ALICE, BOUGHT_KDEX));

        vm.startPrank(ALICE);
        krune.approve(address(staking), type(uint256).max);
        kdex.approve(address(staking), type(uint256).max);

        staking.stake(EARNED_KRUNE, BOUGHT_KDEX);
        vm.warp(block.timestamp + 90 days);
        staking.unstake();

        uint256 t1 = block.timestamp;
        staking.stake(EARNED_KRUNE, BOUGHT_KDEX);
        (,, uint256 startedAt,,,) = staking.positions(ALICE);
        assertEq(startedAt, t1, "the second cycle starts a fresh lock");

        vm.expectRevert("STAKE: locked");
        staking.unstake();

        vm.warp(t1 + 90 days);
        uint256 second = staking.unstake();
        vm.stopPrank();

        assertEq(second, YIELD_90D);
        assertEq(kshrd.balanceOf(ALICE), 2 * YIELD_90D, "two full cycles, two full payouts");
    }
}
