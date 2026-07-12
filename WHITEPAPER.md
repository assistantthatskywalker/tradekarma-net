# TradeKarma

### Earn Your Reputation, Never Buy It

**White Paper — v3 (canonical)**
**Basel, Switzerland · 2026**
**tradekarma.net**

---

## Abstract / Executive Summary

TradeKarma is a reputation economy for e-commerce that pays people for being good. Write an honest, detailed review and you earn a token. Ship an order on time and you earn a token. Answer another buyer's question and you earn a token. These tokens are not a loyalty-points gimmick — they are the foundation of a three-token economy in which earned reputation, invested capital, and real revenue-backed yield are kept in separate, deliberately-designed lanes.

The system rests on a single, non-negotiable rule: **you cannot buy reputation.** The reputation token, KarmaRune ($KRUNE), enters the economy only through participation. There is no purchase path — not off-chain, not on-chain. A whale can buy every investment token on the market and still be locked out of the yield, because the yield gate requires earned reputation they do not have and cannot acquire with money. This is the mechanic everything else is built on, and it is enforced in code, not in prose.

We are building deliberately and in the correct order. Phase 1 runs the entire economy on a plain database — no wallets, no gas, no "connect your wallet." We prove that positive reinforcement actually changes behavior on a real marketplace before a single token touches a blockchain. Only when the model is proven do we migrate to ERC-20 tokens on Base, Coinbase's Ethereum Layer 2, using Coinbase Smart Wallet so ordinary users never see a seed phrase. We don't launch tokens to find out if the model works. **We prove the model works, then launch tokens.**

This document is the definitive specification of the TradeKarma economy: the three tokens and their jobs, the exact earning and staking mathematics as implemented in the codebase, the anti-whale gate, the tokenomics, the phased rollout, governance, the treasury, the tamper-evident audit archive, and our Swiss/FINMA-aware legal posture. Where an earlier draft and the code disagreed, the code won and this paper reflects it.

---

## The Problem

You can buy 500 five-star reviews on Amazon for a few hundred dollars. A buyer who spends 45 minutes writing a detailed, photo-backed, genuinely useful review gets nothing for it. Maybe a "verified purchase" badge. Maybe not even that.

This has been true for more than a decade, and nobody has fixed it, because the incentives are broken at a structural level. There is no cost to faking a review and no reward for writing a real one. The entire economics of online trust run backwards.

It gets worse. A vendor who spends ten years building an excellent reputation on one platform starts again from zero on the next. Reputation is locked inside whatever silo you happened to build it in. There is no portable, verifiable proof that you are trustworthy. Switch platforms and you are a stranger again — and strangers get gamed.

The standard industry response is punishment. Platforms hunt bad actors, ban them, and purge their reviews. This produces an arms race: sellers optimize to evade detection rather than to be genuinely good. The whole system is adversarial by design, and everyone can feel it.

We want to try the opposite. Instead of building a better punishment machine, build a reward machine. Make the honest review worth something real. Turn the reliable vendor's reputation into an asset they actually own and can carry with them. Positive reinforcement has been studied since the 1960s, and the research is consistent: rewarding the behavior you want produces more durable change than punishing the behavior you don't. TradeKarma applies that finding to commerce.

---

## Solution Overview

TradeKarma is, first and last, a functioning marketplace. Strip away all three tokens and there is still a place where people buy and sell things, leave reviews, and resolve disputes. The token economy is a layer on top of a viable business — never the other way around. That ordering is the safety mechanism behind every design decision in this paper.

Three principles shape everything:

**Reputation is earned, never bought.** KarmaRune is the one rule we will not compromise. If reputation can be purchased, the whole system collapses into pay-to-win with extra steps. Every mechanic downstream is designed around this constraint.

**Yield comes from revenue, or it does not come at all.** The treasury that backs the yield token is funded by transaction fees and vendor subscriptions — actual money that actual people paid for actual services. If the marketplace does not generate revenue, the yield pool is empty and no yield is generated. We would rather show an honest "yield is not available yet" than a fabricated APY funded by the next investor buying in. We all watched what happened to the projects that did the latter.

