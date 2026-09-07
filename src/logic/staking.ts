/** Reference simulation of the Solidity hard lock and funded fee pool; not a payment backend. */
import { User } from '../models/User';
import { KarmaDexLedger, KarmaShardVault, KarmaShard } from '../models/Tokens';
import { KarmaRuneLedger } from '../models/KarmaRune';
import { assertAmount } from '../models/Ledger';
export interface StakingContext {
  userId: string;
  user: User;
  kruneLedger: KarmaRuneLedger;
  kdexLedger: KarmaDexLedger;
  shardVault: KarmaShardVault;
}
export function checkAntiWhaleGate(ctx: StakingContext): { canStake: boolean; reason?: string } {
  const referenced = ctx.shardVault.getByUser(ctx.userId).reduce((n, p) => n + p.kruneStaked, 0);
  if (ctx.kruneLedger.get(ctx.userId) <= referenced) return { canStake: false, reason: 'No unreferenced earned reputation (KRUNE).' };
  if (ctx.kdexLedger.get(ctx.userId) <= 0) return { canStake: false, reason: 'No investment tokens (KDEX).' };
  return { canStake: true };
}
export function stake(ctx: StakingContext, kruneAmount: number, kdexAmount: number): { success: boolean; stakeId?: string; error?: string; shard?: KarmaShard } {
  try {
    assertAmount(kruneAmount, true); assertAmount(kdexAmount, true);
    if (ctx.user.profile.id !== ctx.userId) throw new Error('user mismatch');
    const gate = checkAntiWhaleGate(ctx);
    if (!gate.canStake) throw new Error(gate.reason);
    const referenced = ctx.shardVault.getByUser(ctx.userId).reduce((n, p) => n + p.kruneStaked, 0);
    if (ctx.kruneLedger.get(ctx.userId) < referenced + kruneAmount) throw new Error('Insufficient unreferenced KRUNE balance');
    if (ctx.kdexLedger.get(ctx.userId) < kdexAmount) throw new Error('Insufficient KDEX balance');
    // All checks precede mutation. create validates the combined position before changing it.
    const shard = ctx.shardVault.create(ctx.userId, kruneAmount, kdexAmount);
    ctx.kdexLedger.subtract(ctx.userId, kdexAmount);
    return { success: true, stakeId: shard.id, shard };
  } catch (e) { return { success: false, error: (e as Error).message }; }
}
export function unstake(ctx: StakingContext, stakeId: string, forUSDC = true): { success: boolean; yieldAmount?: bigint; error?: string } {
  try {
    if (!forUSDC) throw new Error('KDEX redemption disabled');
    const p = ctx.shardVault.stakes.get(stakeId);
    if (!p || p.userId !== ctx.userId || ctx.user.profile.id !== ctx.userId) throw new Error('Stake not found');
    if (Date.now() < p.matureAt.getTime()) throw new Error('Stake locked for 90 days');
    const principal = ctx.kdexLedger.get(ctx.userId) + p.kdexStaked;
    assertAmount(principal);
    const reward = ctx.shardVault.redeem(stakeId);
    ctx.kdexLedger.set(ctx.userId, principal);
    return { success: true, yieldAmount: reward };
  } catch (e) { return { success: false, error: (e as Error).message }; }
}
/** Compatibility guard: a cron tick must never mint unfunded yield. */
export function accrueGlobalYield(_ctx: StakingContext): number { return 0; }
