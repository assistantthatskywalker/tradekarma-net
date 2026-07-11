/**
 * KRUNE Earning Mechanics
 * Logarithmic rewards, quality multipliers, retroactive helpfulness bonuses.
 */

import { User } from '../models/User';
import { Transaction, TransactionType, TransactionLog } from '../models/Transaction';
import { v4 as uuidv4 } from 'uuid';

export interface EarningContext {
  userId: string;
  transactionLog: TransactionLog;
  user: User;
}

/**
 * Logarithmic earning curve.
 * Nth action earns less than first, but quality & detail multiply.
 */
export function logarithmicBase(actionCount: number): number {
  if (actionCount === 0) return 10; // First action base
  return 10 * Math.log(actionCount + 1) / Math.log(2); // log2 scaling
}

/**
 * Quality multiplier for reviews.
 * Detailed reviews (photos, text) earn 3–5x more.
 */
export function qualityMultiplier(
  hasPhotos: boolean,
  textLength: number,
  isDetailed: boolean
): number {
  let multiplier = 1.0;
  if (hasPhotos) multiplier *= 2;
  if (textLength > 200) multiplier *= 1.5;
  if (isDetailed) multiplier *= 1.3;
  return Math.min(multiplier, 5.0); // Cap at 5x
}

/**
 * First review on a product earns 3x bonus.
 */
export function firstReviewBonus(
  transactionLog: TransactionLog,
  productId: string
): number {
  const existingReviews = Array.from(transactionLog.transactions.values()).filter(
    (tx) =>
      tx.type === TransactionType.REVIEW &&
      tx.metadata?.productId === productId
  );
  return existingReviews.length === 0 ? 3.0 : 1.0;
}

/**
 * Award KRUNE for a review.
 * Base (10 points) × log multiplier × quality multiplier × first-review bonus.
 */
export function awardReview(
  context: EarningContext,
  productId: string,
  orderValue: number,
  hasPhotos: boolean,
  textLength: number,
  isDetailed: boolean
): Transaction {
  const actionCount = context.transactionLog
    .getByUser(context.userId)
    .filter((tx) => tx.type === TransactionType.REVIEW).length;

  const baseAmount = logarithmicBase(actionCount);
  const quality = qualityMultiplier(hasPhotos, textLength, isDetailed);
  const firstBonus = firstReviewBonus(context.transactionLog, productId);

  const amount = Math.round(baseAmount * quality * firstBonus);

  const tx: Transaction = {
    id: uuidv4(),
    userId: context.userId,
    type: TransactionType.REVIEW,
    amountKRUNE: amount,
    multiplier: quality * firstBonus,
    metadata: {
      productId,
      orderValue,
      hasPhotos,
      textLength,
      isDetailed,
    },
    timestamp: new Date(),
  };

  context.transactionLog.record(tx);
  context.user.addKRUNE(amount, tx.id);

  return tx;
}

/**
 * Award KRUNE for helping other buyers retroactively.
 * A helpful answer to a buyer question earns +5 KRUNE.
 */
export function awardHelpfulness(
  context: EarningContext,
  questionId: string,
  answerText: string
): Transaction {
  const amount = 5; // Fixed amount for helpful answers

  const tx: Transaction = {
    id: uuidv4(),
    userId: context.userId,
    type: TransactionType.HELP,
    amountKRUNE: amount,
    multiplier: 1.0,
    metadata: {
      questionId,
      answerText,
    },
    timestamp: new Date(),
    isRetroactive: true,
  };

  context.transactionLog.record(tx);
  context.user.addKRUNE(amount, tx.id);

  return tx;
}

/**
 * Award KRUNE for successful referral.
 * Referred user must remain active for 90 days.
 */
export function awardReferral(
  context: EarningContext,
  referredUserId: string
): Transaction {
  const amount = 30; // Fixed amount for successful referral

  const tx: Transaction = {
    id: uuidv4(),
    userId: context.userId,
    type: TransactionType.REFERRAL,
    amountKRUNE: amount,
    multiplier: 1.0,
    metadata: {
      referredUserId,
    },
    timestamp: new Date(),
  };

  context.transactionLog.record(tx);
  context.user.addKRUNE(amount, tx.id);

  return tx;
}

/**
 * Award KRUNE for on-time shipment.
 * Amount scales with order value (0.1 KRUNE per $1, capped at 100).
 */
export function awardShipment(
  context: EarningContext,
  orderId: string,
  orderValue: number,
  daysToShip: number
): Transaction {
  const isOnTime = daysToShip <= 3; // On-time = ship within 3 days
  const baseAmount = Math.min(Math.round(orderValue * 0.1), 100);
  const amount = isOnTime ? baseAmount : Math.round(baseAmount * 0.5); // Half if late

  const tx: Transaction = {
    id: uuidv4(),
    userId: context.userId,
    type: TransactionType.SHIP,
    amountKRUNE: amount,
    multiplier: isOnTime ? 1.0 : 0.5,
    metadata: {
      orderId,
      orderValue,
      daysToShip,
      isOnTime,
    },
    timestamp: new Date(),
  };

  context.transactionLog.record(tx);
  context.user.addKRUNE(amount, tx.id);

  return tx;
}