**Prove first, tokenize second.** We start with a plain points system on a database. If positive reinforcement does not measurably improve review quality and marketplace health when it is just numbers in Postgres, no blockchain will save it. Only a proven model earns the right to become tokens.

The architecture is layered so the same core logic serves both worlds. A provider-agnostic API sits above the earning and staking logic; the logic sits above the data models; and in Phase 2 the database models are swapped for on-chain contracts behind the identical interface. In Phase 1 the reference implementation is TypeScript in strict mode with a full test suite covering every load-bearing invariant — the anti-whale rejection, tamper detection, and diminishing-returns earning each have a test that fails if the rule breaks.

---

## The Three Tokens

Most token projects use one token for everything: currency, reward, governance vote, and investment vehicle all at once. These jobs conflict. People hoard a "utility" token hoping it appreciates, which breaks its utility; speculation on the reward token distorts the behavior it was supposed to encourage. TradeKarma splits the functions into three tokens that never blur into one another.

| Token | Ticker | Job | How you get it | Supply |
|-------|--------|-----|----------------|--------|
| **KarmaRune** | $KRUNE | Reputation. Proof you participated and contributed. | **Earned only** — reviews, helpful answers, referrals, on-time shipping. **Never purchasable.** | Minted as earned; sinks via spending |
| **KarmaDex** | $KDEX | Investment + governance. The token you buy if you believe in the project. | Bought on a DEX (Uniswap on Base). | **Fixed supply**, minted once |
| **KarmaShard** | $KSHRD | Yield. What you get when earned reputation meets invested capital. | Generated by **staking KRUNE + KDEX together.** Redeem for USDC or KDEX. | Accrues from staking; backed by treasury |

### KarmaRune ($KRUNE) — reputation, earned only

KRUNE is your track record. It accumulates as you do good things on the platform and it can **never be bought.** This is enforced structurally, not by policy. Off-chain there is no endpoint that accepts money in exchange for KRUNE. On-chain, `KarmaRune.sol` is an ERC-20 with **no payable function anywhere** and no public mint. Tokens can be created only by a designated `MINTER` — the earning engine — through a single `mintEarned` function, and every mint carries a `reasonHash` linking it back to the specific off-chain earning event (the review, the shipment, the referral) for auditability. There is no back door, because there is no door at all. You spend KRUNE on platform perks (discounts, visibility boosts) or you save it to stake.

### KarmaDex ($KDEX) — investment and governance, fixed supply

KDEX is what investors interact with. It has a **fixed supply**, minted exactly once at contract construction and distributed; `KarmaDex.sol` declares `totalSupply` as `immutable` and exposes no mint function, so no more can ever be created. It trades freely on a DEX — Uniswap on Base — and it carries governance voting power. Because it is deliberately walled off from the reputation layer, speculation on KDEX price cannot leak into and distort the behavioral incentives that drive KRUNE. If TradeKarma grows, demand for the fixed KDEX supply grows; that is the honest investment thesis, and it is kept structurally separate from the act of earning reputation.

### KarmaShard ($KSHRD) — yield, from both halves together

KSHRD is the bridge between the two, and it exists only where earned reputation and invested capital meet. To generate it, you lock your earned KRUNE **alongside** purchased KDEX in the staking contract. You need both. A hedge fund that buys millions of dollars of KDEX but has never used the platform cannot stake — it has no KRUNE. A power user with a huge KRUNE balance but no financial skin in the game cannot stake either — it has no KDEX. KSHRD accrues over time on the *geometric mean* of the two staked amounts, and it is redeemable from the treasury for USDC, or for KDEX with a **+10% keepback bonus** that keeps value inside the system. The details of both the accrual and the redemption follow below.

---

## Earning Mechanics

The earning engine is live in the codebase (`src/logic/earning.ts`) and its behavior is exact and testable. The specific coefficients will be tuned during Phase 1 against real data, but the *structure* is fixed, and it is built to make honest participation cheaper than farming.

### The diminishing-returns base curve

Every review starts from a logarithmic base reward that shrinks as you repeat the same action. The formula, verbatim from the code, is:

```
base(n) = 10 / log2(n + 2)
```

