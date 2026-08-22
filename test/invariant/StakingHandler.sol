// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {KarmaShard} from "../../contracts/KarmaShard.sol";
import {Staking} from "../../contracts/Staking.sol";
import {Treasury} from "../../contracts/Treasury.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Bounded random driver for the Staking invariant run.
contract StakingHandler is CommonBase, StdCheats, StdUtils {
    Staking public immutable staking;
    Treasury public immutable treasury;
    IERC20 public immutable krune;
    IERC20 public immutable kdex;
    KarmaShard public immutable kshrd;
    MockERC20 public immutable usdc;
    address public immutable stakingOwner;

    address[] public actors;

    /// @notice Sum of KDEX principal believed to be inside the contract.
    uint256 public ghostPrincipalKdex;
    /// @notice Every wei of USDC ever paid into the fee pool.
    uint256 public ghostUsdcDeposited;
    /// @notice Every wei of KSHRD ever settled by unstake(), whether it was
    ///         minted straight away or deferred into `unclaimedYield`.
    uint256 public ghostKshrdClaimed;
    /// @notice Every wei of KSHRD ever destroyed by a redemption.
    uint256 public ghostKshrdRedeemed;

    uint256 public stakeCalls;
    uint256 public unstakeCalls;
    uint256 public depositCalls;
    uint256 public redeemCalls;
    uint256 public warpCalls;
    uint256 public pauseCalls;

    constructor(Staking staking_, address owner_, address[] memory actors_) {
        staking = staking_;
        stakingOwner = owner_;
        treasury = staking_.treasury();
        krune = staking_.krune();
        kdex = staking_.kdex();
        kshrd = staking_.kshrd();
        usdc = MockERC20(address(staking_.usdc()));
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

        // KRUNE is referenced, not escrowed, so what is available to stake is
        // the wallet balance MINUS whatever this position already claims.
        (uint256 referenced,,,,,,) = staking.positions(a);
        uint256 free = krune.balanceOf(a) - referenced;
        uint256 db = kdex.balanceOf(a);
        if (free == 0 || db == 0) return;

        kruneAmt = bound(kruneAmt, 1, free);
        kdexAmt = bound(kdexAmt, 1, db);

        vm.prank(a);
        staking.stake(kruneAmt, kdexAmt);

        ghostPrincipalKdex += kdexAmt;
        stakeCalls++;
    }

    function unstake(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        (, uint256 pd,, uint256 startedAt,,, bool active) = staking.positions(a);
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

        ghostKshrdClaimed += minted;
        ghostPrincipalKdex -= pd;
        unstakeCalls++;
    }

    /// @notice Real revenue arriving. This is the only thing that can increase
    ///         what anyone is owed, and it always moves USDC to do it.
    function depositFees(uint256 amount) external {
        amount = bound(amount, 0, 100_000e6);
        address payer = address(this);
        usdc.mint(payer, amount);
        usdc.approve(address(staking), amount);
        staking.depositFees(amount);

        ghostUsdcDeposited += amount;
        depositCalls++;
    }

    /// @notice Redeeming must not be able to push the treasury under water: it
    ///         removes the same dollar from both sides of the ratio.
    function redeem(uint256 actorSeed, uint256 amount) external {
        address a = _actor(actorSeed);
        uint256 held = kshrd.balanceOf(a);
        if (held < treasury.usdcScale()) return;
        amount = bound(amount, treasury.usdcScale(), held);

        uint256 supplyBefore = kshrd.totalSupply();
        vm.startPrank(a);
        kshrd.approve(address(treasury), amount);
        treasury.redeem(amount, true);
        vm.stopPrank();

        ghostKshrdRedeemed += supplyBefore - kshrd.totalSupply();
        redeemCalls++;
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
