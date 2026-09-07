/** Legacy project name; standard SHA-256 with an explicit version, not a new hash algorithm. */
import * as crypto from 'node:crypto';
export const HASH259_VERSION = 'hash259-v2';
export interface Hash259Digest { version: string; algo: 'sha256'; hex: string }
const valid = (d: Hash259Digest): boolean => d?.version === HASH259_VERSION && d.algo === 'sha256' && /^[0-9a-f]{64}$/.test(d.hex);
export function hash259(content: string | Buffer): Hash259Digest {
  return { version: HASH259_VERSION, algo: 'sha256', hex: crypto.createHash('sha256').update(content).digest('hex') };
}
export function encodeDigest(d: Hash259Digest): string {
  if (!valid(d)) throw new Error('invalid versioned digest');
  return `${d.version}:${d.algo}:${d.hex}`;
}
export function decodeDigest(s: string): Hash259Digest {
  const parts = s.split(':');
  const d = { version: parts[0], algo: parts[1], hex: parts[2] } as Hash259Digest;
  if (parts.length !== 3 || !valid(d)) throw new Error('malformed or unsupported digest');
  return d;
}
export function verify(content: string | Buffer, expected: Hash259Digest): boolean {
  return valid(expected) && crypto.timingSafeEqual(Buffer.from(hash259(content).hex, 'hex'), Buffer.from(expected.hex, 'hex'));
}
export function link(prevHex: string, content: string | Buffer): string {
  if (prevHex !== 'genesis' && !/^[0-9a-f]{64}$/.test(prevHex)) throw new Error('invalid previous hash');
  // Length-prefixed, domain-separated binary fields. Field boundaries are never ambiguous.
  const parts = [Buffer.from('tradekarma:archive:v2'), Buffer.from(prevHex), Buffer.isBuffer(content) ? content : Buffer.from(content)];
  return hash259(Buffer.concat(parts.flatMap(p => { const length = Buffer.alloc(4); length.writeUInt32BE(p.length); return [length, p]; }))).hex;
}
