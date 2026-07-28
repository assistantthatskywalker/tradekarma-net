// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {KarmaRune} from "../../contracts/KarmaRune.sol";
import {KarmaDex} from "../../contracts/KarmaDex.sol";
import {KarmaShard} from "../../contracts/KarmaShard.sol";
import {Staking} from "../../contracts/Staking.sol";
import {StakingHandler} from "./StakingHandler.sol";

contract StakingInvariantTest is Test {
    KarmaRune internal krune;
    KarmaDex internal kdex;
    KarmaShard internal kshrd;
    Staking internal staking;
    StakingHandler internal handler;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant OWNER = address(0xB0B);
    address internal constant DISTRIBUTOR = address(0x7EA5);

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 internal constant ADMIN_ROLE = bytes32(0);

    uint256 internal constant KDEX_SUPPLY = 100_000_000e18;
    uint256 internal constant ACTOR_KRUNE = 1_000e18;
    uint256 internal constant ACTOR_KDEX = 5_000e18;

    address[] internal actors;

    function setUp() public {
        krune = new KarmaRune(ADMIN);
        kdex = new KarmaDex(KDEX_SUPPLY, DISTRIBUTOR);
        kshrd = new KarmaShard(ADMIN);
        staking = new Staking(address(krune), address(kdex), address(kshrd), OWNER);

        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, address(staking));

        address[4] memory seedActors = [address(0xAC71), address(0xAC72), address(0xAC73), address(0xAC74)];
        for (uint256 i = 0; i < seedActors.length; i++) {
            address a = seedActors[i];
            actors.push(a);
            vm.prank(ADMIN);
            krune.mintEarned(a, ACTOR_KRUNE, bytes32(i));
            vm.prank(DISTRIBUTOR);
            assertTrue(kdex.transfer(a, ACTOR_KDEX));
            vm.startPrank(a);
            krune.approve(address(staking), type(uint256).max);
            kdex.approve(address(staking), type(uint256).max);
            vm.stopPrank();
        }

        handler = new StakingHandler(staking, OWNER, actors);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = StakingHandler.stake.selector;
        selectors[1] = StakingHandler.unstake.selector;
        selectors[2] = StakingHandler.warp.selector;
        selectors[3] = StakingHandler.togglePause.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                                SOLVENCY
    //////////////////////////////////////////////////////////////*/

    /// @notice The contract must always hold at least the sum of every active
    ///         position's principal. If this ever breaks, someone's stake is
    ///         unredeemable.
    function invariant_stakingHoldsEveryPrincipal() public view {
        uint256 sumKrune;
        uint256 sumKdex;
        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 k, uint256 d,,,, bool active) = staking.positions(actors[i]);
            if (active) {
                sumKrune += k;
                sumKdex += d;
            }
        }
        assertGe(krune.balanceOf(address(staking)), sumKrune, "KRUNE solvency broken");
        assertGe(kdex.balanceOf(address(staking)), sumKdex, "KDEX solvency broken");
    }

    /// @notice The independently tracked ghost total must agree with the
    ///         on-chain balances exactly - no leakage in either direction.
    function invariant_ghostPrincipalMatchesBalances() public view {
        assertEq(krune.balanceOf(address(staking)), handler.ghostPrincipalKrune());
        assertEq(kdex.balanceOf(address(staking)), handler.ghostPrincipalKdex());
    }

    /*//////////////////////////////////////////////////////////////
                            YIELD CONSERVATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Every KSHRD in existence was minted by Staking as accrued yield,
    ///         and nothing else has ever minted one.
    function invariant_kshrdSupplyEqualsYieldMinted() public view {
        assertEq(kshrd.totalSupply(), handler.ghostKshrdMinted(), "KSHRD supply must equal total accrued yield");
    }

    function invariant_kshrdSupplyEqualsHolderBalances() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += kshrd.balanceOf(actors[i]);
        }
        assertEq(kshrd.totalSupply(), sum, "KSHRD may only exist in staker wallets");
        assertEq(kshrd.balanceOf(address(staking)), 0, "Staking must never hold KSHRD");
    }

    /*//////////////////////////////////////////////////////////////
                          PRINCIPAL CONSERVATION
    //////////////////////////////////////////////////////////////*/

    /// @notice No staker can ever end up with more principal than they started
    ///         with, and none can go missing.
    function invariant_principalIsConserved() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 k, uint256 d,,,, bool active) = staking.positions(actors[i]);
            uint256 stakedK = active ? k : 0;
            uint256 stakedD = active ? d : 0;
            assertEq(krune.balanceOf(actors[i]) + stakedK, ACTOR_KRUNE, "KRUNE created or destroyed");
            assertEq(kdex.balanceOf(actors[i]) + stakedD, ACTOR_KDEX, "KDEX created or destroyed");
        }
    }

    /// @notice KRUNE supply only ever moves through mintEarned; the staking loop
    ///         must not change it.
    function invariant_tokenSuppliesAreStable() public view {
        assertEq(krune.totalSupply(), ACTOR_KRUNE * actors.length);
        assertEq(kdex.totalSupply(), KDEX_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE SAFETY
    //////////////////////////////////////////////////////////////*/

    /// @notice A matured position must be closable regardless of pause state.
    ///         Proven live: for every actor whose lock has elapsed, unstake()
    ///         succeeds right now.
    function invariant_maturedPositionsAreAlwaysWithdrawable() public {
        for (uint256 i = 0; i < actors.length; i++) {
            (,, uint256 startedAt,,, bool active) = staking.positions(actors[i]);
            if (!active) continue;
            // forge-lint: disable-next-line(block-timestamp)
            if (block.timestamp < startedAt + staking.LOCK_PERIOD()) continue;

            uint256 snap = vm.snapshotState();
            vm.prank(actors[i]);
            staking.unstake();
            vm.revertToState(snap);
        }
    }
}
