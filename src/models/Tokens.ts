/** Local reference simulation. Whole reputation/capital units; rewards are integer USDC base units. */
import { randomUUID } from 'node:crypto';
import { Balance, BalanceLedger, assertAmount } from './Ledger';
export type KarmaDexBalance = Balance;
export class KarmaDexLedger extends BalanceLedger {}
export interface KarmaShard {
  id: string;
  userId: string;
  kruneStaked: number;
  kdexStaked: number;
  stakedAt: Date;
  matureAt: Date;
  weight: bigint;
  paid: bigint;
  accruedUsdc: bigint;
}
export function integerSqrt(n: bigint): bigint {
  if (n < 0n) throw new Error('negative root');
  if (n < 2n) return n;
  let x = n, y = (x + 1n) / 2n;
  while (y < x) { x = y; y = (x + n / x) / 2n; }
  return x;
}
const SCALE = 10n ** 18n;
export class KarmaShardVault {
  private positions = new Map<string, KarmaShard>();
  private accumulator = 0n;
  private weight = 0n;
  private carry = 0n;
  private reserve = 0n;
  /** Test/reference cash ledger, never an assertion that a real payment occurred. */
  readonly usdcBalances = new BalanceLedger();
  get stakes(): Map<string, KarmaShard> {
    return new Map([...this.positions].map(([id, p]) => [id, structuredClone(p)]));
  }
  getByUser(userId: string): KarmaShard[] {
    return [...this.stakes.values()].filter(p => p.userId === userId);
  }
  create(userId: string, kruneAmount: number, kdexAmount: number, lockDays = 90): KarmaShard {
    assertAmount(kruneAmount, true); assertAmount(kdexAmount, true);
    if (lockDays !== 90) throw new Error('lock is 90 days');
    let p = [...this.positions.values()].find(p => p.userId === userId);
    const krune = (p?.kruneStaked ?? 0) + kruneAmount;
    const kdex = (p?.kdexStaked ?? 0) + kdexAmount;
    assertAmount(krune); assertAmount(kdex);
    if (p) this.settle(p);
    else p = { id: randomUUID(), userId, kruneStaked: 0, kdexStaked: 0, weight: 0n,
      paid: this.accumulator, accruedUsdc: 0n, stakedAt: new Date(), matureAt: new Date() };
    const weight = integerSqrt(BigInt(krune) * SCALE) * integerSqrt(BigInt(kdex) * SCALE);
    this.weight += weight - p.weight;
    Object.assign(p, { kruneStaked: krune, kdexStaked: kdex, weight, stakedAt: new Date(),
      matureAt: new Date(Date.now() + 90 * 86400_000) });
    this.positions.set(p.id, p);
    return structuredClone(p);
  }
  private settle(p: KarmaShard): void {
    p.accruedUsdc += p.weight * (this.accumulator - p.paid) / SCALE;
    p.paid = this.accumulator;
  }
  /** Mirrors the current Solidity carry policy, including allocation to the next active pool. */
  depositFees(payer: string, usdcUnits: number): void {
    assertAmount(usdcUnits);
    if (!this.usdcBalances.subtract(payer, usdcUnits)) throw new Error('insufficient fee funds');
    this.reserve += BigInt(usdcUnits);
    const pool = this.carry + BigInt(usdcUnits);
    const delta = this.weight ? pool * SCALE / this.weight : 0n;
    const allocated = this.weight ? (delta * this.weight + SCALE - 1n) / SCALE : 0n;
    this.accumulator += delta;
    this.carry = pool - allocated;
  }
  pendingUsdc(id: string): bigint {
    const p = this.positions.get(id);
    return p ? p.accruedUsdc + p.weight * (this.accumulator - p.paid) / SCALE : 0n;
  }
  redeem(id: string): bigint {
    const p = this.positions.get(id);
    if (!p || Date.now() < p.matureAt.getTime()) throw new Error('stake missing or locked');
    const reward = this.pendingUsdc(id);
    if (reward > this.reserve) throw new Error('reward reserve shortfall');
    const nextBalance = this.usdcBalances.get(p.userId) + Number(reward);
    assertAmount(nextBalance);
    this.usdcBalances.set(p.userId, nextBalance);
    this.reserve -= reward;
    this.weight -= p.weight;
    this.positions.delete(id);
    return reward;
  }
}
