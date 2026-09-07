import { User } from '../models/User';
import { KarmaRuneLedger } from '../models/KarmaRune';
import { KarmaDexLedger, KarmaShardVault } from '../models/Tokens';
import { stake, unstake, accrueGlobalYield, StakingContext } from '../logic/staking';
function context(userId = 'alice', shared?: StakingContext): StakingContext {
  const ctx = { userId, user: new User(userId, 'test@example.invalid', userId),
    kruneLedger: shared?.kruneLedger ?? new KarmaRuneLedger(), kdexLedger: shared?.kdexLedger ?? new KarmaDexLedger(),
    shardVault: shared?.shardVault ?? new KarmaShardVault() };
  ctx.kruneLedger.set(userId, 1000); ctx.kdexLedger.set(userId, 1000); return ctx;
}
beforeEach(() => { jest.useFakeTimers(); jest.setSystemTime(new Date('2026-01-01')); });
afterEach(() => jest.useRealTimers());
it.each([-10, 0, NaN, Infinity, 1.5, Number.MAX_SAFE_INTEGER + 1])('rejects invalid stake %s without mutations', n => {
  const ctx = context(); expect(stake(ctx, n, n).success).toBe(false);
  expect(ctx.kruneLedger.get('alice')).toBe(1000); expect(ctx.kdexLedger.get('alice')).toBe(1000);
  expect(ctx.shardVault.stakes.size).toBe(0);
});
it('references reputation, escrows capital, enforces lock, and restores full principal at maturity', () => {
  const ctx = context(); const opened = stake(ctx, 100, 100);
  expect(ctx.kruneLedger.get('alice')).toBe(1000); expect(ctx.kdexLedger.get('alice')).toBe(900);
  expect(unstake(ctx, opened.stakeId!).success).toBe(false);
  jest.advanceTimersByTime(90 * 86400_000);
  expect(unstake(ctx, opened.stakeId!).success).toBe(true);
  expect(ctx.kruneLedger.get('alice')).toBe(1000); expect(ctx.kdexLedger.get('alice')).toBe(1000);
  expect(unstake(ctx, opened.stakeId!).success).toBe(false);
});
it('blocks zero reputation and double referencing; top-ups reset the whole lock', () => {
  const ctx = context(); ctx.kruneLedger.set('alice', 0);
  expect(stake(ctx, 1, 1).success).toBe(false);
  ctx.kruneLedger.set('alice', 100);
  const first = stake(ctx, 50, 50); jest.advanceTimersByTime(89 * 86400_000);
  expect(stake(ctx, 51, 10).success).toBe(false);
  expect(stake(ctx, 50, 50).stakeId).toBe(first.stakeId);
  jest.advanceTimersByTime(2 * 86400_000);
  expect(unstake(ctx, first.stakeId!).success).toBe(false);
});
it('earns nothing with time alone, splits only funded fees, and conserves cash', () => {
  const a = context(); const b = context('bob', a);
  const pa = stake(a, 100, 100), pb = stake(b, 100, 100);
  expect(accrueGlobalYield(a)).toBe(0); expect(accrueGlobalYield(a)).toBe(0);
  expect(() => a.shardVault.depositFees('merchant', 1000000)).toThrow(/insufficient/);
  a.shardVault.usdcBalances.set('merchant', 1000000);
  a.shardVault.depositFees('merchant', 1000000);
  expect(a.shardVault.pendingUsdc(pa.stakeId!)).toBe(500000n);
  jest.advanceTimersByTime(90 * 86400_000);
  expect(unstake(a, pa.stakeId!).yieldAmount).toBe(500000n);
  expect(unstake(b, pb.stakeId!).yieldAmount).toBe(500000n);
  expect(a.shardVault.usdcBalances.get('merchant')).toBe(0);
  expect(a.shardVault.usdcBalances.get('alice') + a.shardVault.usdcBalances.get('bob')).toBe(1000000);
});
it('prevents foreign exits and mutation through position reads', () => {
  const a = context(); const b = context('bob', a); const p = stake(a, 100, 100);
  a.shardVault.stakes.get(p.stakeId!)!.matureAt = new Date(0);
  expect(unstake(a, p.stakeId!).success).toBe(false);
  expect(unstake(b, p.stakeId!).success).toBe(false);
  expect(unstake(a, p.stakeId!, false).success).toBe(false);
});
