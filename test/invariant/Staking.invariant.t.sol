// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {KarmaRune} from "../../contracts/KarmaRune.sol";
import {KarmaDex} from "../../contracts/KarmaDex.sol";
import {KarmaShard} from "../../contracts/KarmaShard.sol";
import {Staking} from "../../contracts/Staking.sol";
import {Treasury} from "../../contracts/Treasury.sol";
import {StakingHandler} from "./StakingHandler.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract StakingInvariantTest is Test {
    KarmaRune internal krune;
    KarmaDex internal kdex;
    KarmaShard internal kshrd;
    Treasury internal treasury;
    Staking internal staking;
    StakingHandler internal handler;
    MockERC20 internal usdc;

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

        address[4] memory seedActors = [address(0xAC71), address(0xAC72), address(0xAC73), address(0xAC74)];
        for (uint256 i = 0; i < seedActors.length; i++) {
            address a = seedActors[i];
            actors.push(a);
            vm.prank(ADMIN);
            krune.mintEarned(a, ACTOR_KRUNE, bytes32(i));
            vm.prank(DISTRIBUTOR);
            assertTrue(kdex.transfer(a, ACTOR_KDEX));
            vm.prank(a);
            kdex.approve(address(staking), type(uint256).max);
        }

        handler = new StakingHandler(staking, OWNER, actors);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = StakingHandler.stake.selector;
        selectors[1] = StakingHandler.unstake.selector;
        selectors[2] = StakingHandler.depositFees.selector;
        selectors[3] = StakingHandler.redeem.selector;
        selectors[4] = StakingHandler.warp.selector;
        selectors[5] = StakingHandler.togglePause.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
        THE SOLVENCY INVARIANT — WHY THE REDESIGN EXISTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice **KSHRD minted can never exceed USDC deposited as fees.**
     *
     *         Counted as everything the protocol has ever promised — shards
     *         already settled by `unstake()` (minted or deferred) plus the
     *         reward every open position could settle right now — against every
     *         dollar that has ever been paid into the pool. v1 failed this by
     *         three orders of magnitude: 9,999 dollars of claims against 10
     *         dollars of reserves, with no revert and no event.
     */
    function invariant_mintedKshrdNeverExceedsDepositedFees() public view {
        uint256 promised = handler.ghostKshrdClaimed();
        for (uint256 i = 0; i < actors.length; i++) {
            promised += staking.pendingKshrd(actors[i]);
        }
        assertLe(
            promised,
            handler.ghostUsdcDeposited() * staking.usdcScale(),
            "the protocol promised more KSHRD than the fees that funded it"
        );
    }

    /// @notice The same statement from the Treasury's side: it always holds
    ///         every dollar it owes, so a redemption can never be refused for
    ///         want of USDC.
    function invariant_allReservedClaimsAreFunded() public view {
        assertTrue(staking.reservesCovered());
        uint256 knownUnminted;
        for (uint256 i = 0; i < actors.length; i++) {
            knownUnminted += (staking.pendingKshrd(actors[i]) + staking.unclaimedYield(actors[i])) / staking.usdcScale();
        }
        assertGe(staking.unmintedReserveUsdc(), knownUnminted);
    }

    function invariant_treasuryCoversItsOutstandingLiability() public view {
        assertGe(
            usdc.balanceOf(address(treasury)),
            treasury.totalOutstandingLiability(),
            "outstanding claims exceed the USDC backing them"
        );
        if (treasury.totalOutstandingLiability() > 0) {
            assertGe(treasury.collateralRatio(), 1e18, "collateral ratio fell below 1");
        }
    }

    /// @notice Every fee dollar is in exactly one of two states: allocated to
    ///         stakers, or explicitly carried as unallocated. None is lost, and
    ///         none is counted twice.
    function invariant_feesAreEitherAllocatedOrCarried() public view {
        assertLe(staking.unallocatedFees(), handler.ghostUsdcDeposited(), "carried more than was ever deposited");
        assertEq(
            usdc.balanceOf(address(treasury)) + handler.ghostKshrdRedeemed() / treasury.usdcScale(),
            handler.ghostUsdcDeposited(),
            "USDC in the Treasury plus USDC paid out must equal USDC deposited"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            WEIGHT ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice `totalWeight` is maintained incrementally and never iterated, so
    ///         the only thing keeping it honest is that every mutation adjusts it
    ///         by exactly the position's cached weight.
    function invariant_totalWeightEqualsTheSumOfActivePositions() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            (,, uint256 w,,,, bool active) = staking.positions(actors[i]);
            if (active) sum += w;
        }
        assertEq(staking.totalWeight(), sum, "totalWeight drifted from the positions it summarises");
    }

    /*//////////////////////////////////////////////////////////////
                          SOULBOUND / REFERENCE
    //////////////////////////////////////////////////////////////*/

    /// @notice No position may reference more KRUNE than its owner holds, and no
    ///         KRUNE may ever sit in the Staking contract — it cannot get there.
    function invariant_referencedKruneIsAlwaysBacked() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            (uint256 referenced,,,,,,) = staking.positions(actors[i]);
            assertLe(referenced, krune.balanceOf(actors[i]), "a position outran its owner's reputation");
            assertEq(krune.balanceOf(actors[i]), ACTOR_KRUNE, "soulbound KRUNE moved");
        }
        assertEq(krune.balanceOf(address(staking)), 0, "Staking must never custody KRUNE");
        assertEq(krune.totalSupply(), ACTOR_KRUNE * actors.length);
    }

    /*//////////////////////////////////////////////////////////////
                        PRINCIPAL CONSERVATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The contract must always hold at least the sum of every active
    ///         position's escrowed KDEX. If this ever breaks, someone's stake is
    ///         unredeemable.
    function invariant_stakingHoldsEveryEscrowedPrincipal() public view {
        uint256 sumKdex;
        for (uint256 i = 0; i < actors.length; i++) {
            (, uint256 d,,,,, bool active) = staking.positions(actors[i]);
            if (active) sumKdex += d;
        }
        assertGe(kdex.balanceOf(address(staking)), sumKdex, "KDEX solvency broken");
    }

    /// @notice The independently tracked ghost total must agree with the
    ///         on-chain balance exactly - no leakage in either direction.
    function invariant_ghostPrincipalMatchesBalances() public view {
        assertEq(kdex.balanceOf(address(staking)), handler.ghostPrincipalKdex());
    }

    /// @notice No staker can ever end up with more KDEX than they started with,
    ///         and none can go missing.
    function invariant_principalIsConserved() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            (, uint256 d,,,,, bool active) = staking.positions(actors[i]);
            uint256 stakedD = active ? d : 0;
            assertEq(kdex.balanceOf(actors[i]) + stakedD, ACTOR_KDEX, "KDEX created or destroyed");
        }
        assertEq(kdex.totalSupply(), KDEX_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                            YIELD CONSERVATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Every KSHRD in existence was settled by Staking against real
    ///         fees, and every one that has left existence was redeemed for
    ///         USDC. Nothing else has ever minted or burned one.
    function invariant_kshrdSupplyIsFullyExplained() public view {
        assertEq(
            kshrd.totalSupply(),
            handler.ghostKshrdClaimed() - handler.ghostKshrdRedeemed(),
            "KSHRD supply must equal claims settled minus claims redeemed"
        );
    }

    function invariant_kshrdOnlyExistsInStakerWallets() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += kshrd.balanceOf(actors[i]);
        }
        assertEq(kshrd.totalSupply(), sum, "KSHRD may only exist in staker wallets");
        assertEq(kshrd.balanceOf(address(staking)), 0, "Staking must never hold KSHRD");
        assertEq(kshrd.balanceOf(address(treasury)), 0, "redemption burns, it does not accumulate");
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSE SAFETY
    //////////////////////////////////////////////////////////////*/

    /// @notice A matured position must be closable regardless of pause state.
    ///         Proven live: for every actor whose lock has elapsed, unstake()
    ///         succeeds right now.
    function invariant_maturedPositionsAreAlwaysWithdrawable() public {
        for (uint256 i = 0; i < actors.length; i++) {
            (,,, uint256 startedAt,,, bool active) = staking.positions(actors[i]);
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