where `n` is how many reviews you have already written. Your first review earns a base of **10** KRUNE. Your second earns about **6.3**. Your fiftieth earns about **1.8**. The curve is deliberately concave: the Nth action always earns less than the one before it. This is the core anti-farming device. Grinding out volume gets you steadily diminishing rewards, so you cannot buy reputation with sheer repetition any more than you can buy it with a credit card.

### Quality multipliers (capped at 5×)

Base reward is only the starting point. What you actually receive depends on what you put into the review. The quality multiplier stacks three factors and is then hard-capped:

| Signal | Effect |
|--------|--------|
| Includes photos | × 2 |
| Substantial text (over 200 characters) | × 1.5 |
| Detailed / specific (usage context, comparisons) | × 1.3 |
| **Maximum combined multiplier** | **× 5 (hard cap)** |

A throwaway "great product, fast shipping" review earns its small base and nothing more. A detailed review with photos and real usage context can earn several times as much — but never more than five times the base, no matter how many signals it hits. Quality scoring is AI-assisted but transparent: the criteria are public, and a user can see why their review received the multiplier it did.

### First-review premium (3×)

Every marketplace has the same gap: popular products drown in reviews while niche products have none, leaving the buyer of the niche product with nothing to go on. TradeKarma fixes this with a coverage bonus. The **first** review on a product earns a **3× multiplier**; once a product already has reviews, subsequent reviews earn the standard 1×. This pushes KRUNE toward the corners of the marketplace that need coverage most, and the incentive self-balances — as coverage fills in, the premium naturally moves to the next underserved product.

### How a review reward is computed

The three factors combine multiplicatively and the result is rounded:

```
reward = round( base(n) × qualityMultiplier × firstReviewBonus )
```

A first-ever review on a product, written with photos and detail by a new reviewer, might compute as `10 × (up to 5) × 3` before rounding — the strongest possible signal the system recognizes. A twentieth generic one-liner on a saturated product computes to a low single-digit number. The math rewards exactly the behavior we want: substantive, first-hand, coverage-expanding contributions.

### Other earning actions

The engine rewards more than reviews:

- **Helpful answers.** Answering another buyer's question earns a flat **+5 KRUNE**, recorded as a retroactive-help event.
- **Referrals.** A successful referral earns **30 KRUNE** — and it only pays out once the referred user has stayed genuinely active for **90 days**, so sharing a link that goes nowhere earns nothing.
- **On-time shipping (vendors).** Vendors earn on fulfillment quality, scaled to order value at **0.1 KRUNE per $1, capped at 100 KRUNE** per order. On-time means shipped within **3 days**; a late shipment earns **half**. Vendors are rewarded for how well they run the shop, not for how much they sell.

Because the base curve diminishes, the quality multiplier is capped, and referrals require proof-of-realness, the cost of gaming the system with fake accounts stays high while the reward for honest participation stays accessible. That asymmetry — honest participation cheaper than farming — is the target the whole engine is tuned toward.

---

## Staking & Yield

Staking is where earned reputation and invested capital finally combine to produce revenue-backed yield. The logic is implemented in `src/logic/staking.ts` for Phase 1 and mirrored on-chain in `Staking.sol` for Phase 2.

### How a stake works

Suppose you have used TradeKarma for six months. You have written reviews, answered questions, and referred a few friends, and you have accumulated 500 KRUNE. You also believe in the project, so you bought 500 KDEX on Uniswap. You go to the staking page and lock **both** into the staking contract. From that moment your position begins accruing KarmaShard.

Both principals are locked for **90 days**. When the lock matures you can redeem the accrued KSHRD (for USDC or KDEX, covered under Treasury & Redemption) and recover your original KRUNE and KDEX. If you exit **early**, before the 90-day lock matures, you **forfeit the accrued yield** but recover your full KRUNE and KDEX principal — the penalty is the lost yield, never the principal.

### The geometric-mean yield curve

Yield does not accrue on the sum of your tokens or on either token alone. It accrues on the **geometric mean** of the two staked amounts:

```
dailyYield = sqrt(KRUNE_staked × KDEX_staked) × rate
```

The reference rate is calibrated to roughly **1% annualized** on that geometric mean (the on-chain `Staking.sol` encodes it as a per-second constant; the exact rate is a governed parameter tuned to treasury capacity). On-chain the same `sqrt(krune × kdex)` drives accrual per second between updates.

