import { types } from 'node:util';
/** Durable outbox protocol. A broadcast is submitted; only a finalized matching mint is confirmed. */
import { Address, Hash, encodeAbiParameters, keccak256, isAddress } from 'viem';
import { Transaction, TransactionType } from '../models/Transaction';
import { assertAmount } from '../models/Ledger';
import { toKarmaUnits } from './TradeKarmaChain';
export interface SettlementDomain { chainId: number; karmaRune: Address }
export interface EarningMinter {
  getSettlementDomain(): SettlementDomain;
  mintEarned(user: Address, amount: bigint, reasonHash: Hash): Promise<Hash>;
  kruneSettled(reasonHash: Hash): Promise<boolean>;
  /** Must read finalized state, not the pending/latest block. */
  kruneSettlementDigest(reasonHash: Hash): Promise<Hash>;
  waitForMintReceipt(hash: Hash): Promise<'success' | 'reverted'>;
}
export type SettlementStatus = 'prepared' | 'submitted' | 'confirmed' | 'failed';
export interface SettlementRecord {
  eventId: string;
  reasonHash: Hash;
  commitment: Hash;
  status: SettlementStatus;
  txHash?: Hash;
  attempts: number;
  lastError?: string;
}
export interface SettlementStore {
  get(key: string): SettlementRecord | undefined;
  put(key: string, value: SettlementRecord): void;
}
export class MemorySettlementStore implements SettlementStore {
  private records = new Map<string, SettlementRecord>();
  get(key: string): SettlementRecord | undefined { const v = this.records.get(key); return v && { ...v }; }
  put(key: string, value: SettlementRecord): void {
    const old = this.records.get(key);
    if (old && old.commitment !== value.commitment) throw new Error('immutable settlement payload conflict');
    if (old?.status !== 'confirmed') this.records.set(key, { ...value });
  }
}
function domainCheck(domain: SettlementDomain): void {
  if (!Number.isSafeInteger(domain.chainId) || domain.chainId <= 0 || !isAddress(domain.karmaRune) || /^0x0{40}$/i.test(domain.karmaRune)) throw new Error('invalid settlement domain');
}
/** Stable replay identity: changing an event payload must never create a second mint opportunity. */
export function computeReasonHash(event: Pick<Transaction, 'id'>, domain: SettlementDomain): Hash {
  domainCheck(domain);
  if (typeof event.id !== 'string' || !event.id || event.id.length > 200) throw new Error('invalid event id');
  return keccak256(encodeAbiParameters([{ type: 'string' }, { type: 'uint256' }, { type: 'address' }, { type: 'string' }],
    ['tradekarma:earning:v2', BigInt(domain.chainId), domain.karmaRune, event.id]));
}
export function mintDigest(user: Address, amount: bigint): Hash {
  return keccak256(encodeAbiParameters([{ type: 'address' }, { type: 'uint256' }], [user, amount]));
}
export class SettlementLedger {
  private inflight = new Map<string, Promise<SettlementRecord>>();
  constructor(private domain: SettlementDomain, private resolveVerifiedWallet: (userId: string) => Address | undefined,
    private store: SettlementStore = new MemorySettlementStore()) { domainCheck(domain); }
  get(eventId: string): SettlementRecord | undefined { return this.store.get(computeReasonHash({ id: eventId }, this.domain)); }
  isConfirmed(eventId: string): boolean { return this.get(eventId)?.status === 'confirmed'; }
  async settle(chain: EarningMinter, event: Transaction, userAddress: Address): Promise<SettlementRecord> {
    assertAmount(event.amountKRUNE, true);
    if (!Object.values(TransactionType).includes(event.type) || event.type === TransactionType.SPEND ||
        !types.isDate(event.timestamp) || !Number.isSafeInteger(event.timestamp.getTime()) || event.timestamp.getTime() < 0 ||
        !isAddress(userAddress) || this.resolveVerifiedWallet(event.userId)?.toLowerCase() !== userAddress.toLowerCase()) throw new Error('invalid event or unverified recipient wallet');
    const actualDomain = chain.getSettlementDomain();
    if (actualDomain.chainId !== this.domain.chainId || actualDomain.karmaRune.toLowerCase() !== this.domain.karmaRune.toLowerCase()) throw new Error('settlement chain/domain mismatch');
    const reasonHash = computeReasonHash(event, this.domain);
    const amount = toKarmaUnits(event.amountKRUNE);
    const commitment = keccak256(encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'string' }, { type: 'string' }, { type: 'address' }, { type: 'uint256' }, { type: 'uint256' }],
      [reasonHash, event.userId, event.type, userAddress, amount, BigInt(event.timestamp.getTime())]));
    const existing = this.store.get(reasonHash);
    if (existing && existing.commitment !== commitment) throw new Error('immutable settlement payload conflict');
    // Reserve the immutable payload before awaiting network calls, including concurrent callers.
    if (!existing) this.store.put(reasonHash, { eventId: event.id, reasonHash, commitment, status: 'prepared', attempts: 0 });
    const running = this.inflight.get(reasonHash);
    if (running) return { ...await running };
    const work = this.process(chain, reasonHash, userAddress, amount);
    this.inflight.set(reasonHash, work);
    try { return { ...await work }; } finally { this.inflight.delete(reasonHash); }
  }
  private async process(chain: EarningMinter, key: Hash, user: Address, amount: bigint): Promise<SettlementRecord> {
    let record = this.store.get(key)!;
    if (record.status === 'confirmed') return record;
    const expected = mintDigest(user, amount);
    const finalize = async (): Promise<boolean> => {
      const digest = await chain.kruneSettlementDigest(key);
      if (/^0x0{64}$/.test(digest)) return false;
      if (digest !== expected) throw new Error('on-chain mint recipient/amount conflict');
      record = { ...record, status: 'confirmed', lastError: undefined };
      this.store.put(key, record);
      return true;
    };
    try {
      if (await finalize()) return record;
      if (record.status === 'submitted' && record.txHash) {
        if (await chain.waitForMintReceipt(record.txHash) === 'reverted') throw new Error('mint transaction reverted');
        await finalize();
        return record;
      }
      if (await chain.kruneSettled(key)) {
        record = { ...record, status: 'submitted' };
        this.store.put(key, record);
        return record; // Another worker minted; wait for finality on the next reconciliation pass.
      }
      record = { ...record, attempts: record.attempts + 1, status: 'prepared', txHash: undefined, lastError: undefined };
      this.store.put(key, record);
      const txHash = await chain.mintEarned(user, amount, key);
      record = { ...record, txHash, status: 'submitted' };
      this.store.put(key, record);
      if (await chain.waitForMintReceipt(txHash) === 'reverted') throw new Error('mint transaction reverted');
      await finalize();
      return record;
    } catch (error) {
      const message = (error as Error).message;
      // Timeout/unknown inclusion stays submitted. Only a known revert permits replacement.
      record = { ...record, status: record.txHash && !message.includes('transaction reverted') ? 'submitted' : 'failed', lastError: message };
      this.store.put(key, record);
      throw error;
    }
  }
}
