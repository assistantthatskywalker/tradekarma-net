/**
 * Immutable Transaction Archive
 * Append-only log with SHA-256 hash chain for tamper-evidence.
 * Version: hash259-v1
 */

import { link } from './hash259';

export interface ArchivedTransaction {
  id: string;
  userId: string;
  type: string;
  amount: number;
  timestamp: Date;
  hash: string;
  prevHash: string;
}

export enum AccessRole {
  SYSTEM = 'system', // Full access
  AUDITOR = 'auditor', // Read-only access
  ADMIN = 'admin', // Full access
  USER = 'user', // Can read own transactions only
}

export class TransactionArchive {
  private transactions: ArchivedTransaction[] = [];
  private lastHash: string = 'genesis';

  /**
   * Add transaction to archive with hash linkage (hash259 chain).
   * Returns hash for verification.
   */
  append(
    id: string,
    userId: string,
    type: string,
    amount: number,
    timestamp: Date
  ): string {
    const hash = link(
      this.lastHash,
      `${id}|${userId}|${type}|${amount}|${timestamp.toISOString()}`
    );

    const tx: ArchivedTransaction = {
      id,
      userId,
      type,
      amount,
      timestamp,
      hash,
      prevHash: this.lastHash,
    };

    this.transactions.push(tx);
    this.lastHash = hash;

    return hash;
  }

  /**
   * Verify hash chain integrity.
   * Returns true if chain is unbroken.
   */
  verify(): boolean {
    let prevHash = 'genesis';

    for (const tx of this.transactions) {
      if (tx.prevHash !== prevHash) {
        return false; // Chain broken
      }

      const expectedHash = link(
        tx.prevHash,
        `${tx.id}|${tx.userId}|${tx.type}|${tx.amount}|${tx.timestamp.toISOString()}`
      );

      if (tx.hash !== expectedHash) {
        return false; // Hash mismatch (tampered)
      }

      prevHash = tx.hash;
    }

    return true;
  }

  /**
   * Role-based access control.
   * Check if user can read transaction.
   */
  canRead(userId: string, role: AccessRole, targetUserId: string): boolean {
    if (role === AccessRole.SYSTEM || role === AccessRole.ADMIN) {
      return true;
    }
    if (role === AccessRole.AUDITOR) {
      return true; // Read-only access to all
    }
    if (role === AccessRole.USER) {
      return userId === targetUserId; // Can only read own
    }
    return false;
  }

  /**
   * Get transactions with access control.
   */
  getTransactions(
    userId: string,
    role: AccessRole,
    filter?: { userId?: string; type?: string }
  ): ArchivedTransaction[] {
    let result = this.transactions;

    if (filter?.userId) {
      result = result.filter((tx) => tx.userId === filter.userId);
    }
    if (filter?.type) {
      result = result.filter((tx) => tx.type === filter.type);
    }

    // Apply access control
    return result.filter((tx) => this.canRead(userId, role, tx.userId));
  }

  /**
   * Audit log: all access attempts.
   * In production, this would be persisted separately.
   */
  private auditLog: Array<{
    userId: string;
    role: AccessRole;
    action: string;
    timestamp: Date;
    allowed: boolean;
  }> = [];

  logAccess(
    userId: string,
    role: AccessRole,
    action: string,
    allowed: boolean
  ): void {
    this.auditLog.push({
      userId,
      role,
      action,
      timestamp: new Date(),
      allowed,
    });
  }

  getAuditLog(role: AccessRole): typeof this.auditLog {
    // Only SYSTEM and ADMIN can read audit log
    if (role === AccessRole.SYSTEM || role === AccessRole.ADMIN) {
      return this.auditLog;
    }
    return [];
  }

  /**
   * Serialize archive to binary for backup.
   * Format: transaction count + (each tx: id, userId, type, amount, timestamp, hash)
   */
  serialize(): Buffer {
    const buffers: Buffer[] = [];

    // Header: archive version
    buffers.push(Buffer.from('hash259-v1', 'utf-8'));
    buffers.push(Buffer.from([0])); // Null terminator

    // Transaction count
    buffers.push(Buffer.allocUnsafe(4));
    buffers[buffers.length - 1].writeUInt32BE(this.transactions.length, 0);

    // Transactions
    for (const tx of this.transactions) {
      buffers.push(Buffer.from(tx.id, 'utf-8'));
      buffers.push(Buffer.from([0]));
      buffers.push(Buffer.from(tx.userId, 'utf-8'));
      buffers.push(Buffer.from([0]));
      buffers.push(Buffer.from(tx.type, 'utf-8'));
      buffers.push(Buffer.from([0]));
      buffers.push(Buffer.allocUnsafe(8));
      buffers[buffers.length - 1].writeDoubleBE(tx.amount, 0);
      buffers.push(Buffer.from(tx.hash, 'hex'));
      buffers.push(Buffer.from(tx.prevHash, 'hex'));
    }

    return Buffer.concat(buffers);
  }
}
