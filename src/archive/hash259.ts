/**
 * hash259 — versioned content-addressed hashing for the file archive.
 *
 * "hash259" is TradeKarma's internal label for its hashing scheme: SHA-256
 * (32 bytes / 256 bits) plus a 1-byte version tag = 259-ish addressing, giving
 * us a forward-compatible envelope. The scheme is one-way (you cannot recover
 * content from a digest) and read-only by construction: the archive stores
 * digests and links, never a way to mutate a sealed record.
 */

import * as crypto from 'crypto';

export const HASH259_VERSION = 'hash259-v1';

export interface Hash259Digest {
  version: string; // e.g. "hash259-v1"
  algo: 'sha256';
  hex: string; // 64 hex chars
}

/** Compute a versioned digest of arbitrary content. */
export function hash259(content: string | Buffer): Hash259Digest {
  const hex = crypto.createHash('sha256').update(content).digest('hex');
  return { version: HASH259_VERSION, algo: 'sha256', hex };
}

/** Encode a digest as a compact string: "hash259-v1:sha256:<hex>". */
export function encodeDigest(d: Hash259Digest): string {
  return `${d.version}:${d.algo}:${d.hex}`;
}

/** Parse a compact digest string back into a structured digest. */
export function decodeDigest(s: string): Hash259Digest {
  const parts = s.split(':');
  if (parts.length !== 3 || parts[1] !== 'sha256' || parts[2].length !== 64) {
    throw new Error(`hash259: malformed digest "${s}"`);
  }
  return { version: parts[0], algo: 'sha256', hex: parts[2] };
}

/** Verify content against an expected digest (constant-time compare). */
export function verify(content: string | Buffer, expected: Hash259Digest): boolean {
  const actual = hash259(content);
  if (actual.hex.length !== expected.hex.length) return false;
  return crypto.timingSafeEqual(
    Buffer.from(actual.hex, 'hex'),
    Buffer.from(expected.hex, 'hex')
  );
}

/**
 * Chain two digests: link(prev, current) — used to build the tamper-evident
 * append-only log. Changing any earlier record changes every later link.
 */
export function link(prevHex: string, content: string | Buffer): string {
  const data = Buffer.concat([
    Buffer.from(prevHex, 'utf-8'),
    Buffer.from('|', 'utf-8'),
    typeof content === 'string' ? Buffer.from(content, 'utf-8') : content,
  ]);
  return crypto.createHash('sha256').update(data).digest('hex');
}