The geometric mean is the mathematical heart of the anti-whale design, and it is worth seeing why. Consider three stakers:

- **Balanced participant:** 500 KRUNE, 500 KDEX → √(250,000) = **500** units of productive stake.
- **All money, little reputation:** 20 KRUNE, 500 KDEX → √(10,000) = **100**.
- **All reputation, little money:** 500 KRUNE, 20 KDEX → √(10,000) = **100**.

The geometric mean is symmetric and it punishes imbalance. Piling on capital without earning matching reputation barely moves your yield, and vice versa. The function is maximized only when both halves grow together — precisely the profile of a committed, honest, long-term participant. And in the limiting case that matters most: **if either amount is zero, the geometric mean is zero.** No KRUNE means no yield, mathematically, even before the gate stops you.

---

## The Anti-Whale Mechanic

This is the mechanic everything else is built on, so it gets its own section.

**A whale with $10 million of KDEX and zero earned KRUNE cannot stake, cannot generate KSHRD, and cannot touch the yield.** Full stop. They can buy every KDEX on the open market; it does not matter. Yield requires *both halves*, and the reputation half cannot be bought at any price.

This is enforced twice over. First, the **anti-whale gate** is an explicit check that runs before any stake is opened. In `staking.ts`, `checkAntiWhalGate` returns a hard refusal if the user's KRUNE balance is zero — *"No earned reputation (KRUNE). You must participate first."* — and an equally hard refusal if their KDEX balance is zero — *"No investment tokens (KDEX). You must believe in the project."* On-chain, `Staking.sol` enforces the same rule with two `require` statements at the top of the `stake` function:

```solidity
require(kruneAmount > 0, "STAKE: need earned KRUNE (reputation)");
require(kdexAmount > 0, "STAKE: need invested KDEX (capital)");
```

A transaction that tries to stake with zero KRUNE simply reverts. Second, even if the gate were somehow bypassed, the **geometric-mean yield curve** makes the attack pointless: √(0 × millions) = 0. Zero reputation yields zero KSHRD by construction.

The reverse is equally true and equally deliberate. A user who has earned 50,000 KRUNE over years of helpful participation but refuses to put up any capital cannot stake either — they have no KDEX. The system does not privilege money over labor or labor over money. It requires both, together, every time. That symmetry is the whole point: yield is the reward for *aligned* commitment, capital that stands behind reputation and reputation that has skin in the game.

The consequence is that the most dangerous actor in most token economies — the whale who buys their way to the top of the yield stack — is structurally disarmed here. They can invest. They can hold. They can vote with their KDEX. But they cannot extract yield without doing the one thing money cannot do for them: earning a reputation, action by honest action, over time.

---

## Tokenomics & Supply / Distribution

The three tokens have three different supply models, matched to their three jobs.

| Token | Supply model | Created by | Reduced by |
|-------|--------------|------------|------------|
| $KRUNE | Elastic, earned-only | `mintEarned` (earning engine only) | Spending on perks; staking lock-up |
| $KDEX | **Fixed**, minted once | Genesis mint at construction | (Optional DAO-governed fee burns) |
| $KSHRD | Accrues from staking; treasury-backed | Geometric-mean yield accrual | Redemption against treasury |

**KRUNE** has no fixed cap because it is a measure of cumulative good behavior, not a scarce investment. It expands as the community participates and contracts as members spend it on discounts, visibility, and other perks, and as it is locked away in staking. Its value is not speculative; it is a credential.

**KDEX** is the fixed-supply investment token. The reference deployment mints **100,000,000 KDEX** once, to the treasury, for structured distribution. An illustrative distribution — subject to legal review and final board approval before any launch — allocates the fixed supply across the constituencies that build and sustain the network:

| Allocation | Share | Purpose |
|------------|-------|---------|
| Community & ecosystem rewards | 40% | Long-term incentives for participants and vendors |
| Team (multi-year vesting) | 20% | Founders and core contributors, vested over time |
| Treasury / reserve | 15% | Runway, buybacks, contingency |
| Liquidity provision | 15% | DEX liquidity on Base (Uniswap) |
| Investor round | 10% | Small early raise to fund development and legal |

