import { types } from 'node:util';
/** Reward calculation for trusted, verified commerce events. No network adapter is implicit. */
import { User } from '../models/User';
import { Transaction, TransactionType, TransactionLog } from '../models/Transaction';
import { assertAmount } from '../models/Ledger';

export interface VerifiedEarningEvent {
  id: string;
  userId: string;
  type: TransactionType;
  subjectId: string;
  verifiedAt: Date;
  orderValue?: number;
  hasPhotos?: boolean;
  textLength?: number;
  isDetailed?: boolean;
  answerText?: string;
  daysToShip?: number;
  /** Referral evidence must come from activity records, not account age alone. */
  activeSince?: Date;
  activeThrough?: Date;
}

/** Trusted ingestion only. Do not expose register() to agents or public request payloads. */
export class VerifiedEventStore {
  private events = new Map<string, VerifiedEarningEvent>();
  register(event: VerifiedEarningEvent): void {
    if (!event.id || this.events.has(event.id)) throw new Error('duplicate or missing evidence id');
    this.events.set(event.id, structuredClone(event));
  }
  get(id: string): VerifiedEarningEvent | undefined {
    const event = this.events.get(id);
    return event && structuredClone(event);
  }
}

export interface EarningContext {
  userId: string;
  transactionLog: TransactionLog;
  user: User;
  evidence?: VerifiedEarningEvent;
  now?: Date;
}

export function logarithmicBase(actionCount: number): number {
  assertAmount(actionCount);
  return 10 / Math.log2(actionCount + 2);
}
export function qualityMultiplier(hasPhotos: boolean, textLength: number, isDetailed: boolean): number {
  assertAmount(textLength);
  return Math.min((hasPhotos ? 2 : 1) * (textLength > 200 ? 1.5 : 1) * (isDetailed ? 1.3 : 1), 5);
}
export function firstReviewBonus(log: TransactionLog, productId: string): number {
  return log.getByType(TransactionType.REVIEW).some(tx => tx.metadata.productId === productId) ? 1 : 3;
}

function evidence(ctx: EarningContext, type: TransactionType, subjectId: string): VerifiedEarningEvent {
  const e = ctx.evidence;
  const now = (ctx.now ?? new Date()).getTime();
  if (ctx.user.profile.id !== ctx.userId || !subjectId || !e || !e.id || e.userId !== ctx.userId ||
      e.type !== type || e.subjectId !== subjectId || !types.isDate(e.verifiedAt) ||
      !Number.isFinite(e.verifiedAt.getTime()) || e.verifiedAt.getTime() > now) {
    throw new Error('trusted verified earning evidence required');
  }
  if (ctx.transactionLog.verify(e.id)) throw new Error('earning event already awarded');
  if (ctx.transactionLog.getByType(type).some(tx =>
    tx.metadata.subjectId === subjectId && (type === TransactionType.REFERRAL || type === TransactionType.SHIP || tx.userId === ctx.userId))) {
    throw new Error('subject already rewarded');
  }
  return e;
}
function record(ctx: EarningContext, e: VerifiedEarningEvent, amount: number, multiplier: number, metadata: Record<string, unknown>): Transaction {
  assertAmount(amount);
  assertAmount(ctx.user.getReputation() + amount);
  assertAmount(ctx.user.reputation.earned + amount);
  if (ctx.user.reputation.transactions.includes(e.id)) throw new Error('duplicate reputation event');
  const tx: Transaction = { id: e.id, userId: ctx.userId, type: e.type, amountKRUNE: amount, multiplier,
    metadata: { ...metadata, subjectId: e.subjectId }, timestamp: new Date(e.verifiedAt),
    isRetroactive: e.type === TransactionType.HELP };
  ctx.transactionLog.record(tx);
  ctx.user.addKRUNE(amount, tx.id);
  return tx;
}
export function awardReview(ctx: EarningContext, productId: string, orderValue: number, hasPhotos: boolean, textLength: number, isDetailed: boolean): Transaction {
  const e = evidence(ctx, TransactionType.REVIEW, productId);
  if (!Number.isFinite(orderValue) || orderValue <= 0 || e.orderValue !== orderValue || e.hasPhotos !== hasPhotos ||
      e.textLength !== textLength || e.isDetailed !== isDetailed) throw new Error('review facts differ from verified purchase evidence');
  const count = ctx.transactionLog.getByUser(ctx.userId).filter(t => t.type === TransactionType.REVIEW).length;
  const multiplier = qualityMultiplier(hasPhotos, textLength, isDetailed) * firstReviewBonus(ctx.transactionLog, productId);
  return record(ctx, e, Math.round(logarithmicBase(count) * multiplier), multiplier, { productId, orderValue, hasPhotos, textLength, isDetailed });
}
export function awardHelpfulness(ctx: EarningContext, questionId: string, answerText: string): Transaction {
  const e = evidence(ctx, TransactionType.HELP, questionId);
  if (!answerText.trim() || e.answerText !== answerText) throw new Error('verified helpful answer required');
  return record(ctx, e, 5, 1, { questionId, answerText });
}
export function awardReferral(ctx: EarningContext, referredUserId: string): Transaction {
  const e = evidence(ctx, TransactionType.REFERRAL, referredUserId);
  const since = e.activeSince?.getTime();
  const through = e.activeThrough?.getTime();
  if (referredUserId === ctx.userId || since === undefined || through === undefined ||
      !Number.isFinite(since) || !Number.isFinite(through) || through > e.verifiedAt.getTime() ||
      through - since < 90 * 86400_000) throw new Error('referral requires 90 days of verified activity and a different user');
  return record(ctx, e, 30, 1, { referredUserId });
}
export function awardShipment(ctx: EarningContext, orderId: string, orderValue: number, daysToShip: number): Transaction {
  const e = evidence(ctx, TransactionType.SHIP, orderId);
  if (!Number.isFinite(orderValue) || orderValue <= 0 || !Number.isFinite(daysToShip) || daysToShip < 0 ||
      e.orderValue !== orderValue || e.daysToShip !== daysToShip) throw new Error('verified shipment facts required');
  const multiplier = daysToShip <= 3 ? 1 : 0.5;
  return record(ctx, e, Math.round(Math.min(Math.round(orderValue * .1), 100) * multiplier), multiplier, { orderId, orderValue, daysToShip });
}
