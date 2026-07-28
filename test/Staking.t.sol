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
import {StakingHarness} from "./harness/StakingHarness.sol";

contract StakingTest is Test {
    KarmaRune internal krune;
    KarmaDex internal kdex;
    KarmaShard internal kshrd;
    Staking internal staking;
    StakingHarness internal harness;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant OWNER = address(0xB0B);
    address internal constant KDEX_TREASURY = address(0x7EA5);
    address internal constant ALICE = address(0xA11);
    address internal constant WHALE = address(0x1A26E);
    address internal constant STRANGER = address(0xDEAD);

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 internal constant ADMIN_ROLE = bytes32(0);

    uint256 internal constant KDEX_SUPPLY = 100_000_000e18;
    bytes32 internal constant REASON = keccak256("earned");

    /**
     * Reference yield, computed independently of the implementation:
     *   geometric mean of 100e18 KRUNE and 400e18 KDEX
     *     = sqrt(1e20) * sqrt(4e20) = 1e10 * 2e10 = 2e20        (exact, both perfect squares)
     *   rate * elapsed = 317_097_919 * 7_776_000 = 2_465_753_418_144_000
     *   yield = 2e20 * 2_465_753_418_144_000 / 1e18
     *         = 200 * 2_465_753_418_144_000
     *         = 493_150_683_628_800_000                          (= 0.4931506836288 KSHRD)
     * Sanity: 1% of 200 for 90/365 of a year = 0.49315... KSHRD. Correct.
     */
    uint256 internal constant STAKE_KRUNE = 100e18;
    uint256 internal constant STAKE_KDEX = 400e18;
    uint256 internal constant EXPECTED_YIELD_90D = 493_150_683_628_800_000;

    event Staked(address indexed user, uint256 krune, uint256 kdex);
    event Accrued(address indexed user, uint256 kshrd);
    event Unstaked(address indexed user, uint256 krune, uint256 kdex, uint256 kshrd);
    event YieldMintDeferred(address indexed user, uint256 kshrd);
    event YieldClaimed(address indexed user, uint256 kshrd);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        krune = new KarmaRune(ADMIN);
        kdex = new KarmaDex(KDEX_SUPPLY, KDEX_TREASURY);
        kshrd = new KarmaShard(ADMIN);
        staking = new Staking(address(krune), address(kdex), address(kshrd), OWNER);

        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));

        _fund(ALICE, 1_000e18, 10_000e18);

        harness = new StakingHarness(address(krune), address(kdex), address(kshrd), OWNER);
    }

    /// @dev Each mint gets its own reason hash: KRUNE settles an earning event
    ///      exactly once on-chain, so a shared constant would revert on the
    ///      second staker. See test_mintEarned_* in KarmaRune.t.sol.
    uint256 internal reasonNonce;

    function _reason() internal returns (bytes32) {
        return keccak256(abi.encode(REASON, ++reasonNonce));
    }

    function _fund(address who, uint256 kruneAmt, uint256 kdexAmt) internal {
        vm.prank(ADMIN);
        krune.mintEarned(who, kruneAmt, _reason());
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(who, kdexAmt));
        vm.startPrank(who);
        krune.approve(address(staking), type(uint256).max);
        kdex.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }

    function _position(address who)
        internal
        view
        returns (uint256 k, uint256 d, uint256 startedAt, uint256 lastAccrued, uint256 accrued, bool active)
    {
        return staking.positions(who);
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTION & CONSTANTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_wiring() public view {
        assertEq(address(staking.krune()), address(krune));
        assertEq(address(staking.kdex()), address(kdex));
        assertEq(address(staking.kshrd()), address(kshrd));
        assertEq(staking.owner(), OWNER);
        assertFalse(staking.paused());
    }

    function test_constructor_revertsOnZeroTokens() public {
        vm.expectRevert("STAKE: zero token");
        new Staking(address(0), address(kdex), address(kshrd), OWNER);
        vm.expectRevert("STAKE: zero token");
        new Staking(address(krune), address(0), address(kshrd), OWNER);
        vm.expectRevert("STAKE: zero token");
        new Staking(address(krune), address(kdex), address(0), OWNER);
    }

    function test_constructor_revertsOnZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Staking(address(krune), address(kdex), address(kshrd), address(0));
    }

    function test_constants() public view {
        assertEq(staking.LOCK_PERIOD(), 90 days);
        assertEq(staking.YIELD_RATE_PER_SEC(), 317_097_919);
    }

    /// @notice The per-second rate must round-trip to ~1% per year.
    function test_yieldRateIsOnePercentPerYear() public view {
        uint256 annual = staking.YIELD_RATE_PER_SEC() * 365 days; // scaled 1e18
        assertApproxEqAbs(annual, 0.01e18, 1e10, "rate must be 1%/yr within truncation error");
        assertLe(annual, 0.01e18, "truncation must never round the rate UP");
    }

    /*//////////////////////////////////////////////////////////////
                                  STAKE
    //////////////////////////////////////////////////////////////*/

    function test_stake_happyPath() public {
        uint256 t0 = block.timestamp;

        vm.expectEmit(true, false, false, true, address(staking));
        emit Staked(ALICE, STAKE_KRUNE, STAKE_KDEX);
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);

        assertEq(krune.balanceOf(address(staking)), STAKE_KRUNE);
        assertEq(kdex.balanceOf(address(staking)), STAKE_KDEX);
        assertEq(krune.balanceOf(ALICE), 1_000e18 - STAKE_KRUNE);
        assertEq(kdex.balanceOf(ALICE), 10_000e18 - STAKE_KDEX);

        (uint256 k, uint256 d, uint256 startedAt, uint256 lastAccrued, uint256 accrued, bool active) = _position(ALICE);
        assertEq(k, STAKE_KRUNE);
        assertEq(d, STAKE_KDEX);
        assertEq(startedAt, t0);
        assertEq(lastAccrued, t0);
        assertEq(accrued, 0);
        assertTrue(active);
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
    ///         holding 50 million KDEX and zero KRUNE cannot open a position.
    function test_stake_whaleWithNoKruneCannotStake() public {
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(WHALE, 50_000_000e18));
        vm.startPrank(WHALE);
        kdex.approve(address(staking), type(uint256).max);
        krune.approve(address(staking), type(uint256).max);

        assertEq(krune.balanceOf(WHALE), 0);

        vm.expectRevert("STAKE: need earned KRUNE (reputation)");
        staking.stake(0, 50_000_000e18);

        // Even trying to pass a KRUNE amount they do not own fails at transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, WHALE, 0, 1));
        staking.stake(1, 50_000_000e18);
        vm.stopPrank();

        (,,,,, bool active) = _position(WHALE);
        assertFalse(active, "whale must have no position");
        assertEq(kdex.balanceOf(address(staking)), 0, "not a single KDEX may enter without KRUNE");
    }

    /// @notice A whale that scrapes together 1 wei of KRUNE gets in, but the
    ///         geometric mean crushes the yield: 100M KDEX + 1 wei KRUNE earns
    ///         less than a balanced 100/400 staker by ~7 orders of magnitude.
    function test_geometricMeanSuppressesLopsidedWhale() public {
        vm.prank(ADMIN);
        krune.mintEarned(WHALE, 1, _reason());
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(WHALE, 50_000_000e18));
        vm.startPrank(WHALE);
        krune.approve(address(staking), type(uint256).max);
        kdex.approve(address(staking), type(uint256).max);
        staking.stake(1, 50_000_000e18);
        vm.stopPrank();

        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);

        vm.warp(block.timestamp + 90 days);

        uint256 whaleYield = staking.pendingKshrd(WHALE);
        uint256 aliceYield = staking.pendingKshrd(ALICE);

        assertEq(aliceYield, EXPECTED_YIELD_90D);
        // sqrt(1) * sqrt(5e25) = 1 * 7071067811 -> 7071067811 * 2465753418144000 / 1e18
        assertLt(whaleYield, aliceYield / 1_000_000, "50M KDEX must not out-earn 100 KRUNE + 400 KDEX");
        assertGt(aliceYield, 0);
    }

    function test_stake_revertsWithoutApproval() public {
        vm.prank(ADMIN);
        krune.mintEarned(STRANGER, 10e18, _reason());
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(STRANGER, 10e18));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(staking), 0, 1e18)
        );
        vm.prank(STRANGER);
        staking.stake(1e18, 1e18);
    }

    function test_stake_topUpAccruesFirstAndAddsPrincipal() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        uint256 t0 = block.timestamp;

        vm.warp(t0 + 30 days);
        uint256 pendingBefore = staking.pendingKshrd(ALICE);
        assertGt(pendingBefore, 0);

        vm.expectEmit(true, false, false, true, address(staking));
        emit Accrued(ALICE, pendingBefore);
        vm.expectEmit(true, false, false, true, address(staking));
        emit Staked(ALICE, STAKE_KRUNE, STAKE_KDEX);
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);

        (uint256 k, uint256 d, uint256 startedAt, uint256 lastAccrued, uint256 accrued,) = _position(ALICE);
        assertEq(k, 2 * STAKE_KRUNE);
        assertEq(d, 2 * STAKE_KDEX);
        assertEq(accrued, pendingBefore, "old principal must be settled before the new one applies");
        assertEq(lastAccrued, t0 + 30 days);
        assertEq(startedAt, t0 + 30 days, "the top-up restarts the lock on the whole position");
    }

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

        (,, uint256 startedAt,,,) = _position(ALICE);
        assertEq(startedAt, topUpAt, "startedAt IS refreshed on top-up");

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
        assertEq(krune.balanceOf(ALICE), 1_000e18, "principal comes back once the new term is served");
    }

    function test_stake_multipleUsersAreIndependent() public {
        _fund(WHALE, 500e18, 500e18);
        vm.prank(ALICE);
        staking.stake(100e18, 400e18);
        vm.prank(WHALE);
        staking.stake(500e18, 500e18);

        (uint256 ak, uint256 ad,,,,) = _position(ALICE);
        (uint256 wk, uint256 wd,,,,) = _position(WHALE);
        assertEq(ak, 100e18);
        assertEq(ad, 400e18);
        assertEq(wk, 500e18);
        assertEq(wd, 500e18);
        assertEq(krune.balanceOf(address(staking)), 600e18);
        assertEq(kdex.balanceOf(address(staking)), 900e18);
    }

    /*//////////////////////////////////////////////////////////////
                                 UNSTAKE
    //////////////////////////////////////////////////////////////*/

    function test_unstake_revertsBeforeLockElapses() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        uint256 t0 = block.timestamp;

        vm.warp(t0 + 90 days - 1);
        vm.expectRevert("STAKE: locked");
        vm.prank(ALICE);
        staking.unstake();
    }

    function test_unstake_succeedsAtExactly90Days() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        uint256 t0 = block.timestamp;

        vm.warp(t0 + 90 days);
        vm.prank(ALICE);
        uint256 minted = staking.unstake();

        assertEq(minted, EXPECTED_YIELD_90D);
        assertEq(kshrd.balanceOf(ALICE), EXPECTED_YIELD_90D);
        assertEq(krune.balanceOf(ALICE), 1_000e18);
        assertEq(kdex.balanceOf(ALICE), 10_000e18);
    }

    function test_unstake_emitsAccruedThenUnstakedAndClearsPosition() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 90 days);

        vm.expectEmit(true, false, false, true, address(staking));
        emit Accrued(ALICE, EXPECTED_YIELD_90D);
        vm.expectEmit(true, false, false, true, address(staking));
        emit Unstaked(ALICE, STAKE_KRUNE, STAKE_KDEX, EXPECTED_YIELD_90D);
        vm.prank(ALICE);
        staking.unstake();

        (uint256 k, uint256 d, uint256 startedAt, uint256 lastAccrued, uint256 accrued, bool active) = _position(ALICE);
        assertEq(k, 0);
        assertEq(d, 0);
        assertEq(startedAt, 0);
        assertEq(lastAccrued, 0);
        assertEq(accrued, 0);
        assertFalse(active);
        assertEq(krune.balanceOf(address(staking)), 0);
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

    function test_unstake_yieldKeepsAccruingPastTheLock() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 180 days);

        vm.prank(ALICE);
        uint256 minted = staking.unstake();
        assertEq(minted, 2 * EXPECTED_YIELD_90D, "180 days is exactly twice 90 days of linear accrual");
    }

    function test_unstake_dustPositionMintsNothing() public {
        vm.prank(ALICE);
        staking.stake(1, 1); // geometric mean 1 -> yield rounds to 0 over 90 days
        vm.warp(block.timestamp + 90 days);

        vm.prank(ALICE);
        uint256 minted = staking.unstake();
        assertEq(minted, 0);
        assertEq(kshrd.totalSupply(), 0, "no KSHRD is minted for zero yield");
    }

    /**
     * @notice The deployment-ordering hazard: a Staking deployed before (or
     *         instead of) its MINTER_ROLE grant cannot mint yield. That must
     *         cost the staker a delay, never their principal.
     */
    function test_unstake_returnsPrincipalWhenStakingLacksMinterRole() public {
        Staking orphan = new Staking(address(krune), address(kdex), address(kshrd), OWNER);
        vm.startPrank(ALICE);
        krune.approve(address(orphan), type(uint256).max);
        kdex.approve(address(orphan), type(uint256).max);
        orphan.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.stopPrank();

        // Control: the mint really would revert right now.
        assertFalse(kshrd.hasRole(MINTER_ROLE, address(orphan)));

        vm.warp(block.timestamp + 90 days);

        vm.expectEmit(true, false, false, true, address(orphan));
        emit YieldMintDeferred(ALICE, EXPECTED_YIELD_90D);
        vm.prank(ALICE);
        uint256 settled = orphan.unstake();

        assertEq(settled, EXPECTED_YIELD_90D, "unstake still reports the yield it settled");
        assertEq(krune.balanceOf(ALICE), 1_000e18, "KRUNE principal is out in full");
        assertEq(kdex.balanceOf(ALICE), 10_000e18, "KDEX principal is out in full");
        assertEq(krune.balanceOf(address(orphan)), 0, "nothing is left behind");
        assertEq(kdex.balanceOf(address(orphan)), 0);

        // The yield is owed, not lost - and not mintable yet.
        assertEq(kshrd.balanceOf(ALICE), 0);
        assertEq(orphan.unclaimedYield(ALICE), EXPECTED_YIELD_90D);
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
        emit YieldClaimed(ALICE, EXPECTED_YIELD_90D);
        vm.prank(ALICE);
        assertEq(orphan.claimYield(), EXPECTED_YIELD_90D);

        assertEq(kshrd.balanceOf(ALICE), EXPECTED_YIELD_90D);
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
        vm.warp(block.timestamp + 90 days);

        vm.prank(ADMIN);
        kshrd.revokeRole(MINTER_ROLE, address(staking));

        vm.prank(ALICE);
        uint256 settled = staking.unstake();

        assertEq(settled, EXPECTED_YIELD_90D);
        assertEq(krune.balanceOf(ALICE), 1_000e18, "principal does not depend on the yield path");
        assertEq(kdex.balanceOf(ALICE), 10_000e18);
        assertEq(staking.unclaimedYield(ALICE), EXPECTED_YIELD_90D, "the claim survives the revoke");
        assertEq(kshrd.totalSupply(), 0);

        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));
        vm.prank(ALICE);
        staking.claimYield();
        assertEq(kshrd.balanceOf(ALICE), EXPECTED_YIELD_90D);
    }

    /// @notice A pause on top of a broken minter still cannot hold the principal.
    function test_unstake_returnsPrincipalWhenPausedAndMintingIsBroken() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 90 days);

        vm.prank(ADMIN);
        kshrd.revokeRole(MINTER_ROLE, address(staking));
        vm.prank(OWNER);
        staking.pause();

        vm.prank(ALICE);
        staking.unstake();

        assertEq(krune.balanceOf(ALICE), 1_000e18);
        assertEq(kdex.balanceOf(ALICE), 10_000e18);
        assertEq(staking.unclaimedYield(ALICE), EXPECTED_YIELD_90D);
    }

    /// @notice Deferred yield accumulates across cycles rather than overwriting.
    function test_claimYield_accumulatesAcrossDeferredUnstakes() public {
        vm.prank(ADMIN);
        kshrd.revokeRole(MINTER_ROLE, address(staking));

        vm.startPrank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 90 days);
        staking.unstake();
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 90 days);
        staking.unstake();
        vm.stopPrank();

        assertEq(staking.unclaimedYield(ALICE), 2 * EXPECTED_YIELD_90D);

        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));
        vm.prank(ALICE);
        assertEq(staking.claimYield(), 2 * EXPECTED_YIELD_90D);
        assertEq(kshrd.balanceOf(ALICE), 2 * EXPECTED_YIELD_90D);
    }

    /// @notice On the happy path nothing is deferred - the mint is direct and
    ///         `unclaimedYield` stays empty, so `claimYield` has nothing to pay.
    function test_claimYield_isEmptyWhenMintingWorks() public {
        vm.prank(ALICE);
        staking.stake(STAKE_KRUNE, STAKE_KDEX);
        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();

        assertEq(kshrd.balanceOf(ALICE), EXPECTED_YIELD_90D);
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

        assertEq(kshrd.totalSupply(), EXPECTED_YIELD_90D, "the debt minted exactly once");
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
        vm.warp(block.timestamp + 90 days);

        vm.prank(OWNER);
        staking.pause();
        assertTrue(staking.paused());

        vm.prank(ALICE);
        uint256 minted = staking.unstake();

        assertEq(minted, EXPECTED_YIELD_90D, "yield is still paid while paused");
        assertEq(krune.balanceOf(ALICE), 1_000e18, "KRUNE principal returned while paused");
        assertEq(kdex.balanceOf(ALICE), 10_000e18, "KDEX principal returned while paused");
        assertTrue(staking.paused(), "still paused afterwards - unstake does not unpause");
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
        (,,,,, bool active) = _position(ALICE);
        assertTrue(active);
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
        (,, uint256 startedAt,,,) = _position(ALICE);
        assertEq(startedAt, t0 + 90 days, "startedAt IS refreshed by the top-up");

        vm.expectRevert("STAKE: locked");
        staking.unstake();

        // Nor at any point before the new term is served.
        vm.warp(t0 + 180 days - 1);
        vm.expectRevert("STAKE: locked");
        staking.unstake();
        vm.stopPrank();

        assertEq(krune.balanceOf(address(staking)), 500e18 + 1, "the capital is still locked up");
        assertEq(kdex.balanceOf(address(staking)), 5_000e18 + 1);

        // A full 90 days after the deposit, and only then, it comes out.
        vm.warp(t0 + 180 days);
        vm.prank(ALICE);
        staking.unstake();
        assertEq(krune.balanceOf(ALICE), 1_000e18);
        assertEq(kdex.balanceOf(ALICE), 10_000e18);
    }

    /**
     * @notice The intended security property, stated directly: every deposit is
     *         locked for 90 days, no matter what came before it.
     */
    function test_BUG_everyDepositMustBeLockedForNinetyDays() public {
        vm.prank(ALICE);
        staking.stake(1, 1);
        uint256 t0 = block.timestamp;
        vm.warp(t0 + 90 days);

        vm.startPrank(ALICE);
        staking.stake(500e18, 5_000e18); // fresh capital, one second old
        vm.expectRevert("STAKE: locked");
        staking.unstake();
        vm.stopPrank();
    }

    /// @notice The property above, generalised: no deposit is ever withdrawable
    ///         sooner than 90 days after it was made, whatever the history.
    function testFuzz_noDepositEscapesTheLock(uint32 seasoning, uint32 wait) public {
        seasoning = uint32(bound(seasoning, 0, 365 days));
        wait = uint32(bound(wait, 0, 90 days - 1));

        vm.prank(ALICE);
        staking.stake(1, 1);
        vm.warp(block.timestamp + seasoning);

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
                            YIELD ACCRUAL — FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_yieldIsMonotonicInElapsed(uint256 geometric, uint256 e1, uint256 e2) public view {
        geometric = bound(geometric, 0, 1e40);
        e1 = bound(e1, 0, 3650 days);
        e2 = bound(e2, e1, 3650 days);
        assertLe(harness.yieldFor(geometric, e1), harness.yieldFor(geometric, e2));
    }

    function testFuzz_yieldIsMonotonicInPrincipal(uint256 g1, uint256 g2, uint256 elapsed) public view {
        g1 = bound(g1, 0, 1e40);
        g2 = bound(g2, g1, 1e40);
        elapsed = bound(elapsed, 0, 3650 days);
        assertLe(harness.yieldFor(g1, elapsed), harness.yieldFor(g2, elapsed));
    }

    function testFuzz_yieldIsAboutOnePercentPerYear(uint256 geometric) public view {
        geometric = bound(geometric, 1e18, 1e30);
        uint256 y = harness.yieldFor(geometric, 365 days);
        assertApproxEqRel(y, geometric / 100, 1e12, "1%/yr within 1e-6 relative error");
        assertLe(y, geometric / 100 + 1, "truncation must never over-pay");
    }

    function testFuzz_pendingKshrdIsMonotonicOverTime(uint256 kruneAmt, uint256 kdexAmt, uint32 dt1, uint32 dt2)
        public
    {
        kruneAmt = bound(kruneAmt, 1, 1_000e18);
        kdexAmt = bound(kdexAmt, 1, 10_000e18);

        vm.prank(ALICE);
        staking.stake(kruneAmt, kdexAmt);

        uint256 p0 = staking.pendingKshrd(ALICE);
        vm.warp(block.timestamp + dt1);
        uint256 p1 = staking.pendingKshrd(ALICE);
        vm.warp(block.timestamp + dt2);
        uint256 p2 = staking.pendingKshrd(ALICE);

        assertEq(p0, 0);
        assertLe(p1, p2, "pending yield can never go down");
    }

    /// @notice Accrual is linear, so splitting a hold period into two segments
    ///         must never CREATE yield, and must lose at most 1 wei per
    ///         truncation. This is what makes the top-up path safe.
    function testFuzz_accrualIsPathIndependent(uint256 geometric, uint256 e1, uint256 e2) public view {
        geometric = bound(geometric, 0, 1e40);
        e1 = bound(e1, 0, 3650 days);
        e2 = bound(e2, 0, 3650 days);

        uint256 split = harness.yieldFor(geometric, e1) + harness.yieldFor(geometric, e2);
        uint256 whole = harness.yieldFor(geometric, e1 + e2);

        assertLe(split, whole, "splitting an accrual period must never mint extra yield");
        assertLe(whole - split, 2, "and must cost at most 1 wei per truncated segment");
    }

    /*//////////////////////////////////////////////////////////////
                             SOLVENCY (UNIT)
    //////////////////////////////////////////////////////////////*/

    function testFuzz_contractHoldsAtLeastEveryPrincipal(uint256 aK, uint256 aD, uint256 bK, uint256 bD) public {
        aK = bound(aK, 1, 1_000e18);
        aD = bound(aD, 1, 10_000e18);
        bK = bound(bK, 1, 1_000e18);
        bD = bound(bD, 1, 10_000e18);
        _fund(WHALE, 1_000e18, 10_000e18);

        vm.prank(ALICE);
        staking.stake(aK, aD);
        vm.prank(WHALE);
        staking.stake(bK, bD);

        (uint256 ak, uint256 ad,,,,) = _position(ALICE);
        (uint256 wk, uint256 wd,,,,) = _position(WHALE);
        assertGe(krune.balanceOf(address(staking)), ak + wk);
        assertGe(kdex.balanceOf(address(staking)), ad + wd);

        vm.warp(block.timestamp + 90 days);
        vm.prank(ALICE);
        staking.unstake();
        (uint256 wk2, uint256 wd2,,,,) = _position(WHALE);
        assertGe(krune.balanceOf(address(staking)), wk2, "Alice's exit must not eat Whale's principal");
        assertGe(kdex.balanceOf(address(staking)), wd2);
    }

    /*//////////////////////////////////////////////////////////////
                       YIELD FORMULA OVERFLOW FRONTIER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Documents the exact point where _yieldFor stops being total.
     *         mulDiv(g, rate*elapsed, 1e18) overflows once rate*elapsed > 1e18,
     *         i.e. elapsed > floor(1e18 / 317_097_919) = 3_153_600_008 s
     *         (~99.94 years), AND the geometric mean sits at the uint256 ceiling.
     *         Both conditions together are unreachable with real balances, but
     *         the frontier is pinned here so a future rate change cannot move it
     *         silently.
     */
    function test_yieldForOverflowFrontier() public {
        uint256 maxGeometric = (2 ** 128 - 1) * (2 ** 128 - 1);

        uint256 y = harness.yieldFor(maxGeometric, 3_153_600_008);
        assertGt(y, 0, "still total one second before the frontier");

        vm.expectRevert(stdError.arithmeticError);
        harness.yieldFor(maxGeometric, 3_153_600_009);
    }

    /// @notice With any plausible balance the formula is total for centuries.
    function testFuzz_yieldForIsTotalOnRealisticInputs(uint256 geometric, uint256 elapsed) public view {
        geometric = bound(geometric, 0, 1e50); // 1e32 tokens at 18 decimals
        elapsed = bound(elapsed, 0, 100 * 365 days);
        harness.yieldFor(geometric, elapsed);
    }
}
