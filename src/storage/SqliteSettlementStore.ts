/** Persistent outbox for a Node 24 service with durable local storage. Never use ephemeral serverless disks. */
import { DatabaseSync } from 'node:sqlite';
import type { SettlementRecord, SettlementStore } from '../chain/settlement';
export class SqliteSettlementStore implements SettlementStore {
  private db: DatabaseSync;
  constructor(path: string) {
    if (!path || path === ':memory:') throw new Error('durable database path required');
    this.db = new DatabaseSync(path);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS settlement_outbox (key TEXT PRIMARY KEY, commitment TEXT NOT NULL, status TEXT NOT NULL, record TEXT NOT NULL);`);
  }
  get(key: string): SettlementRecord | undefined {
    const row = this.db.prepare('SELECT record FROM settlement_outbox WHERE key = ?').get(key);
    return row ? JSON.parse(row.record as string) : undefined;
  }
  put(key: string, value: SettlementRecord): void {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const old = this.get(key);
      if (old && old.commitment !== value.commitment) throw new Error('immutable settlement payload conflict');
      if (old?.status !== 'confirmed') this.db.prepare(`INSERT INTO settlement_outbox VALUES (?, ?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET status=excluded.status, record=excluded.record`).run(key, value.commitment, value.status, JSON.stringify(value));
      this.db.exec('COMMIT');
    } catch (e) { this.db.exec('ROLLBACK'); throw e; }
  }
  close(): void { this.db.close(); }
}
