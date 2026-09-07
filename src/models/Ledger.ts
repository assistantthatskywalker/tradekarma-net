/**
 * Generic per-user balance ledger (Phase 1: in-memory database representation).
 * Shared by KRUNE (earned) and KDEX (purchased) — the token rules differ,
 * the bookkeeping does not.
 */

export function assertAmount(amount: number, positive = false): void {
  if (!Number.isSafeInteger(amount) || amount < 0 || (positive && amount === 0)) {
    throw new Error("amount must be a bounded non-negative integer (positive for stakes)");
  }
}

export interface Balance {
  userId: string;
  balance: number;
  lastUpdated: Date;
}

export class BalanceLedger {
  balances: Map<string, Balance> = new Map();

  get(userId: string): number {
    return this.balances.get(userId)?.balance ?? 0;
  }

  set(userId: string, amount: number): void {
    assertAmount(amount);
    this.balances.set(userId, {
      userId,
      balance: amount,
      lastUpdated: new Date(),
    });
  }

  add(userId: string, amount: number): number {
    assertAmount(amount);
    const newBalance = this.get(userId) + amount;
    this.set(userId, newBalance);
    return newBalance;
  }

  subtract(userId: string, amount: number): boolean {
    assertAmount(amount);
    const current = this.get(userId);
    if (current < amount) return false;
    this.set(userId, current - amount);
    return true;
  }
}
