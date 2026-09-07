import { generateKeyPairSync } from 'node:crypto';
/**
 * Sprint 3: Archive + hash259 Tests — tamper-evidence & access control.
 */

import { TransactionArchive, AccessRole } from '../archive/Archive';
import { hash259, encodeDigest, decodeDigest, verify, link, HASH259_VERSION } from '../archive/hash259';

describe('hash259', () => {
  it('produces a versioned sha256 digest', () => {
    const d = hash259('hello');
    expect(d.version).toBe(HASH259_VERSION);
    expect(d.algo).toBe('sha256');
    expect(d.hex).toHaveLength(64);
  });

  it('is deterministic', () => {
    expect(hash259('x').hex).toBe(hash259('x').hex);
  });

  it('encode/decode round-trips', () => {
    const d = hash259('abc');
    const s = encodeDigest(d);
    const back = decodeDigest(s);
    expect(back.hex).toBe(d.hex);
  });

  it('rejects malformed digest strings', () => {
    expect(() => decodeDigest('nonsense')).toThrow();
  });

  it('verify passes for correct content, fails for tampered', () => {
    const d = hash259('payload');
    expect(verify('payload', d)).toBe(true);
    expect(verify('payload!', d)).toBe(false);
  });

  it('link changes when prior content changes (chain sensitivity)', () => {
    const a = link('genesis', 'tx1');
    const b = link(a, 'tx2');
    const aTampered = link('genesis', 'tx1-tampered');
    const bTampered = link(aTampered, 'tx2');
    expect(b).not.toBe(bTampered);
  });
});

describe('TransactionArchive', () => {
  it('verifies an untampered chain', () => {
    const arc = new TransactionArchive();
    for (let i = 0; i < 100; i++) {
      arc.append(`tx-${i}`, `user-${i % 5}`, 'review', i, new Date(2026, 0, 1, 0, 0, i));
    }
    expect(arc.verify()).toBe(true);
  });

  it('detects tampering: modifying a record breaks verification', () => {
    const arc = new TransactionArchive();
    for (let i = 0; i < 10; i++) {
      arc.append(`tx-${i}`, 'user-1', 'review', i, new Date(2026, 0, 1, 0, 0, i));
    }
    // Tamper with an internal record's amount directly.
    (arc as any).transactions[5].amount = 999999;
    expect(arc.verify()).toBe(false);
  });

  describe('access control', () => {
    let arc: TransactionArchive;
    beforeEach(() => {
      arc = new TransactionArchive();
      arc.append('t1', 'alice', 'review', 10, new Date());
      arc.append('t2', 'bob', 'review', 20, new Date());
    });

    it('USER can read only own transactions', () => {
      const rows = arc.getTransactions('alice', AccessRole.USER);
      expect(rows.every((r) => r.userId === 'alice')).toBe(true);
      expect(rows.find((r) => r.userId === 'bob')).toBeUndefined();
    });

    it('AUDITOR can read all transactions (read-only)', () => {
      const rows = arc.getTransactions('auditor-1', AccessRole.AUDITOR);
      expect(rows.length).toBe(2);
    });

    it('ADMIN/SYSTEM can read all', () => {
      expect(arc.getTransactions('sys', AccessRole.SYSTEM).length).toBe(2);
      expect(arc.getTransactions('adm', AccessRole.ADMIN).length).toBe(2);
    });

    it('USER cannot read the audit log; ADMIN can', () => {
      arc.logAccess('alice', AccessRole.USER, 'read', true);
      expect(arc.getAuditLog(AccessRole.USER).length).toBe(0);
      expect(arc.getAuditLog(AccessRole.ADMIN).length).toBeGreaterThan(0);
    });
  });

  it('serializes to a binary buffer with the version header', () => {
    const arc = new TransactionArchive();
    arc.append('t1', 'alice', 'review', 10, new Date());
    const buf = arc.serialize();
    expect(buf.length).toBeGreaterThan(0);
    expect(JSON.parse(buf.toString()).version).toBe(HASH259_VERSION);
    const restored = TransactionArchive.deserialize(buf, arc.checkpoint());
    expect(restored.verify()).toBe(true);
    expect(restored.getTransactions('alice', AccessRole.USER)[0].timestamp).toEqual(arc.getTransactions('alice', AccessRole.USER)[0].timestamp);
  });
});

it('delimiter ambiguity, mutable reads and invalid digests no longer bypass integrity', () => {
  const a = new TransactionArchive(), b = new TransactionArchive();
  expect(a.append('a|b', 'c', 'review', 1, new Date(0))).not.toBe(b.append('a', 'b|c', 'review', 1, new Date(0)));
  a.getTransactions('admin', AccessRole.ADMIN)[0].amount = 999;
  expect(a.getTransactions('admin', AccessRole.ADMIN)[0].amount).toBe(1);
  expect(verify('x', { version: HASH259_VERSION, algo: 'sha256', hex: 'z'.repeat(64) })).toBe(false);
  expect(() => decodeDigest('wrong:sha256:' + 'a'.repeat(64))).toThrow();
});
it('independently retained signed checkpoints detect changed or truncated backups', () => {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const arc = new TransactionArchive(); arc.append('one', 'a', 'review', 1, new Date(0));
  const signed = arc.signCheckpoint(privateKey);
  expect(arc.verifySignedCheckpoint(signed.checkpoint, signed.signature, publicKey)).toBe(true);
  const empty = new TransactionArchive();
  expect(empty.verifySignedCheckpoint(signed.checkpoint, signed.signature, publicKey)).toBe(false);
  const data = JSON.parse(arc.serialize().toString()); data.transactions[0].amount = 2;
  expect(() => TransactionArchive.deserialize(Buffer.from(JSON.stringify(data)))).toThrow();
});
