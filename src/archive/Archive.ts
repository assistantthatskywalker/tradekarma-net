import { types } from 'node:util';
/** Local append-only archive. Roles must be resolved by the trusted server, not request fields.
 * Hash chains alone cannot detect an operator rewriting history; retain signed checkpoints independently.
 */
import { sign, verify as verifySignature, KeyObject } from 'node:crypto';
import { link, HASH259_VERSION } from './hash259';
import { assertAmount } from '../models/Ledger';
export interface ArchivedTransaction { id: string; userId: string; type: string; amount: number; timestamp: Date; hash: string; prevHash: string }
export enum AccessRole { SYSTEM = 'system', AUDITOR = 'auditor', ADMIN = 'admin', USER = 'user' }
export interface ArchiveCheckpoint { version: string; count: number; head: string }
function payload(tx: Omit<ArchivedTransaction, 'hash' | 'prevHash'>): string {
  return JSON.stringify([tx.id, tx.userId, tx.type, tx.amount, tx.timestamp.toISOString()]);
}
export class TransactionArchive {
  private transactions: ArchivedTransaction[] = [];
  private lastHash = 'genesis';
  private auditLog: Array<{ userId: string; role: AccessRole; action: string; timestamp: Date; allowed: boolean }> = [];
  append(id: string, userId: string, type: string, amount: number, timestamp: Date): string {
    assertAmount(amount);
    if (![id, userId, type].every(x => typeof x === 'string' && x.length > 0) ||
        !types.isDate(timestamp) || !Number.isFinite(timestamp.getTime()) || this.transactions.some(t => t.id === id)) throw new Error('invalid or duplicate archive record');
    const tx = { id, userId, type, amount, timestamp: new Date(timestamp) };
    const hash = link(this.lastHash, payload(tx));
    this.transactions.push({ ...tx, hash, prevHash: this.lastHash });
    this.lastHash = hash;
    return hash;
  }
  checkpoint(): ArchiveCheckpoint { return { version: HASH259_VERSION, count: this.transactions.length, head: this.lastHash }; }
  signCheckpoint(privateKey: KeyObject): { checkpoint: ArchiveCheckpoint; signature: string } {
    if (privateKey.asymmetricKeyType !== 'ed25519') throw new Error('Ed25519 key required');
    const checkpoint = this.checkpoint();
    return { checkpoint, signature: sign(null, Buffer.from(JSON.stringify(checkpoint)), privateKey).toString('base64') };
  }
  verifySignedCheckpoint(checkpoint: ArchiveCheckpoint, signature: string, publicKey: KeyObject): boolean {
    if (publicKey.asymmetricKeyType !== 'ed25519') return false;
    return verifySignature(null, Buffer.from(JSON.stringify(checkpoint)), publicKey, Buffer.from(signature, 'base64')) && this.verify(checkpoint);
  }
  verify(expected?: ArchiveCheckpoint): boolean {
    try {
      let prev = 'genesis';
      const ids = new Set<string>();
      for (const tx of this.transactions) {
        assertAmount(tx.amount);
        if (ids.has(tx.id) || tx.prevHash !== prev || tx.hash !== link(prev, payload(tx))) return false;
        ids.add(tx.id); prev = tx.hash;
      }
      return prev === this.lastHash && (!expected || (expected.version === HASH259_VERSION && expected.head === prev && expected.count === this.transactions.length));
    } catch { return false; }
  }
  canRead(userId: string, role: AccessRole, targetUserId: string): boolean {
    return [AccessRole.SYSTEM, AccessRole.ADMIN, AccessRole.AUDITOR].includes(role) || (role === AccessRole.USER && userId === targetUserId);
  }
  getTransactions(userId: string, role: AccessRole, filter?: { userId?: string; type?: string }): ArchivedTransaction[] {
    const allowed = Object.values(AccessRole).includes(role) && (!filter?.userId || this.canRead(userId, role, filter.userId));
    this.logAccess(userId, role, 'read transactions', allowed);
    if (!allowed) return [];
    return this.transactions.filter(tx => (!filter?.userId || tx.userId === filter.userId) &&
      (!filter?.type || tx.type === filter.type) && this.canRead(userId, role, tx.userId)).map(tx => structuredClone(tx));
  }
  logAccess(userId: string, role: AccessRole, action: string, allowed: boolean): void {
    this.auditLog.push({ userId, role, action, allowed, timestamp: new Date() });
  }
  getAuditLog(role: AccessRole): typeof this.auditLog {
    return [AccessRole.SYSTEM, AccessRole.ADMIN].includes(role) ? structuredClone(this.auditLog) : [];
  }
  serialize(): Buffer {
    return Buffer.from(JSON.stringify({ version: HASH259_VERSION, checkpoint: this.checkpoint(), transactions: this.transactions }));
  }
  static deserialize(data: Buffer, expected?: ArchiveCheckpoint): TransactionArchive {
    const parsed = JSON.parse(data.toString('utf8'));
    if (parsed.version !== HASH259_VERSION || !Array.isArray(parsed.transactions)) throw new Error('unsupported archive format');
    const arc = new TransactionArchive();
    for (const tx of parsed.transactions) {
      if (tx.prevHash !== arc.lastHash) throw new Error('broken archive linkage');
      if (arc.append(tx.id, tx.userId, tx.type, tx.amount, new Date(tx.timestamp)) !== tx.hash) throw new Error('archive digest mismatch');
    }
    if (!arc.verify(parsed.checkpoint) || !arc.verify(expected)) throw new Error('archive checkpoint mismatch');
    return arc;
  }
}
