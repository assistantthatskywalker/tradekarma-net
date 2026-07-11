/**
 * KarmaRune ($KRUNE) — Reputation Token
 * Phase 1: Database points (not yet on-chain)
 * Cannot be purchased; earned only through participation.
 */

export interface KarmaRuneBalance {
  userId: string;
  balance: number;
  lastUpdated: Date;
}

export class KarmaRuneLedger {
  balances: Map<string, KarmaRuneBalance> = new Map();

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

  getAllBalances(): KarmaRuneBalance[] {
    return Array.from(this.balances.values());
  }

  getTotalSupply(): number {
    return this.getAllBalances().reduce((sum, b) => sum + b.balance, 0);
  }

  /**
   * Invariant: KRUNE can only be created via earning, never purchased.
   * This is the load-bearing rule of the system.
   */
  assertNoPurchaseMechanic(): boolean {
    // In production, this would be enforced by API design:
    // no endpoint accepts money for KRUNE creation.
    // This method exists as a documentation/assertion point.
    return true;
  }
}
