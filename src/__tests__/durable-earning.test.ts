import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { SqliteEarningStore } from '../storage/SqliteEarningStore';
import { TransactionType } from '../models/Transaction';
import type { VerifiedEarningEvent } from '../logic/earning';
const event: VerifiedEarningEvent = { id: 'order-review-1', userId: 'alice', type: TransactionType.REVIEW, subjectId: 'product',
  verifiedAt: new Date(1), orderValue: 100, hasPhotos: true, textLength: 250, isDetailed: true };
it('atomically persists evidence, reputation and a balanced journal across process loss', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tradekarma-earning-')); const path = join(dir, 'ledger.sqlite');
  let store = new SqliteEarningStore(path);
  try {
    store.registerVerifiedEvent(event);
    expect(store.award(event.id).amountKRUNE).toBe(117);
    store.close(); store = new SqliteEarningStore(path);
    expect(store.award(event.id).amountKRUNE).toBe(117);
    expect(store.balance('alice')).toBe(117);
    expect(store.transactions('alice')).toHaveLength(1);
    expect(store.reconcile()).toBe(true);
    expect(() => store.registerVerifiedEvent({ ...event, orderValue: 10000 })).toThrow(/conflict/);
    store.registerVerifiedEvent({ ...event, id: 'different-event-same-subject' });
    expect(() => store.award('different-event-same-subject')).toThrow(/already/);
    expect(store.balance('alice')).toBe(117); expect(store.reconcile()).toBe(true);
    const second = new SqliteEarningStore(path);
    try { expect(second.award(event.id).amountKRUNE).toBe(117); expect(second.balance('alice')).toBe(117); } finally { second.close(); }
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
it('rejected evidence cannot produce a partial accounting entry', () => {
  const dir = mkdtempSync(join(tmpdir(), 'tradekarma-rollback-')); const store = new SqliteEarningStore(join(dir, 'ledger.sqlite'));
  try {
    store.registerVerifiedEvent({ ...event, type: TransactionType.REFERRAL, subjectId: 'alice' });
    expect(() => store.award(event.id)).toThrow();
    expect(store.balance('alice')).toBe(0); expect(store.transactions('alice')).toHaveLength(0); expect(store.reconcile()).toBe(true);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
