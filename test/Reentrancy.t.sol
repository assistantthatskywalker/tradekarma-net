// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {KarmaDex} from "../contracts/KarmaDex.sol";
import {KarmaShard} from "../contracts/KarmaShard.sol";
import {Staking} from "../contracts/Staking.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ReentrantToken} from "./mocks/ReentrantToken.sol";
import {ReentrancyProbe} from "./mocks/ReentrancyProbe.sol";
import {Attacker} from "./mocks/Attacker.sol";

/**
 * @notice Proves `nonReentrant` actually blocks a hostile ERC-20.
 *
 * Every blocking test is paired with a POSITIVE CONTROL that arms the same
 * token against a harmless probe and asserts the callback fired mid-transfer.
 * Without that pairing, "the attack reverted" would be indistinguishable from
 * "the callback never ran".
 *
 * @dev The hostile token is KDEX or USDC, never KRUNE. Staking no longer calls
 *      `transferFrom` on KRUNE at all — it only reads `balanceOf`, which cannot
 *      hand control to anyone — so the token that used to be the re-entry point
 *      has stopped being one. KRUNE is modelled here as a plain MockERC20
 *      because Staking uses nothing but its balance.
 */
contract ReentrancyTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant OWNER = address(0xB0B);
    address internal constant DISTRIBUTOR = address(0x7EA5);

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 internal constant ADMIN_ROLE = bytes32(0);

    uint256 internal constant KDEX_SUPPLY = 100_000_000e18;

    KarmaShard internal kshrd;
    ReentrancyProbe internal probe;

    function setUp() public {
        kshrd = new KarmaShard(ADMIN);
        probe = new ReentrancyProbe();
    }

    /*//////////////////////////////////////////////////////////////
                        HARNESS SANITY (POSITIVE CONTROL)
    //////////////////////////////////////////////////////////////*/

    function test_control_maliciousTokenReallyReenters() public {
        ReentrantToken evil = new ReentrantToken("Evil", "EVIL", 18);
        evil.mint(address(this), 10e18);
        evil.arm(address(probe), abi.encodeCall(ReentrancyProbe.ping, ()));

        assertTrue(evil.transfer(address(0xDEAD), 1e18));

        assertEq(probe.pings(), 1, "callback must fire during the transfer");
        assertEq(evil.callbacksFired(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                                 STAKING
    //////////////////////////////////////////////////////////////*/

    function _deployStaking()
        internal
        returns (Staking s, MockERC20 krune, ReentrantToken evilKdex, MockERC20 usdc, Attacker atk)
    {
        krune = new MockERC20("KarmaRune", "KRUNE", 18);
        evilKdex = new ReentrantToken("Evil KDEX", "eKDEX", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        Treasury t = new Treasury(address(usdc), address(evilKdex), address(kshrd), OWNER);
        s = new Staking(address(krune), address(evilKdex), address(kshrd), address(t), OWNER);

        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(s));

        atk = new Attacker(address(s));
        krune.mint(address(atk), 1_000e18);
        evilKdex.mint(address(atk), 1_000e18);
        usdc.mint(address(atk), 1_000e6);

        atk.approve(address(evilKdex), address(s), type(uint256).max);
        atk.approve(address(usdc), address(s), type(uint256).max);
    }

    function test_control_callbackFiresInsideStake() public {
        (Staking s,, ReentrantToken evilKdex,, Attacker atk) = _deployStaking();

        evilKdex.arm(address(probe), abi.encodeCall(ReentrancyProbe.ping, ()));
        atk.exec(abi.encodeCall(Staking.stake, (10e18, 10e18)));

        assertEq(probe.pings(), 1, "re-entry point inside stake() is reachable");
        (,,,,,, bool active) = s.positions(address(atk));
        assertTrue(active);
    }

    function test_stake_reentryIsBlocked() public {
        (Staking s,, ReentrantToken evilKdex,, Attacker atk) = _deployStaking();

        bytes memory reenter = abi.encodeCall(Attacker.exec, (abi.encodeCall(Staking.stake, (1e18, 1e18))));
        evilKdex.arm(address(atk), reenter);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        atk.exec(abi.encodeCall(Staking.stake, (10e18, 10e18)));

        (,,,,,, bool active) = s.positions(address(atk));
        assertFalse(active, "nothing was staked");
        assertEq(evilKdex.balanceOf(address(s)), 0);
        assertEq(s.totalWeight(), 0, "and no weight leaked into the pool");
    }

    function test_control_callbackFiresInsideUnstake() public {
        (,, ReentrantToken evilKdex,, Attacker atk) = _deployStaking();
        atk.exec(abi.encodeCall(Staking.stake, (10e18, 10e18)));
        vm.warp(block.timestamp + 90 days);

        evilKdex.arm(address(probe), abi.encodeCall(ReentrancyProbe.ping, ()));
        atk.exec(abi.encodeCall(Staking.unstake, ()));

        assertEq(probe.pings(), 1, "re-entry point inside unstake() is reachable");
        assertEq(evilKdex.balanceOf(address(atk)), 1_000e18);
    }

    /// @notice The double-drain: re-enter unstake() while the principal transfer
    ///         is still in flight, as the SAME staker.
    function test_unstake_reentryIsBlocked() public {
        (Staking s,, ReentrantToken evilKdex,, Attacker atk) = _deployStaking();
        atk.exec(abi.encodeCall(Staking.stake, (10e18, 10e18)));
        vm.warp(block.timestamp + 90 days);

        bytes memory reenter = abi.encodeCall(Attacker.exec, (abi.encodeCall(Staking.unstake, ())));
        evilKdex.arm(address(atk), reenter);

        // Must be the guard, NOT "STAKE: none" - the guard has to be what stops it.
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        atk.exec(abi.encodeCall(Staking.unstake, ()));

        (,,,,,, bool active) = s.positions(address(atk));
        assertTrue(active, "position survives the failed attack");
        assertEq(evilKdex.balanceOf(address(s)), 10e18, "principal still in the contract");
        assertEq(kshrd.totalSupply(), 0, "no KSHRD was minted twice");
    }

    /// @notice Re-entering stake() from inside unstake() is blocked too.
    function test_crossFunctionReentryIsBlocked() public {
        (,, ReentrantToken evilKdex,, Attacker atk) = _deployStaking();
        atk.exec(abi.encodeCall(Staking.stake, (10e18, 10e18)));
        vm.warp(block.timestamp + 90 days);

        bytes memory reenter = abi.encodeCall(Attacker.exec, (abi.encodeCall(Staking.stake, (1e18, 1e18))));
        evilKdex.arm(address(atk), reenter);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        atk.exec(abi.encodeCall(Staking.unstake, ()));
    }

    /*//////////////////////////////////////////////////////////////
        DEPOSIT FEES — THE ACCUMULATOR MUST NOT BE RE-ENTERED
    //////////////////////////////////////////////////////////////*/

    function _deployStakingWithEvilUsdc()
        internal
        returns (Staking s, ReentrantToken evilUsdc, MockERC20 kdex, Attacker atk)
    {
        MockERC20 krune = new MockERC20("KarmaRune", "KRUNE", 18);
        kdex = new MockERC20("KarmaDex", "KDEX", 18);
        evilUsdc = new ReentrantToken("Evil USDC", "eUSDC", 6);
        Treasury t = new Treasury(address(evilUsdc), address(kdex), address(kshrd), OWNER);
        s = new Staking(address(krune), address(kdex), address(kshrd), address(t), OWNER);

        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(s));

        atk = new Attacker(address(s));
        krune.mint(address(atk), 1_000e18);
        kdex.mint(address(atk), 1_000e18);
        evilUsdc.mint(address(atk), 1_000e6);
        atk.approve(address(kdex), address(s), type(uint256).max);
        atk.approve(address(evilUsdc), address(s), type(uint256).max);
    }

    function test_control_callbackFiresInsideDepositFees() public {
        (Staking s, ReentrantToken evilUsdc,, Attacker atk) = _deployStakingWithEvilUsdc();
        atk.exec(abi.encodeCall(Staking.stake, (10e18, 10e18)));

        evilUsdc.arm(address(probe), abi.encodeCall(ReentrancyProbe.ping, ()));
        atk.exec(abi.encodeCall(Staking.depositFees, (100e6)));

        assertEq(probe.pings(), 1, "re-entry point inside depositFees() is reachable");
        assertGt(s.rewardPerWeightStored(), 0, "and the deposit still landed");
    }

    /// @notice Re-entering `unstake` from inside `depositFees` would settle a
    ///         position against an accumulator that is mid-update. The guard
    ///         covers both functions, so it cannot start.
    function test_depositFees_reentryIntoUnstakeIsBlocked() public {
        (Staking s, ReentrantToken evilUsdc, MockERC20 kdex, Attacker atk) = _deployStakingWithEvilUsdc();
        atk.exec(abi.encodeCall(Staking.stake, (10e18, 10e18)));
        vm.warp(block.timestamp + 90 days);

        bytes memory reenter = abi.encodeCall(Attacker.exec, (abi.encodeCall(Staking.unstake, ())));
        evilUsdc.arm(address(atk), reenter);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        atk.exec(abi.encodeCall(Staking.depositFees, (100e6)));

        assertEq(evilUsdc.balanceOf(address(atk)), 1_000e6, "the deposit rolled back too");
        assertEq(s.rewardPerWeightStored(), 0);
        assertEq(kdex.balanceOf(address(s)), 10e18, "and the position is untouched");
    }

    /*//////////////////////////////////////////////////////////////
                                 TREASURY
    //////////////////////////////////////////////////////////////*/

    function _deployTreasuryWithEvilUsdc()
        internal
        returns (Treasury t, ReentrantToken evilUsdc, KarmaDex kdex, Attacker atk)
    {
        evilUsdc = new ReentrantToken("Evil USDC", "eUSDC", 6);
        kdex = new KarmaDex(KDEX_SUPPLY, DISTRIBUTOR);
        t = new Treasury(address(evilUsdc), address(kdex), address(kshrd), OWNER);

        vm.startPrank(ADMIN);
        kshrd.grantRole(BURNER_ROLE, address(t));
        kshrd.grantRole(MINTER_ROLE, address(this));
        vm.stopPrank();

        atk = new Attacker(address(t));
        evilUsdc.mint(address(t), 1_000_000e6);
        vm.prank(DISTRIBUTOR);
        assertTrue(kdex.transfer(address(t), 1_000_000e18));
        kshrd.mint(address(atk), 100e18);
        // Redeeming burns via the holder's allowance; arm the attacker fully so
        // the guard, not a missing approval, is what stops the re-entry.
        atk.approve(address(kshrd), address(t), type(uint256).max);
    }

    function test_control_callbackFiresInsideRedeem() public {
        (, ReentrantToken evilUsdc,, Attacker atk) = _deployTreasuryWithEvilUsdc();

        evilUsdc.arm(address(probe), abi.encodeCall(ReentrancyProbe.ping, ()));
        atk.exec(abi.encodeCall(Treasury.redeem, (10e18, true)));

        assertEq(probe.pings(), 1, "re-entry point inside redeem() is reachable");
        assertEq(evilUsdc.balanceOf(address(atk)), 10e6);
        assertEq(kshrd.balanceOf(address(atk)), 90e18);
    }

    function test_redeem_reentryIsBlocked() public {
        (Treasury t, ReentrantToken evilUsdc,, Attacker atk) = _deployTreasuryWithEvilUsdc();

        bytes memory reenter = abi.encodeCall(Attacker.exec, (abi.encodeCall(Treasury.redeem, (10e18, true))));
        evilUsdc.arm(address(atk), reenter);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        atk.exec(abi.encodeCall(Treasury.redeem, (50e18, true)));

        assertEq(kshrd.balanceOf(address(atk)), 100e18, "no shards burned");
        assertEq(evilUsdc.balanceOf(address(atk)), 0, "no USDC drained");
        assertEq(evilUsdc.balanceOf(address(t)), 1_000_000e6);
    }

    function test_redeemAsKdex_reentryIsBlocked() public {
        ReentrantToken evilKdex = new ReentrantToken("Evil KDEX", "eKDEX", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        Treasury t = new Treasury(address(usdc), address(evilKdex), address(kshrd), OWNER);

        vm.startPrank(ADMIN);
        kshrd.grantRole(BURNER_ROLE, address(t));
        kshrd.grantRole(MINTER_ROLE, address(this));
        vm.stopPrank();
        vm.prank(OWNER);
        t.setKshrdPerKdexRate(1e18);

        Attacker atk = new Attacker(address(t));
        evilKdex.mint(address(t), 1_000_000e18);
        usdc.mint(address(t), 1_000_000e6);
        kshrd.mint(address(atk), 100e18);
        atk.approve(address(kshrd), address(t), type(uint256).max);

        bytes memory reenter = abi.encodeCall(Attacker.exec, (abi.encodeCall(Treasury.redeem, (10e18, false))));
        evilKdex.arm(address(atk), reenter);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        atk.exec(abi.encodeCall(Treasury.redeem, (50e18, false)));

        assertEq(kshrd.balanceOf(address(atk)), 100e18);
        assertEq(evilKdex.balanceOf(address(atk)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        GUARD RELEASES AFTER THE CALL
    //////////////////////////////////////////////////////////////*/

    /// @notice A guard that never releases would brick the contract. Prove the
    ///         same actor can call again in a later transaction.
    function test_guardIsNotSticky() public {
        (Staking s, MockERC20 krune, ReentrantToken evilKdex,, Attacker atk) = _deployStaking();

        atk.exec(abi.encodeCall(Staking.stake, (10e18, 10e18)));
        atk.exec(abi.encodeCall(Staking.stake, (10e18, 10e18)));
        vm.warp(block.timestamp + 90 days);
        atk.exec(abi.encodeCall(Staking.unstake, ()));

        assertEq(evilKdex.balanceOf(address(atk)), 1_000e18);
        assertEq(krune.balanceOf(address(atk)), 1_000e18, "the reference never moved a rune");
        (,,,,,, bool active) = s.positions(address(atk));
        assertFalse(active);
    }
}