Because the supply is fixed and immutable, none of these allocations can be inflated after the fact. Team tokens vest over multiple years to align incentives with the long build.

**KSHRD** is not pre-minted. It comes into existence only as staked positions accrue it, and it is retired when redeemed against the treasury. Its outstanding quantity is therefore always tethered to real staking activity and real treasury backing — it cannot be conjured from nothing, which is the specific failure mode that destroyed earlier "high-APY" tokens.

Revenue that funds the economy comes from platform fees: transaction commissions on trades, vendor listing subscriptions, premium features, and (in later phases) protocol fees from external platforms that integrate TradeKarma reputation. Revenue is split across operations, the yield pool, KDEX buybacks, and reserves, with the **yield pool held at 0% until the platform crosses a minimum active-user threshold** — because a yield pool split among a handful of users is both economically meaningless and an invitation to gaming. Yield activates as a natural consequence of real economic activity, not before it.

---

## Phased Rollout

We are not launching three tokens at once. That would be reckless. Each phase has to earn the next.

### Phase 1 — Database points, no blockchain (now)

Phase 1 is a real e-commerce marketplace with a points system running entirely on a database. Users see and earn "Karma" for the behaviors we want to encourage and spend it on benefits. There are no wallets, no gas fees, and nothing to connect. From a crypto perspective it is intentionally boring — it looks like a loyalty program, and that is exactly right.

The purpose is to answer the only question that matters before tokenizing: **does positive reinforcement actually change behavior on a real marketplace?** Does review quality rise? Do vendors respond faster? Do people stay longer? Because everything is in a database, we can adjust earning rates and spending options in minutes and measure the result — iteration that becomes nearly impossible once economics are on-chain and gated behind governance votes and contract upgrades. The reference implementation for this phase already exists: the earning and staking logic, models, archive, and governance are implemented in TypeScript under strict typing with a full test suite. The motto of this phase is literal: **prove the model, then launch tokens.** If Phase 1 fails, we learned it cheaply and no token was ever issued.

### Phase 2 — Two tokens on-chain (Base)

When the model is proven, KRUNE migrates from the database to an **ERC-20 on Base**, Coinbase's Ethereum Layer 2. Users receive a **Coinbase Smart Wallet** tied to their email — **no seed phrases** to write down and lose — and their accumulated points convert to on-chain KRUNE. The migration is a milestone worth marketing: *your reputation is now yours, portable, and on-chain.* Transactions on Base cost roughly a cent, and Swiss users can fund a wallet through Coinbase with a bank transfer, so the crypto machinery stays invisible to people who never wanted to think about it.

KDEX launches alongside, with its fixed supply distributed as above and liquidity on Uniswap (Base). In this phase the two tokens coexist but do not yet mechanically interact — both simply accumulate while the marketplace generates revenue into a multi-signature treasury and we watch whether on-chain KRUNE behaves like the off-chain points did and whether organic KDEX demand appears.

### Phase 3 — Yield and the open protocol

Phase 3 turns on KSHRD generation. Staking goes live, users pair earned KRUNE with purchased KDEX, and the treasury begins paying real, revenue-backed yield. This is gated hard: yield activates only when the platform has enough active users generating consistent fee revenue that the pool is meaningful and not merely a gaming target. In this phase governance progressively hands parameters to the DAO, and the long-term protocol vision comes into view — an open reputation layer that other marketplaces can integrate, so that reputation earned in one place is recognized in another.

```
Phase 1                  Phase 2                   Phase 3
Karma points             KRUNE on-chain (Base)     KSHRD yield active
(database, no crypto)    KDEX launches (fixed)     Staking: KRUNE + KDEX
                         Treasury accumulates      DAO governs · open protocol

1 token (points)   -->   2 tokens (on-chain)  -->  3 tokens (full economy)
Prove behavior     -->   Prove investment     -->  Prove yield
```

Each phase justifies the next. If points do not change behavior, there is no blockchain. If the marketplace does not generate revenue, there is no yield. The tokens earn their existence.

---

## Governance & the DAO

