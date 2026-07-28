/**
 * Settlement — bridges off-chain earning events (src/logic/earning.ts) to
 * on-chain KRUNE mints.
 *
 * Off-chain earning happens instantly against an in-memory ledger, no gas.
 * Settlement is the async, fallible step that mints the equivalent KRUNE on
 * Base via mintEarned. Because it crosses a trust boundary (an RPC call that
 * can time out, revert, or be retried), the ledger below tracks status per
 * off-chain event id and is safe to call repeatedly for the same event.
 *
 * Failure modes handled:
 *  - Duplicate settlement of the same event, same process: a CONFIRMED event
 *    short-circuits in settle() and never touches the chain again.
 *  - Transient submission failure (RPC error, nonce race, gas spike, revert):
 *    the event is marked FAILED with the error message. Calling settle()
 *    again for the same event is the retry path — it reuses the exact same
 *    deterministic reasonHash, so a human (or a script) can always reconcile
 *    a mint back to the off-chain event that caused it, no matter how many
 *    attempts it took.
 *  - Duplicate settlement after a process restart: the in-memory ledger
 *    above does not survive a restart, so on its own it cannot tell a fresh
 *    retry from a first attempt. KarmaRune now backstops this on-chain —
 *    `mintEarned` reverts with "KRUNE: already settled" if `reasonHash` was
 *    already consumed (`settled(reasonHash) == true`). `settle()` reads
 *    `settled()` before submitting and short-circuits to a synthesized
 *    CONFIRMED record (txHash undefined — the mint happened in a previous
 *    process, so there is no transaction hash to report here) if it is
 *    already true. This is an optimisation, not the correctness mechanism:
 *    see the race note below.
 *
 * Failure modes deliberately NOT handled here (documented, not silently
 * ignored):
 *  - The gap between checking `settled()` and submitting `mintEarned` is not
 *    atomic. Two concurrent settle() calls for the same event (e.g. two
 *    process instances retrying at once) can both read `settled() == false`
 *    and both submit a transaction. This is fine, not a bug: only one of the
 *    two mints can actually land, because the contract's own
 *    `require(!settled[reasonHash])` is the real backstop and is atomic at
 *    the EVM level. The loser's transaction reverts and its settle() call
 *    surfaces that revert as a FAILED record, same as any other reverted
 *    submission — no double mint is possible, only a wasted gas fee on the
 *    losing transaction. The pre-check exists purely to avoid paying for
 *    that doomed transaction in the common case (a lone retry after a
 *    restart), not to guarantee only one is ever sent.
 *  - "Did it actually land?" after a timed-out submission that was NOT a
 *    settled-guard short-circuit. If the RPC call to broadcast times out, we
 *    cannot tell from here whether it was actually mined. This layer marks
 *    that attempt FAILED and relies on retry; the on-chain `settled()` check
 *    on the next attempt is exactly what now makes that retry safe (see
 *    above), without needing an indexer or log-scanning step.
 *  - Chain reorgs after a receipt is observed. A transaction hash returned by
 *    mintEarned is treated as CONFIRMED once the write call resolves; this
 *    module does not wait for confirmation depth or re-check after a reorg.
 *  - Mapping off-chain userId -> on-chain wallet address. Callers supply the
 *    address explicitly; there is no address book here.
 *  - Persistence across process restarts. The ledger is in-memory only,
 *    mirroring the rest of Phase 1 (mirrors BalanceLedger, TransactionLog).
 *    A production deployment would back this with a database keyed by event
 *    id — what changed is that a restart can no longer cause a *duplicate
 *    mint*, only the loss of this process's bookkeeping (attempts count,
 *    txHash) about a mint that already happened.
 */

import type { Address, Hash } from 'viem';
import { encodePacked, keccak256 } from 'viem';
import { Transaction } from '../models/Transaction';
import { toKarmaUnits } from './TradeKarmaChain';

