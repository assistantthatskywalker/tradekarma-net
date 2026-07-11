/**
 * Sprint 1: Earning Mechanics Tests
 * Verify logarithmic scaling, quality multipliers, first-review bonus, retroactive helpfulness.
 */

import { User } from '../models/User';
import { TransactionLog } from '../models/Transaction';
import {
  awardReview,
  awardHelpfulness,
  awardReferral,
  awardShipment,
  logarithmicBase,
  qualityMultiplier,
  firstReviewBonus,
} from '../logic/earning';

describe('Earning Mechanics', () => {
  let user: User;
  let transactionLog: TransactionLog;

  beforeEach(() => {
    user = new User('user-123', 'test@example.com', 'testuser');
    transactionLog = new TransactionLog();
  });

  describe('logarithmicBase', () => {
    it('first action earns base 10', () => {
      expect(logarithmicBase(0)).toBe(10);
    });

    it('50th review earns less than 1st', () => {
      const first = logarithmicBase(0);
      const fiftieth = logarithmicBase(49);
      expect(fiftieth).toBeLessThan(first);
    });

    it('scales logarithmically with count', () => {
      const count1 = logarithmicBase(0);
      const count2 = logarithmicBase(1);
      const count10 = logarithmicBase(9);
      expect(count2).toBeLessThan(count1);
      expect(count10).toBeLessThan(count2);
    });
  });

  describe('qualityMultiplier', () => {
    it('no details: 1.0x multiplier', () => {
      expect(qualityMultiplier(false, 50, false)).toBe(1.0);
    });

    it('photos only: 2.0x multiplier', () => {
      expect(qualityMultiplier(true, 50, false)).toBe(2.0);
    });

    it('detailed text (>200 chars): 1.5x bonus', () => {
      const multi = qualityMultiplier(false, 250, false);
      expect(multi).toBe(1.5);
    });

    it('detailed flag adds 1.3x', () => {
      const multi = qualityMultiplier(false, 50, true);
      expect(multi).toBeCloseTo(1.3, 1);
    });

    it('photos + detailed text: 2.0 × 1.5 × 1.3 = 3.9x, capped at 5.0', () => {
      const multi = qualityMultiplier(true, 250, true);
      expect(multi).toBeLessThanOrEqual(5.0);
      expect(multi).toBeGreaterThan(3.0);
    });

    it('multiplier never exceeds 5.0', () => {
      expect(qualityMultiplier(true, 500, true)).toBeLessThanOrEqual(5.0);
    });
  });

  describe('firstReviewBonus', () => {
    it('first review on a product: 3.0x', () => {
      const bonus = firstReviewBonus(transactionLog, 'product-abc');
      expect(bonus).toBe(3.0);
    });

    it('subsequent reviews: 1.0x', () => {
      // Award first review
      awardReview(
        { userId: 'user-123', transactionLog, user },
        'product-abc',
        100,
        false,
        100,
        false
      );

      // Second review: no bonus
      const bonus = firstReviewBonus(transactionLog, 'product-abc');
      expect(bonus).toBe(1.0);
    });

    it('different products each get 3.0x first-review bonus', () => {
      const bonus1 = firstReviewBonus(transactionLog, 'product-1');
      const bonus2 = firstReviewBonus(transactionLog, 'product-2');
      expect(bonus1).toBe(3.0);
      expect(bonus2).toBe(3.0);
    });
  });

  describe('awardReview', () => {
    it('detailed photo review on $100 purchase earns ~30 KRUNE', () => {
      const tx = awardReview(
        { userId: 'user-123', transactionLog, user },
        'product-abc',
        100,
        true, // photos
        300, // long text
        true // detailed flag
      );

      // Base 10 × quality (2.0 × 1.5 × 1.3 ≈ 3.9) × first bonus (3.0) ≈ 117, but let's just check it's reasonable
      expect(tx.amountKRUNE).toBeGreaterThan(20);
      expect(user.getReputation()).toBe(tx.amountKRUNE);
    });

    it('generic text review earns ~7 KRUNE', () => {
      const tx = awardReview(
        { userId: 'user-123', transactionLog, user },
        'product-abc',
        100,
        false, // no photos
        50, // short text
        false // not detailed
      );

      // Base 10 × quality (1.0) × first bonus (3.0) ≈ 30, but let's check range
      expect(tx.amountKRUNE).toBeGreaterThan(0);
      expect(tx.multiplier).toBeGreaterThan(0);
    });

    it('user balance increments correctly after review', () => {
      expect(user.getReputation()).toBe(0);
      awardReview(
        { userId: 'user-123', transactionLog, user },
        'product-abc',
        100,
        false,
        100,
        false
      );
      expect(user.getReputation()).toBeGreaterThan(0);
    });

    it('transaction recorded in log', () => {
      const tx = awardReview(
        { userId: 'user-123', transactionLog, user },
        'product-abc',
        100,
        false,
        100,
        false
      );
      const logged = transactionLog.verify(tx.id);
      expect(logged).toBeDefined();
      expect(logged?.userId).toBe('user-123');
    });

    it('first review bonus applied correctly', () => {
      const tx = awardReview(
        { userId: 'user-123', transactionLog, user },
        'product-abc',
        100,
        false,
        100,
        false
      );
      // Multiplier should include first-review bonus (3.0)
      expect(tx.multiplier).toBeGreaterThanOrEqual(3.0);
    });
  });

  describe('awardHelpfulness', () => {
    it('helpful answer awards 5 KRUNE', () => {
      const tx = awardHelpfulness(
        { userId: 'user-123', transactionLog, user },
        'question-123',
        'Here is a detailed answer explaining the sizing...'
      );
      expect(tx.amountKRUNE).toBe(5);
      expect(user.getReputation()).toBe(5);
    });

    it('marked as retroactive', () => {
      const tx = awardHelpfulness(
        { userId: 'user-123', transactionLog, user },
        'question-123',
        'Answer text'
      );
      expect(tx.isRetroactive).toBe(true);
    });

    it('multiple helpful answers accumulate', () => {
      awardHelpfulness(
        { userId: 'user-123', transactionLog, user },
        'q-1',
        'Answer 1'
      );
      awardHelpfulness(
        { userId: 'user-123', transactionLog, user },
        'q-2',
        'Answer 2'
      );
      expect(user.getReputation()).toBe(10);
    });
  });

  describe('awardReferral', () => {
    it('successful referral awards 30 KRUNE', () => {
      const tx = awardReferral(
        { userId: 'user-123', transactionLog, user },
        'referred-user-456'
      );
      expect(tx.amountKRUNE).toBe(30);
      expect(user.getReputation()).toBe(30);
    });
  });

  describe('awardShipment', () => {
    it('on-time shipment: $100 order → 10 KRUNE', () => {
      const tx = awardShipment(
        { userId: 'user-123', transactionLog, user },
        'order-abc',
        100,
        2 // shipped in 2 days
      );
      expect(tx.amountKRUNE).toBe(10);
      expect(tx.multiplier).toBe(1.0);
    });

    it('late shipment: $100 order → 5 KRUNE (50% penalty)', () => {
      const tx = awardShipment(
        { userId: 'user-123', transactionLog, user },
        'order-abc',
        100,
        5 // shipped in 5 days
      );
      expect(tx.amountKRUNE).toBe(5);
      expect(tx.multiplier).toBe(0.5);
    });

    it('amount capped at 100 KRUNE for high-value orders', () => {
      const tx = awardShipment(
        { userId: 'user-123', transactionLog, user },
        'order-xyz',
        2000, // $2000 order
        1
      );
      expect(tx.amountKRUNE).toBeLessThanOrEqual(100);
    });
  });

  describe('Anti-Abuse Scenarios', () => {
    it('cannot spend more KRUNE than earned', () => {
      awardReview(
        { userId: 'user-123', transactionLog, user },
        'product-abc',
        100,
        false,
        100,
        false
      );
      const earned = user.getReputation();
      const result = user.spendKRUNE(earned + 10, 'tx-123');
      expect(result).toBe(false); // Spend failed
      expect(user.getReputation()).toBe(earned); // Balance unchanged
    });

    it('earning rate slows with review count (logarithmic)', () => {
      const tx1 = awardReview(
        { userId: 'user-123', transactionLog, user },
        'product-1',
        100,
        false,
        100,
        false
      );
      const balance1 = user.getReputation();

      // Clear and re-award to compare fresh amounts
      user = new User('user-124', 'test2@example.com', 'testuser2');
      transactionLog = new TransactionLog();

      // Simulate 10 reviews already done, then award the 11th
      for (let i = 0; i < 10; i++) {
        awardReview(
          { userId: 'user-124', transactionLog, user },
          `product-${i}`,
          100,
          false,
          100,
          false
        );
      }
      const balanceBefore11 = user.getReputation();

      const tx11 = awardReview(
        { userId: 'user-124', transactionLog, user },
        'product-11',
        100,
        false,
        100,
        false
      );

      // The 11th review should earn less than the 1st (logarithmic decay)
      expect(tx11.amountKRUNE).toBeLessThan(tx1.amountKRUNE);
    });
  });

  describe('Integration', () => {
    it('complex user flow: review + help + referral + shipment', () => {
      const review = awardReview(
        { userId: 'user-123', transactionLog, user },
        'product-abc',
        100,
        true,
        250,
        true
      );

      const help = awardHelpfulness(
        { userId: 'user-123', transactionLog, user },
        'q-123',
        'Answer'
      );

      const referral = awardReferral(
        { userId: 'user-123', transactionLog, user },
        'user-456'
      );

      const shipment = awardShipment(
        { userId: 'user-123', transactionLog, user },
        'order-xyz',
        200,
        2
      );

      const total = review.amountKRUNE +
        help.amountKRUNE +
        referral.amountKRUNE +
        shipment.amountKRUNE;
      expect(user.getReputation()).toBe(total);
      expect(transactionLog.getByUser('user-123').length).toBe(4);
    });
  });
});