Governance runs on KDEX, and it is intentionally kept separate from the reputation layer. In the reference implementation (`src/dao/Governance.ts`), voting weight is **1 KDEX = 1 vote**. Proposals have a defined voting window and a **quorum** — a minimum total KDEX weight that must participate for the result to count — and pass by **simple majority** of the votes cast. One address votes once per proposal.

Notably, **KRUNE does not vote.** This is a deliberate design choice, and it reverses what earlier drafts assumed: governance is a capital-and-belief function, so it is denominated in the capital-and-belief token, while reputation is kept purely as the behavioral currency and the yield key. Blending them would drag reputation-farming incentives into governance and governance-capture incentives into reputation. Keeping them apart protects both.

The DAO is *earned*, the same way KRUNE is. A three-person founding team cannot govern by committee, and a DAO of a few hundred early users would be governance theater. So the platform starts centralized and hands over control progressively as the community demonstrates it can hold it. Early on, token holders vote on parameters like earning rates, vendor categories, and feature priorities, while the founder retains authority over contract upgrades, treasury withdrawals, and terms of service. Over time, authority migrates to a DAO timelock and an elected council handles day-to-day execution.

Full handover is gated by strict conditions: multiple years of stable operation, zero critical security incidents, a demonstrated track record of the DAO governing well, a treasury that has covered expenses for six or more consecutive months, and a community supermajority vote (75%+) approving the transition. We do not hand over the keys until the system has proven it can run without us.

---

## Treasury & Redemption

The treasury is what makes the yield real. It holds USDC and KDEX funded by actual platform fees, and it is the counterparty that backs every KSHRD redemption. In production it is a multi-signature wallet; the reference `Treasury.sol` collects fees via `depositFees` and pays out redemptions only when called by the authorized staking flow.

When a matured stake is redeemed, the holder chooses one of two paths:

| Path | What you receive |
|------|------------------|
| **KSHRD → USDC** | Baseline **1 KSHRD ≈ 1 USDC**, paid from the treasury's USDC reserve to your wallet. |
| **KSHRD → KDEX** | KDEX equal to your KSHRD value **plus a +10% keepback bonus** (`KDEX_KEEPBACK_BONUS_BPS = 1000`), paid from the treasury's KDEX reserve. |

The USDC path is the straightforward cash-out. The KDEX path exists to solve a structural problem: if USDC were the only exit, every redemption would drain the treasury and value would leak out of the system through a one-way valve. So redeeming as KDEX pays a **10% bonus** — you receive more value for choosing to keep it inside the ecosystem, and the KDEX you receive can be re-staked or held. The bonus is a deliberate incentive to recirculate value rather than extract it, and as a side effect it puts steady, organic demand behind KDEX.

Redemption is always bounded by what the treasury actually holds. The contract will not pay USDC it does not have, nor KDEX it does not have; every payout `require`s sufficient balance. This is the guardrail that prevents the "print money from nothing" failure mode. If revenue falls, the yield pool stops filling, new KSHRD stops generating, and outstanding KSHRD retains whatever treasury backing remains — the system degrades gracefully to a reputation-only economy in which KRUNE and the marketplace still work. The yield can never promise more than the business earned.

---

## Security & the Immutable Archive

Trust in a reputation system depends on the reputation record being tamper-proof. TradeKarma's answer is **hash259**, a versioned, content-addressed, tamper-evident, role-gated audit archive implemented in `src/archive/`.

**What hash259 is.** The name is TradeKarma's internal label for the scheme: SHA-256 (32 bytes / 256 bits) plus a one-byte version tag — 259 addressing bits — giving a forward-compatible envelope (`hash259-v1`). The scheme is **one-way by construction** (you cannot recover content from a digest) and **read-only by construction** (the archive stores digests and links; it exposes no way to mutate a sealed record).

**How tamper-evidence works.** Every transaction is written to an append-only log and **hash-linked** to the one before it: each record's hash is computed over its own contents concatenated with the previous record's hash. This chains the entire history together. Change any single earlier record — alter an amount, backdate a timestamp, delete a review — and its hash changes, which breaks the link every later record depends on, cascading a mismatch through the rest of the chain. The archive's `verify()` walks the chain from genesis and returns false the moment a `prevHash` or a recomputed hash fails to match. There is no way to quietly rewrite history; any edit is detectable.