/** Structural minimum settlement needs from TradeKarmaChain — keeps this file testable without viem clients. */
export interface EarningMinter {
  mintEarned(user: Address, amount: bigint, reasonHash: Hash): Promise<Hash>;
  /**
   * On-chain replay guard: true once `reasonHash` has been consumed by a
   * successful `mintEarned`. Checked before submitting so a retry after a
   * process restart (empty in-memory ledger, but the mint already landed
   * last time) can short-circuit instead of submitting a transaction that
   * is guaranteed to revert.
   */
  kruneSettled(reasonHash: Hash): Promise<boolean>;
}

export type SettlementStatus = 'pending' | 'confirmed' | 'failed';

export interface SettlementRecord {
  eventId: string;
  status: SettlementStatus;
  reasonHash: Hash;
  txHash?: Hash;
  attempts: number;
  lastError?: string;
}

/**
 * Deterministic, collision-resistant reasonHash for an earning event.
 * Binds the on-chain mint to its off-chain cause: event id (UUID), user,
 * type, amount, and timestamp. The UUID alone would already be unique, but
 * folding in the other fields means the hash is also a self-contained audit
 * record — a chain observer can confirm what was earned without a DB lookup.
 *
 * NOTE: assumes event.amountKRUNE is already an integer (src/logic/earning.ts
 * always Math.round()s before recording a Transaction).
 */
export function computeReasonHash(event: Transaction): Hash {
  return keccak256(
    encodePacked(
      ['string', 'string', 'string', 'uint256', 'uint256'],
      [
        event.id,
        event.userId,
        event.type,
        BigInt(Math.round(event.amountKRUNE)),
        BigInt(event.timestamp.getTime()),
      ]
    )
  );
}

/**
 * Tracks settlement status per off-chain event id so the same event is never
 * minted twice. In-memory (Phase 1 parity); swap for a DB-backed store
 * before this graduates past the bridge prototype.
 */
export class SettlementLedger {
  private records: Map<string, SettlementRecord> = new Map();

  get(eventId: string): SettlementRecord | undefined {
    return this.records.get(eventId);
  }

  isConfirmed(eventId: string): boolean {
    return this.records.get(eventId)?.status === 'confirmed';
  }

  /**
   * Settle one off-chain earning event by minting the equivalent KRUNE
   * on-chain. Idempotent per event.id within this process: a CONFIRMED event
   * returns the cached record without calling the chain again. A FAILED (or
   * never-attempted) event is (re)submitted — this is the retry path.
   *
   * Also idempotent ACROSS process restarts, via the on-chain `settled()`
   * guard: if the in-memory record was lost (restart) but the mint already
   * landed in a previous process, this checks `chain.kruneSettled(reasonHash)`
   * before submitting and short-circuits to a CONFIRMED record instead of
   * re-attempting a mint that would revert. This check-then-act is not
   * atomic — see the file header for the exact race this does and does not
   * close; the contract's own require is what actually prevents a double
   * mint, this is purely an optimisation to skip a doomed transaction.
   */
  async settle(chain: EarningMinter, event: Transaction, userAddress: Address): Promise<SettlementRecord> {
    const existing = this.records.get(event.id);
    if (existing?.status === 'confirmed') {
      return existing;
    }

    const reasonHash = computeReasonHash(event);

    const alreadySettledOnChain = await chain.kruneSettled(reasonHash);
    if (alreadySettledOnChain) {
      const confirmed: SettlementRecord = {
        eventId: event.id,
        status: 'confirmed',
        reasonHash,
        attempts: (existing?.attempts ?? 0) + 1,
      };
      this.records.set(event.id, confirmed);
      return confirmed;
    }

    const attempt: SettlementRecord = {
      eventId: event.id,
      status: 'pending',
      reasonHash,
      attempts: (existing?.attempts ?? 0) + 1,
    };
    this.records.set(event.id, attempt);

    try {
      const amount = toKarmaUnits(Math.round(event.amountKRUNE));
      const txHash = await chain.mintEarned(userAddress, amount, reasonHash);
      const confirmed: SettlementRecord = { ...attempt, status: 'confirmed', txHash };
      this.records.set(event.id, confirmed);
      return confirmed;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      const failed: SettlementRecord = { ...attempt, status: 'failed', lastError: message };
      this.records.set(event.id, failed);
      throw err;
    }
  }
}
