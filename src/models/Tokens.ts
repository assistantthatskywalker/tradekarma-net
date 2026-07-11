/**
 * Token Models: KDEX (investment), KSHRD (yield)
 * Phase 1: Database representation (not yet on-chain)
 */

export interface KarmaDexBalance {
  userId: string;
  balance: number; // KDEX (fixed supply, purchased via DEX in Phase 2)
  lastUpdated: Date;
}

export interface KarmaShard {
  userId: string;
  amountStaked: number; // KSHRD accrued from staking
  kruneStaked: number; // KRUNE locked
  kdexStaked: number; // KDEX locked
  stakedAt: Date;
  matureAt: Date; // Unlock date (90 days)
  lastYieldAt: Date;
}

export class KarmaDexLedger {
  balances: Map<string, KarmaDexBalance> = new Map();

  get(userId: string): number {
    return this.balances.get(userId)?.balance || 0;
  }

  set(userId: string, amount: number): void {
    this.balances.set(userId, {
      userId,
      balance: amount,
      lastUpdated: new Date(),
    });
  }

  add(userId: string, amount: number): number {
    const current = this.get(userId);
    const newBalance = current + amount;
    this.set(userId, newBalance);
    return newBalance;
  }

  subtract(userId: string, amount: number): boolean {
    const current = this.get(userId);
    if (current < amount) return false;
    this.set(userId, current - amount);
    return true;
  }
}

export class KarmaShardVault {
  stakes: Map<string, KarmaShard> = new Map();

  create(
    userId: string,
    kruneAmount: number,
    kdexAmount: number,
    lockDays: number = 90
  ): KarmaShard {
    const now = new Date();
    const matureAt = new Date(now.getTime() + lockDays * 24 * 60 * 60 * 1000);

    const shard: KarmaShard = {
      userId,
      amountStaked: 0, // Starts at zero, accrues daily
      kruneStaked: kruneAmount,
      kdexStaked: kdexAmount,
      stakedAt: now,
      matureAt,
      lastYieldAt: now,
    };

    const id = `${userId}-${now.getTime()}`;
    this.stakes.set(id, shard);
    return shard;
  }

  getByUser(userId: string): KarmaShard[] {
    return Array.from(this.stakes.values()).filter((s) => s.userId === userId);
  }

  /**
   * Accrue daily yield: 1% annual (0.00274% daily).
   * Formula: (KRUNE × KDEX) ^ 0.5 × 0.000274 per day
   * This creates a symbiotic curve: both tokens needed, balanced incentives.
   */
  accrueYield(stakeId: string, days: number = 1): number {
    const stake = this.stakes.get(stakeId);
    if (!stake) return 0;

    const now = new Date();
    if (now < stake.matureAt) {
      // Accruing (not mature yet)
      const geometric = Math.sqrt(stake.kruneStaked * stake.kdexStaked);
      const dailyYield = geometric * 0.000274; // ~1% annual
      const totalYield = dailyYield * days;
      stake.amountStaked += totalYield;
      stake.lastYieldAt = now;
      return totalYield;
    }
    return 0;
  }

  redeem(stakeId: string, forUSDC: boolean): number {
    const stake = this.stakes.get(stakeId);
    if (!stake) return 0;

    const now = new Date();
    if (now < stake.matureAt) return 0; // Not mature yet

    const amount = stake.amountStaked;
    // In Phase 2, this would transfer to user wallet or treasury
    // For now, just return the amount
    this.stakes.delete(stakeId);
    return amount;
  }
}
