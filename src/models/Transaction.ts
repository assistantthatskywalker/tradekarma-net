/**
 * Transaction model for KRUNE earning events.
 * Immutable record of all reputation changes.
 */

export enum TransactionType {
  REVIEW = 'review',
  HELP = 'help',
  REFERRAL = 'referral',
  SHIP = 'ship',
  SPEND = 'spend',
}

export interface Transaction {
  id: string; // UUID
  userId: string;
  type: TransactionType;
  amountKRUNE: number;
  multiplier: number; // Quality multiplier (1.0–5.0)
  metadata: Record<string, any>; // Review text, order value, etc.
  timestamp: Date;
  isRetroactive?: boolean; // Set if awarded retroactively for helpfulness
}

export class TransactionLog {
  transactions: Map<string, Transaction> = new Map();

  record(tx: Transaction): void {
    if (this.transactions.has(tx.id)) throw new Error("duplicate transaction id");
    this.transactions.set(tx.id, structuredClone(tx));
  }

  getByUser(userId: string): Transaction[] {
    return Array.from(this.transactions.values()).filter(
      (tx) => tx.userId === userId
    ).map(tx => structuredClone(tx));
  }

  getByType(type: TransactionType): Transaction[] {
    return Array.from(this.transactions.values()).filter(
      (tx) => tx.type === type
    ).map(tx => structuredClone(tx));
  }

  verify(id: string): Transaction | null {
    const tx = this.transactions.get(id);
    return tx ? structuredClone(tx) : null;
  }
}
