import { User } from '../models/User';
import { TransactionLog, TransactionType } from '../models/Transaction';
import { awardReview, awardReferral, awardHelpfulness, awardShipment, logarithmicBase, qualityMultiplier, EarningContext, VerifiedEarningEvent } from '../logic/earning';
function context(type = TransactionType.REVIEW, subjectId = 'product', overrides: Partial<VerifiedEarningEvent> = {}): EarningContext {
  return { userId: 'alice', user: new User('alice', 'a@example.invalid', 'a'), transactionLog: new TransactionLog(),
    evidence: { id: 'event1', userId: 'alice', type, subjectId, verifiedAt: new Date(1), orderValue: 100,
      hasPhotos: true, textLength: 250, isDetailed: true, ...overrides } };
}
const review = (ctx: EarningContext) => awardReview(ctx, ctx.evidence!.subjectId, 100, true, 250, true);
it('retains diminishing rewards and the documented quality formula', () => {
  expect(logarithmicBase(0)).toBe(10);
  expect(logarithmicBase(49)).toBeLessThan(logarithmicBase(1));
  expect(qualityMultiplier(true, 250, true)).toBeCloseTo(3.9);
  expect(review(context()).amountKRUNE).toBe(117);
});
it('requires verified evidence, not caller-supplied reward facts', () => {
  const ctx = context(); ctx.evidence = undefined;
  expect(() => awardReview(ctx, 'p', 100, true, 250, true)).toThrow(/evidence/);
  expect(() => awardReview(context(), 'product', 10000, true, 250, true)).toThrow(/facts/);
  expect(() => review(context(TransactionType.REVIEW, 'product', { userId: 'bob' }))).toThrow(/evidence/);
});
it('consumes event and subject once and preserves balances on replay', () => {
  const ctx = context(); review(ctx);
  expect(() => review(ctx)).toThrow(/already/);
  ctx.evidence!.id = 'new-id';
  expect(() => review(ctx)).toThrow(/already/);
  expect(ctx.user.getReputation()).toBe(117);
});
it('subsequent verified products receive lower rewards for the same user', () => {
  const ctx = context(); const first = review(ctx);
  ctx.evidence = { ...ctx.evidence!, id: 'event2', subjectId: 'product2' };
  expect(review(ctx).amountKRUNE).toBeLessThan(first.amountKRUNE);
});
it('referrals require actual verified activity spanning 90 days', () => {
  const ctx = context(TransactionType.REFERRAL, 'bob');
  expect(() => awardReferral(ctx, 'bob')).toThrow(/90 days/);
  ctx.evidence = { ...ctx.evidence!, activeSince: new Date(0), activeThrough: new Date(90 * 86400_000), verifiedAt: new Date(91 * 86400_000) };
  expect(awardReferral(ctx, 'bob').amountKRUNE).toBe(30);
  const self = context(TransactionType.REFERRAL, 'alice', { activeSince: new Date(0), activeThrough: new Date(90 * 86400_000), verifiedAt: new Date(91 * 86400_000) });
  expect(() => awardReferral(self, 'alice')).toThrow(/different user/);
});
it('requires verified useful answers and shipment facts', () => {
  const help = context(TransactionType.HELP, 'question', { answerText: 'Useful answer' });
  expect(awardHelpfulness(help, 'question', 'Useful answer').amountKRUNE).toBe(5);
  const ship = context(TransactionType.SHIP, 'order', { daysToShip: 2 });
  expect(awardShipment(ship, 'order', 100, 2).amountKRUNE).toBe(10);
  expect(() => awardShipment(context(TransactionType.SHIP, 'o', { daysToShip: -1 }), 'o', 100, -1)).toThrow();
});
it.each([-1, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1])('rejects corrupt ledger amounts: %s', amount => {
  const ctx = context();
  expect(() => ctx.user.addKRUNE(amount, 'bad')).toThrow();
  expect(() => ctx.user.spendKRUNE(amount, 'bad')).toThrow();
  expect(ctx.user.getReputation()).toBe(0);
});
it('returns detached transaction records', () => {
  const ctx = context(); const tx = review(ctx); tx.amountKRUNE = 999;
  const stored = ctx.transactionLog.verify(tx.id)!; stored.metadata.productId = 'changed';
  expect(ctx.transactionLog.verify(tx.id)!.amountKRUNE).toBe(117);
  expect(ctx.transactionLog.verify(tx.id)!.metadata.productId).toBe('product');
});
