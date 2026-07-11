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
    this.transactions.set(tx.id, tx);
  }

  getByUser(userId: string): Transaction[] {
    return Array.from(this.transactions.values()).filter(
      (tx) => tx.userId === userId
    );
  }

  getByType(type: TransactionType): Transaction[] {
    return Array.from(this.transactions.values()).filter(
      (tx) => tx.type === type
    );
  }

  verify(id: string): Transaction | null {
    return this.transactions.get(id) || null;
  }
}
