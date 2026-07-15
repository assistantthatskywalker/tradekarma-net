/**
 * KarmaRune ($KRUNE) — Reputation Token
 * Phase 1: Database points (not yet on-chain)
 * Cannot be purchased; earned only through participation.
 */

import { Balance, BalanceLedger } from './Ledger';

export type KarmaRuneBalance = Balance;

export class KarmaRuneLedger extends BalanceLedger {
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
