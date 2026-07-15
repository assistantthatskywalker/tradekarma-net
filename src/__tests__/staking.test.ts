/**
 * Sprint 2: Staking & Yield Tests — including the anti-whale gate.
 */

import { User } from '../models/User';
import { KarmaRuneLedger } from '../models/KarmaRune';
import { KarmaDexLedger, KarmaShardVault } from '../models/Tokens';
import { stake, unstake, checkAntiWhalGate, accrueGlobalYield, StakingContext } from '../logic/staking';

function makeContext(userId: string): StakingContext {
  return {
    userId,
    user: new User(userId, `${userId}@example.com`, userId),
    kruneLedger: new KarmaRuneLedger(),
    kdexLedger: new KarmaDexLedger(),
    shardVault: new KarmaShardVault(),
  };
}

describe('Staking & Anti-Whale Gate', () => {
  describe('checkAntiWhalGate', () => {
    it('BLOCKS a whale: $10M KDEX, 0 KRUNE cannot stake', () => {
      const ctx = makeContext('whale');
      ctx.kdexLedger.set('whale', 10_000_000);
      ctx.kruneLedger.set('whale', 0);

      const gate = checkAntiWhalGate(ctx);
      expect(gate.canStake).toBe(false);
      expect(gate.reason).toMatch(/reputation/i);
    });

    it('BLOCKS a power user: lots of KRUNE, 0 KDEX cannot stake', () => {
      const ctx = makeContext('power');
      ctx.kruneLedger.set('power', 50_000);
      ctx.kdexLedger.set('power', 0);

      const gate = checkAntiWhalGate(ctx);
      expect(gate.canStake).toBe(false);
      expect(gate.reason).toMatch(/investment|KDEX/i);
    });

    it('ALLOWS a balanced user: both KRUNE and KDEX', () => {
      const ctx = makeContext('balanced');
      ctx.kruneLedger.set('balanced', 500);
      ctx.kdexLedger.set('balanced', 500);

      const gate = checkAntiWhalGate(ctx);
      expect(gate.canStake).toBe(true);
    });
  });

  describe('stake', () => {
    it('whale stake attempt is rejected with clear error', () => {
      const ctx = makeContext('whale');
      ctx.kdexLedger.set('whale', 10_000_000);
      const res = stake(ctx, 100, 1000);
      expect(res.success).toBe(false);
      expect(res.error).toMatch(/reputation/i);
    });

    it('balanced user stakes successfully, both tokens locked', () => {
      const ctx = makeContext('u');
      ctx.kruneLedger.set('u', 500);
      ctx.kdexLedger.set('u', 500);

      const res = stake(ctx, 500, 500);
      expect(res.success).toBe(true);
      expect(res.stakeId).toBeDefined();
      // Both balances drained into the vault
      expect(ctx.kruneLedger.get('u')).toBe(0);
      expect(ctx.kdexLedger.get('u')).toBe(0);
    });

    it('rejects staking more than balance', () => {
      const ctx = makeContext('u');
      ctx.kruneLedger.set('u', 100);
      ctx.kdexLedger.set('u', 100);
      const res = stake(ctx, 500, 500);
      expect(res.success).toBe(false);
      expect(res.error).toMatch(/insufficient/i);
    });
  });

  describe('unstake', () => {
    it('early unstake forfeits yield and returns principal', () => {
      const ctx = makeContext('u');
      ctx.kruneLedger.set('u', 500);
      ctx.kdexLedger.set('u', 500);
      const res = stake(ctx, 500, 500);
      accrueGlobalYield(ctx);

      const out = unstake(ctx, res.stakeId!);
      expect(out.success).toBe(true);
      expect(out.yieldAmount).toBe(0);
      expect(ctx.kruneLedger.get('u')).toBe(500);
      expect(ctx.kdexLedger.get('u')).toBe(500);
      expect(ctx.shardVault.stakes.size).toBe(0);
    });

    it('rejects an unknown or foreign stakeId', () => {
      const ctx = makeContext('u');
      ctx.kruneLedger.set('u', 500);
      ctx.kdexLedger.set('u', 500);
      stake(ctx, 100, 100);

      expect(unstake(ctx, 'no-such-stake').success).toBe(false);
      expect(unstake(ctx, 'other-user-1234').success).toBe(false);
      expect(ctx.shardVault.stakes.size).toBe(1); // nothing was touched
    });
  });

  describe('yield accrual', () => {
    it('accrues positive yield on the geometric mean over time', () => {
      const ctx = makeContext('u');
      ctx.kruneLedger.set('u', 10_000);
      ctx.kdexLedger.set('u', 10_000);
      const res = stake(ctx, 10_000, 10_000);
      expect(res.success).toBe(true);

      const yielded = accrueGlobalYield(ctx);
      expect(yielded).toBeGreaterThan(0);
    });

    it('more balanced stakes earn more than lopsided (geometric mean)', () => {
      // Balanced 1000/1000 vs lopsided 1999/1: same sum, different geometric mean
      const balanced = makeContext('bal');
      balanced.kruneLedger.set('bal', 1000);
      balanced.kdexLedger.set('bal', 1000);
      stake(balanced, 1000, 1000);
      const yBalanced = accrueGlobalYield(balanced);

      const lopsided = makeContext('lop');
      lopsided.kruneLedger.set('lop', 1999);
      lopsided.kdexLedger.set('lop', 1);
      stake(lopsided, 1999, 1);
      const yLopsided = accrueGlobalYield(lopsided);

      expect(yBalanced).toBeGreaterThan(yLopsided);
    });
  });
});
