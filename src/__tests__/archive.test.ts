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
    expect(buf.toString('utf-8', 0, 10)).toBe('hash259-v1');
  });
});
