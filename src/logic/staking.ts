/**
 * Staking Logic
 * Lock KRUNE + KDEX together to generate KSHRD yield.
 * Anti-whale: both KRUNE (earned) and KDEX (purchased) required.
 */

import { User } from '../models/User';
import { KarmaDexLedger, KarmaShardVault, KarmaShard } from '../models/Tokens';
import { KarmaRuneLedger } from '../models/KarmaRune';

export interface StakingContext {
  userId: string;
  user: User;
  kruneLedger: KarmaRuneLedger;
  kdexLedger: KarmaDexLedger;
  shardVault: KarmaShardVault;
}

/**
 * Anti-Whale Gate: user must have both earned reputation AND purchased investment.
 * This is the load-bearing mechanic: cannot buy your way to yield without proving participation.
 */
export function checkAntiWhaleGate(context: StakingContext): {
  canStake: boolean;
  reason?: string;
} {
  const krune = context.kruneLedger.get(context.userId);
  const kdex = context.kdexLedger.get(context.userId);

  if (krune === 0) {
    return {
      canStake: false,
      reason: 'No earned reputation (KRUNE). You must participate first.',
    };
  }

  if (kdex === 0) {
    return {
      canStake: false,
      reason: 'No investment tokens (KDEX). You must believe in the project.',
    };
  }

  return { canStake: true };
}

/**
 * Stake KRUNE + KDEX together to generate yield (KSHRD).
 * Locks both for 90 days (penalty for early exit: lose accrued yield).
 */
export function stake(
  context: StakingContext,
  kruneAmount: number,
  kdexAmount: number
): {
  success: boolean;
  stakeId?: string;
  error?: string;
  shard?: KarmaShard;
} {
  // Check gate
  const gate = checkAntiWhaleGate(context);
  if (!gate.canStake) {
    return { success: false, error: gate.reason };
  }

  // Check balances
  const userKrune = context.kruneLedger.get(context.userId);
  const userKdex = context.kdexLedger.get(context.userId);

  if (userKrune < kruneAmount) {
    return { success: false, error: 'Insufficient KRUNE balance' };
  }

  if (userKdex < kdexAmount) {
    return { success: false, error: 'Insufficient KDEX balance' };
  }

  // Lock tokens
  context.kruneLedger.subtract(context.userId, kruneAmount);
  context.kdexLedger.subtract(context.userId, kdexAmount);

  // Create stake
  const shard = context.shardVault.create(
    context.userId,
    kruneAmount,
    kdexAmount,
    90
  );

  return {
    success: true,
    stakeId: shard.id,
    shard,
  };
}

/**
 * Unstake and redeem KSHRD yield.
 * After lock period, user can redeem for USDC (treasury) or KDEX (keepback).
 * Early unstake (before lock period): lose accrued yield, recover original KRUNE + KDEX.
 */
export function unstake(
  context: StakingContext,
  stakeId: string,
  forUSDC: boolean = true
): {
  success: boolean;
  yieldAmount?: number;
  error?: string;
} {
  const stake = context.shardVault.stakes.get(stakeId);

  if (!stake || stake.userId !== context.userId) {
    return { success: false, error: 'Stake not found' };
  }

  const now = new Date();
  const isMatured = now >= stake.matureAt;

  if (!isMatured) {
    // Early unstake: lose yield, recover principal
    context.kruneLedger.add(context.userId, stake.kruneStaked);
    context.kdexLedger.add(context.userId, stake.kdexStaked);
    context.shardVault.stakes.delete(stakeId);

    return {
      success: true,
      yieldAmount: 0,
      error: 'Early unstake: yield forfeited. KRUNE + KDEX returned.',
    };
  }

  // Normal redemption (mature)
  const yield_ = context.shardVault.redeem(stakeId);

  // In Phase 2, this would transfer from treasury
  // For Phase 1 (database), just return the amount
  if (forUSDC) {
    // Would be: transfer USDC from treasury
  } else {
    // Would be: transfer KDEX from treasury with 10% keepback bonus
    const bonus = yield_ * 0.1;
    context.kdexLedger.add(context.userId, yield_ + bonus);
  }

  return {
    success: true,
    yieldAmount: yield_,
  };
}

/**
 * Accrue daily yield for all active stakes.
 * Called daily (cron job in production).
 */
export function accrueGlobalYield(context: StakingContext): number {
  let totalYield = 0;
  for (const stake of Array.from(context.shardVault.stakes.values())) {
    totalYield += context.shardVault.accrueYield(stake.id, 1);
  }
  return totalYield;
}