**Role-gated reads.** Access is controlled by role. **SYSTEM** and **ADMIN** have full access; an **AUDITOR** has read-only access to the entire archive (so an external reviewer can verify integrity without any ability to alter it); a **USER** can read only their own transactions. Every access attempt is written to a separate audit log that only SYSTEM and ADMIN can read. The archive also serializes to a compact binary format for backup, headed by its version tag.

**On-chain and contract security.** In Phase 2, the same guarantees are inherited from Base, which settles to Ethereum. The contracts are minimal and auditable: KRUNE has no payable path and mints only via an authorized minter; KDEX has an immutable fixed supply and no mint function; the staking contract enforces the anti-whale gate with `require` statements and returns principals only after the lock; the treasury pays out only what it holds and only to the authorized staking flow. Beyond the code, our security posture includes a tier-1 audit before mainnet, a bug bounty from day one, a multi-signature treasury (3-of-5 signers), circuit breakers for emergencies, no admin mint function, and fully open-source, verified contracts. The load-bearing invariants — earned-only KRUNE, the anti-whale gate, diminishing returns, and tamper-evidence — each have a test that fails if the rule is broken.

---

## Legal & Regulatory

TradeKarma originates in **Basel, Switzerland**, and operates within the Swiss regulatory framework under **FINMA**, the Swiss Financial Market Supervisory Authority. Switzerland offers one of the clearer token-classification regimes in the world — but "clearer" still means we obtain a formal legal opinion on every token classification before we issue anything.

Our token designs map onto FINMA's categories deliberately. **KRUNE** is designed as a pure utility token: it grants access to platform features, it is only ever earned through usage, and there is no ICO and no token sale. Because our points-first approach means the economy is already live and functional when KRUNE tokenizes, the "utility must be usable at issuance" expectation is satisfied by construction. **KDEX** is an investment-and-governance token subject to anti-money-laundering rules and requiring careful legal review of how it is offered and traded. **KSHRD** is the complicated one: redeeming it for USDC from a treasury can resemble a banking function, which several advisors have flagged as potentially requiring a banking license. This is precisely why KSHRD does not activate without explicit legal clearance, and why the KDEX redemption path (a token-to-token conversion, a different regulatory posture) is built in as the structurally cleaner default. If clearance is not obtained, the fallback is simple and already designed for: keep two tokens and pay qualifying stakers directly, dropping KSHRD as a separate instrument — the anti-whale mechanic works either way.

We budget CHF 30,000–50,000 for legal opinions across all phases and treat legal sign-off as a **blocking dependency**: no token is issued without the lawyer's approval, even if the technology is ready. Vendors undergo KYC; buyers get lighter phone-and-email verification with optional KYC to unlock higher earning limits.

---

## Risks & Mitigations

We would rather name the risks than bury them.

**Sybil attacks and fake-account farming.** The existential threat. If someone can spin up 100 fake accounts and farm KRUNE, the earned-reputation gate is meaningless. Mitigations stack: vendor KYC is mandatory; KRUNE only comes from reviewing verified purchases above a minimum value; the diminishing-returns curve makes each additional action worth less; the quality multiplier is capped and AI-scored so low-effort spam earns almost nothing; new accounts earn at reduced rates; referrals only pay after 90 days of proven activity; graph analysis flags circular trading and mutual-review rings; and high-reputation users can serve as a community jury for edge cases. No system is gaming-proof — the goal is to make honest participation cheaper than fraud, and every mechanic is tuned toward that asymmetry.

**Smart-contract exploits.** The economics are secondary to security; a flawless token model on a hacked contract is worthless. Mitigations: minimal auditable contracts, a tier-1 audit before mainnet, a bug bounty from day one, a 3-of-5 multi-sig treasury, circuit breakers, no admin mint, and progressive rather than reckless decentralization.

**Yield inflation / unbacked yield.** The failure mode that destroyed the "high-APY" projects. Mitigation is structural: yield is funded only by real revenue, the pool sits at 0% below a minimum user threshold, redemption is bounded by actual treasury holdings, and KSHRD cannot be minted from nothing.

