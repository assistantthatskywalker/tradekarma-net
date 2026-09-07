import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Address, Hash } from 'viem';
import { Transaction, TransactionType } from '../models/Transaction';
import { SettlementLedger, EarningMinter, computeReasonHash, mintDigest, SettlementDomain } from '../chain/settlement';
import { SqliteSettlementStore } from '../storage/SqliteSettlementStore';
const user: Address = '0x0000000000000000000000000000000000000011';
const other: Address = '0x0000000000000000000000000000000000000022';
const domain: SettlementDomain = { chainId: 84532, karmaRune: '0x0000000000000000000000000000000000000033' };
const event: Transaction = { id: 'event1', userId: 'alice', type: TransactionType.REVIEW, amountKRUNE: 10,
  timestamp: new Date(1), multiplier: 1, metadata: {} };
const zero = ('0x' + '0'.repeat(64)) as Hash;
class Chain implements EarningMinter {
  writes = 0; finalized = false; mined = false; receipt: 'success' | 'reverted' = 'success'; timeout = false; failBroadcast = false;
  digest: Hash = zero;
  getSettlementDomain() { return domain; }
  async mintEarned(address: Address, amount: bigint, _reasonHash: Hash): Promise<Hash> {
    this.writes++;
    if (this.failBroadcast) throw new Error('RPC failed');
    this.digest = mintDigest(address, amount); this.mined = this.receipt === 'success';
    return ('0x' + 'a'.repeat(64)) as Hash;
  }
  async kruneSettled(_key: Hash) { return this.mined; }
  async kruneSettlementDigest(_key: Hash) { return this.finalized ? this.digest : zero; }
  async waitForMintReceipt(_hash: Hash) { if (this.timeout) throw new Error('receipt timeout'); return this.receipt; }
}
const ledger = () => new SettlementLedger(domain, () => user);
it('uses stable event identity with domain separation', () => {
  const key = computeReasonHash(event, domain);
  expect(computeReasonHash({ ...event }, domain)).toBe(key);
  expect(computeReasonHash({ id: 'other' }, domain)).not.toBe(key);
  expect(computeReasonHash(event, { ...domain, chainId: 8453 })).not.toBe(key);
  expect(computeReasonHash(event, { ...domain, karmaRune: other })).not.toBe(key);
});
it('does not confirm broadcast or even mined transactions before finalized matching state', async () => {
  const chain = new Chain(), outbox = ledger();
  expect((await outbox.settle(chain, event, user)).status).toBe('submitted');
  expect(outbox.isConfirmed(event.id)).toBe(false);
  chain.finalized = true;
  expect((await outbox.settle(chain, event, user)).status).toBe('confirmed');
  await outbox.settle(chain, event, user); expect(chain.writes).toBe(1);
});
it('retries known reverted transactions, but keeps timeout attempts submitted', async () => {
  const chain = new Chain(), outbox = ledger(); chain.receipt = 'reverted';
  await expect(outbox.settle(chain, event, user)).rejects.toThrow(/reverted/);
  expect(outbox.get(event.id)!.status).toBe('failed');
  chain.receipt = 'success'; chain.timeout = true;
  await expect(outbox.settle(chain, event, user)).rejects.toThrow(/timeout/);
  expect(outbox.get(event.id)!.status).toBe('submitted');
  chain.timeout = false; chain.finalized = true;
  expect((await outbox.settle(chain, event, user)).status).toBe('confirmed');
  expect(chain.writes).toBe(2);
});
it('retries failed broadcast without changing the event key', async () => {
  const chain = new Chain(), outbox = ledger(); chain.failBroadcast = true;
  await expect(outbox.settle(chain, event, user)).rejects.toThrow(/RPC/);
  chain.failBroadcast = false; chain.finalized = true;
  expect((await outbox.settle(chain, event, user)).attempts).toBe(2);
});
it('deduplicates concurrent settlement and rejects changed payloads', async () => {
  const chain = new Chain(), outbox = ledger();
  await Promise.all([outbox.settle(chain, event, user), outbox.settle(chain, event, user)]);
  expect(chain.writes).toBe(1);
  await expect(outbox.settle(chain, { ...event, amountKRUNE: 11 }, user)).rejects.toThrow(/conflict/);
  await expect(outbox.settle(chain, event, other)).rejects.toThrow(/unverified/);
});
it('does not accept an already-finalized mint to the wrong recipient after local state loss', async () => {
  const chain = new Chain(); chain.mined = true; chain.finalized = true; chain.digest = mintDigest(other, 10n * 10n ** 18n);
  await expect(ledger().settle(chain, event, user)).rejects.toThrow(/conflict/);
  expect(chain.writes).toBe(0);
});
it.each([-1, 0, NaN, Infinity, 1.1, Number.MAX_SAFE_INTEGER + 1])('rejects unsafe event amount %s', async amountKRUNE => {
  await expect(ledger().settle(new Chain(), { ...event, amountKRUNE }, user)).rejects.toThrow();
});
it('persists immutable outbox state across restart and database connections', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'tradekarma-outbox-'));
  const path = join(dir, 'state.sqlite');
  let store = new SqliteSettlementStore(path);
  try {
    const chain = new Chain();
    await new SettlementLedger(domain, () => user, store).settle(chain, event, user);
    store.close(); store = new SqliteSettlementStore(path);
    const restarted = new SettlementLedger(domain, () => user, store);
    await expect(restarted.settle(chain, { ...event, timestamp: new Date(2) }, user)).rejects.toThrow(/conflict/);
    chain.finalized = true;
    expect((await restarted.settle(chain, event, user)).status).toBe('confirmed');
    expect(chain.writes).toBe(1);
    const second = new SqliteSettlementStore(path);
    try {
      const key = computeReasonHash(event, domain), old = second.get(key)!;
      expect(() => second.put(key, { ...old, commitment: zero })).toThrow(/conflict/);
      second.put(key, { ...old, status: 'failed' }); expect(second.get(key)!.status).toBe('confirmed');
    } finally { second.close(); }
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
