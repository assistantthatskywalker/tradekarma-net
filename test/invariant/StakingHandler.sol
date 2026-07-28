// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {KarmaShard} from "../../contracts/KarmaShard.sol";
import {Staking} from "../../contracts/Staking.sol";

/// @notice Bounded random driver for the Staking invariant run.
contract StakingHandler is CommonBase, StdCheats, StdUtils {
    Staking public immutable staking;
    IERC20 public immutable krune;
    IERC20 public immutable kdex;
    KarmaShard public immutable kshrd;
    address public immutable stakingOwner;

    address[] public actors;

    /// @notice Sum of principals believed to be inside the contract.
    uint256 public ghostPrincipalKrune;
    uint256 public ghostPrincipalKdex;
    /// @notice Every wei of KSHRD ever minted through unstake().
    uint256 public ghostKshrdMinted;

    uint256 public stakeCalls;
    uint256 public unstakeCalls;
    uint256 public warpCalls;
    uint256 public pauseCalls;

    constructor(Staking staking_, address owner_, address[] memory actors_) {
        staking = staking_;
        stakingOwner = owner_;
        krune = staking_.krune();
        kdex = staking_.kdex();
        kshrd = staking_.kshrd();
        for (uint256 i = 0; i < actors_.length; i++) {
            actors.push(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function stake(uint256 actorSeed, uint256 kruneAmt, uint256 kdexAmt) external {
        if (staking.paused()) return;
        address a = _actor(actorSeed);

        uint256 kb = krune.balanceOf(a);
        uint256 db = kdex.balanceOf(a);
        if (kb == 0 || db == 0) return;

        kruneAmt = bound(kruneAmt, 1, kb);
        kdexAmt = bound(kdexAmt, 1, db);

        vm.prank(a);
        staking.stake(kruneAmt, kdexAmt);

        ghostPrincipalKrune += kruneAmt;
        ghostPrincipalKdex += kdexAmt;
        stakeCalls++;
    }

    function unstake(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        (uint256 pk, uint256 pd, uint256 startedAt,,, bool active) = staking.positions(a);
        if (!active) return;
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < startedAt + staking.LOCK_PERIOD()) return;

        uint256 expected = staking.pendingKshrd(a);
        uint256 shardsBefore = kshrd.balanceOf(a);

        vm.prank(a);
        uint256 minted = staking.unstake();

        // The view and the settlement must agree, always.
        require(minted == expected, "HANDLER: pendingKshrd disagreed with unstake");
        require(kshrd.balanceOf(a) == shardsBefore + minted, "HANDLER: minted shards not delivered");

        ghostKshrdMinted += minted;
        ghostPrincipalKrune -= pk;
        ghostPrincipalKdex -= pd;
        unstakeCalls++;
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1 hours, 45 days));
        warpCalls++;
    }

    /// @notice Pausing must never break solvency or trap principal.
    function togglePause() external {
        bool isPaused = staking.paused(); // read BEFORE the prank, it would consume it
        vm.prank(stakingOwner);
        if (isPaused) {
            staking.unpause();
        } else {
            staking.pause();
        }
        pauseCalls++;
    }
}