**Insufficient adoption.** If the marketplace never generates enough activity, yield never becomes meaningful. Mitigation: the phased model means we never over-invest ahead of proof — Phase 1 is cheap, and if behavior does not change, we stop before tokenizing. The base case is a functioning marketplace that stands on its own without any token.

**Regulatory reclassification.** A token could be classified more strictly than expected — especially KSHRD. Mitigation: legal sign-off is a blocking dependency, the KDEX redemption path reduces banking-function exposure, and the two-token fallback is fully designed and ready.

**Whale capture of governance.** Because governance is KDEX-weighted, a large holder could accumulate influence. Mitigation: quorum requirements, progressive and conditional decentralization, and the deliberate separation of governance (KDEX) from the yield key (which still requires earned KRUNE no whale can buy).

---

## Roadmap

These are targets, not promises. If a phase takes longer to prove, it takes longer — rushing a deadline is how projects ship insecure contracts.

| Timeframe | Milestone |
|-----------|-----------|
| Months 1–3 | Legal entity, FINMA consultation, hire blockchain developer, design marketplace architecture |
| Months 4–6 | Marketplace live: listings, checkout, fiat payments; KRUNE points system running on database |
| Months 7–9 | First vendors onboarded, first real transactions, anti-gaming v1 deployed |
| Months 10–12 | Cross the active-user threshold; analyze KRUNE engagement data; make the tokenization decision |
| Months 13–18 | **Phase 2:** KRUNE migrates on-chain (Base), KDEX launches, Coinbase Smart Wallet, contracts audited |
| Months 19–24 | DAO governance v1, treasury accumulating, marketplace scaling |
| Months 25–36 | Multi-category expansion, vendor growth, sustained fee revenue |
| Months 37–42 | **Phase 3:** KSHRD staking and yield go live (if legal and economic conditions are met); first redemptions |
| Months 43–48 | Reputation protocol / SDK opened; first external platform integration |
| Months 49–60 | Full DAO governance; contract ownership progressively renounced; protocol self-sustaining |

---

## Conclusion

TradeKarma is a bet that the internet's trust economy is broken because its incentives are backwards, and that the fix is to reward good behavior rather than merely punish bad behavior. The three tokens encode that bet precisely: **KarmaRune** is reputation you can only earn and never buy; **KarmaDex** is a fixed-supply investment and governance token you buy on a DEX; and **KarmaShard** is revenue-backed yield that exists only where earned reputation and invested capital are staked together.

The anti-whale gate is the keystone. A whale with millions in KDEX and zero KRUNE cannot stake, cannot generate yield, and cannot buy their way past it — the reputation half is not for sale at any price, and the geometric-mean curve makes zero reputation mathematically worth zero yield. That single constraint, enforced in the code and not just the prose, is what keeps this a reward system for genuine participation rather than another pay-to-win token.

And we are building it in the right order. Database first, prove the model, then launch tokens on Base with wallets ordinary people can actually use. Yield that comes from real revenue or does not come at all. A tamper-evident archive so the record can be trusted. A Swiss, FINMA-aware legal posture that treats legal sign-off as a hard gate. Reputation is not a badge you buy or a number a platform can quietly rewrite. It is something you earn, action by honest action — and with TradeKarma, it is finally something you own.

**Earn Your Reputation, Never Buy It.**

---

### Disclaimer — Not Financial Advice / Forward-Looking Statements

This white paper is a design and planning document. It is **not financial advice**, not a prospectus, not an offer or solicitation to buy or sell any token or security, and not a promise of any return. It contains **forward-looking statements** — roadmap dates, economic projections, token designs, and mechanics — that involve assumptions, risks, and uncertainties; actual outcomes may differ materially. All numeric parameters (earning coefficients, yield rates, supply and distribution figures, thresholds) are illustrative and subject to change based on Phase 1 data, legal review, and community governance. No tokens have been issued, and no investment is being offered. Token designs described here may change or be withdrawn. Digital assets are volatile and may lose all value. **Review by qualified Swiss legal counsel is required before any token issuance**, and nothing herein should be relied upon as legal, tax, or financial advice. Consult your own professional advisors before making any decision.

---

*TradeKarma · Basel, Switzerland · 2026 · tradekarma.net*
