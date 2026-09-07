/** Atomic, persistent reputation issuance for a trusted Node service. Not an authentication or order-verification provider. */
import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import { VerifiedEarningEvent, awardReview, awardReferral, awardHelpfulness, awardShipment } from '../logic/earning';
import { Transaction, TransactionLog, TransactionType } from '../models/Transaction';
import { User } from '../models/User';
function encodeEvidence(e: VerifiedEarningEvent): string {
  const ordered = Object.fromEntries(Object.entries(e).sort(([a], [b]) => a.localeCompare(b)));
  return JSON.stringify(ordered);
}
function decodeEvidence(raw: string): VerifiedEarningEvent {
  const e = JSON.parse(raw);
  e.verifiedAt = new Date(e.verifiedAt);
  if (e.activeSince) e.activeSince = new Date(e.activeSince);
  if (e.activeThrough) e.activeThrough = new Date(e.activeThrough);
  return e;
}
function decodeTransaction(raw: string): Transaction {
  const tx = JSON.parse(raw); tx.timestamp = new Date(tx.timestamp); return tx;
}
export class SqliteEarningStore {
  private db: DatabaseSync;
  constructor(path: string) {
    if (!path || path === ':memory:') throw new Error('durable database path required');
    this.db = new DatabaseSync(path);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS verified_events (id TEXT PRIMARY KEY, payload TEXT NOT NULL, digest TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS reputation_accounts (user_id TEXT PRIMARY KEY, balance INTEGER NOT NULL CHECK(balance BETWEEN 0 AND 9007199254740991));
      CREATE TABLE IF NOT EXISTS reputation_awards (event_id TEXT PRIMARY KEY REFERENCES verified_events(id), user_id TEXT NOT NULL,
        type TEXT NOT NULL, subject_id TEXT NOT NULL, scope_key TEXT UNIQUE NOT NULL, amount INTEGER NOT NULL CHECK(amount>=0), tx TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS reputation_awards_user ON reputation_awards(user_id);
      CREATE INDEX IF NOT EXISTS reputation_awards_subject ON reputation_awards(type, subject_id);
      CREATE TABLE IF NOT EXISTS reputation_journal (event_id TEXT NOT NULL REFERENCES reputation_awards(event_id), account TEXT NOT NULL,
        delta INTEGER NOT NULL, PRIMARY KEY(event_id, account));
      PRAGMA foreign_keys=ON;`);
  }
  /** Invoke only after commerce verification; never register evidence directly from agent requests. */
  registerVerifiedEvent(event: VerifiedEarningEvent): void {
    if (!event.id || event.id.length > 200) throw new Error('invalid evidence id');
    const payload = encodeEvidence(event), digest = createHash('sha256').update(payload).digest('hex');
    this.db.prepare('INSERT INTO verified_events VALUES (?, ?, ?) ON CONFLICT(id) DO NOTHING').run(event.id, payload, digest);
    const old = this.db.prepare('SELECT digest FROM verified_events WHERE id=?').get(event.id)!;
    if (old.digest !== digest) throw new Error('immutable evidence conflict');
  }
  getVerifiedEvent(id: string): VerifiedEarningEvent | undefined {
    const row = this.db.prepare('SELECT payload FROM verified_events WHERE id=?').get(id);
    return row ? decodeEvidence(row.payload as string) : undefined;
  }
  balance(userId: string): number {
    return Number(this.db.prepare('SELECT balance FROM reputation_accounts WHERE user_id=?').get(userId)?.balance ?? 0);
  }
  transactions(userId: string): Transaction[] {
    return this.db.prepare('SELECT tx FROM reputation_awards WHERE user_id=? ORDER BY rowid').all(userId).map(r => decodeTransaction(r.tx as string));
  }
  /** Idempotent event consumption and balanced journal posting in a single durable transaction. */
  award(eventId: string): Transaction {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const existing = this.db.prepare('SELECT tx FROM reputation_awards WHERE event_id=?').get(eventId);
      if (existing) { this.db.exec('COMMIT'); return decodeTransaction(existing.tx as string); }
      const e = this.getVerifiedEvent(eventId);
      if (!e) throw new Error('verified event not found');
      const user = new User(e.userId, '', e.userId);
      user.reputation.balance = this.balance(e.userId); user.reputation.earned = user.reputation.balance;
      const log = new TransactionLog();
      // Indexed reads of the user and relevant subject instead of scanning all marketplace activity.
      const rows = this.db.prepare('SELECT tx FROM reputation_awards WHERE user_id=? OR (type=? AND subject_id=?)').all(e.userId, e.type, e.subjectId);
      for (const row of rows) log.record(decodeTransaction(row.tx as string));
      const ctx = { userId: e.userId, user, transactionLog: log, evidence: e };
      let tx: Transaction;
      switch (e.type) {
        case TransactionType.REVIEW: tx = awardReview(ctx, e.subjectId, e.orderValue!, e.hasPhotos!, e.textLength!, e.isDetailed!); break;
        case TransactionType.HELP: tx = awardHelpfulness(ctx, e.subjectId, e.answerText!); break;
        case TransactionType.REFERRAL: tx = awardReferral(ctx, e.subjectId); break;
        case TransactionType.SHIP: tx = awardShipment(ctx, e.subjectId, e.orderValue!, e.daysToShip!); break;
        default: throw new Error('unsupported earning event');
      }
      const scope = JSON.stringify([e.type, e.subjectId, [TransactionType.REFERRAL, TransactionType.SHIP].includes(e.type) ? 'global' : e.userId]);
      this.db.prepare('INSERT INTO reputation_awards VALUES (?, ?, ?, ?, ?, ?, ?)').run(e.id, e.userId, e.type, e.subjectId, scope, tx.amountKRUNE, JSON.stringify(tx));
      this.db.prepare(`INSERT INTO reputation_accounts VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET balance=excluded.balance`).run(e.userId, user.getReputation());
      const post = this.db.prepare('INSERT INTO reputation_journal VALUES (?, ?, ?)');
      post.run(e.id, 'system:issued', -tx.amountKRUNE); post.run(e.id, `user:${e.userId}`, tx.amountKRUNE);
      this.db.exec('COMMIT'); return tx;
    } catch (e) { this.db.exec('ROLLBACK'); throw e; }
  }
  reconcile(): boolean {
    const unbalanced = this.db.prepare('SELECT event_id FROM reputation_journal GROUP BY event_id HAVING SUM(delta) != 0 OR COUNT(*) != 2').all();
    const drift = this.db.prepare(`SELECT a.user_id FROM reputation_accounts a WHERE a.balance !=
      (SELECT COALESCE(SUM(j.delta),0) FROM reputation_journal j WHERE j.account='user:' || a.user_id)`).all();
    return unbalanced.length === 0 && drift.length === 0;
  }
  close(): void { this.db.close(); }
}
