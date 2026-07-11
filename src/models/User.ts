/**
 * User model for TradeKarma reputation system.
 * Tracks identity, reputation balance, and transaction history.
 */

export interface UserProfile {
  id: string; // UUID
  email: string;
  username: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface ReputationLedger {
  userId: string;
  balance: number; // KRUNE balance (database points, Phase 1)
  earned: number; // Total earned (cumulative)
  spent: number; // Total spent (on perks, staking)
  transactions: string[]; // Transaction IDs (for audit trail)
}

export class User {
  profile: UserProfile;
  reputation: ReputationLedger;

  constructor(id: string, email: string, username: string) {
    this.profile = {
      id,
      email,
      username,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
    this.reputation = {
      userId: id,
      balance: 0,
      earned: 0,
      spent: 0,
      transactions: [],
    };
  }

  addKRUNE(amount: number, txId: string): void {
    this.reputation.balance += amount;
    this.reputation.earned += amount;
    this.reputation.transactions.push(txId);
    this.profile.updatedAt = new Date();
  }

  spendKRUNE(amount: number, txId: string): boolean {
    if (this.reputation.balance < amount) {
      return false;
    }
    this.reputation.balance -= amount;
    this.reputation.spent += amount;
    this.reputation.transactions.push(txId);
    this.profile.updatedAt = new Date();
    return true;
  }

  getReputation(): number {
    return this.reputation.balance;
  }
}
