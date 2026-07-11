# TradeKarma White Paper

**Version 1.0 — First Draft**
**March 2026**

**tradekarma.net**

---

## Abstract

TradeKarma is a reputation protocol for e-commerce. It introduces a token economy where good behavior — honest reviews, reliable shipping, responsive support — earns you something real. Not likes, not stars that disappear when you switch platforms. Tokens that unlock economic value.

The system uses three tokens, introduced in phases. You start with one: KarmaRune ($KRUNE), an off-chain points system that proves the behavioral economics work before anything touches a blockchain. Then you add the investment layer: KarmaDex ($KDEX), a freely tradeable token. Finally, you activate yield: KarmaShard ($KSHRD), generated only when earned reputation meets invested capital.

The core mechanic: you cannot buy your way to yield. You have to earn it.

Built in Basel, Switzerland. Designed for FINMA compliance. Points first, tokens later.

---

## Table of Contents

1. [The Problem](#1-the-problem)
2. [The TradeKarma Approach](#2-the-tradekarma-approach)
3. [Three Tokens, Three Functions](#3-three-tokens-three-functions)
4. [The Phased Rollout: 1 to 3 Tokens](#4-the-phased-rollout-1-to-3-tokens)
5. [How the Three-Token Economy Works](#5-how-the-three-token-economy-works)
6. [Revenue and the Real Yield Question](#6-revenue-and-the-real-yield-question)
7. [Anti-Gaming and Sybil Resistance](#7-anti-gaming-and-sybil-resistance)
8. [Technical Architecture](#8-technical-architecture)
9. [Governance](#9-governance)
10. [Legal and Regulatory](#10-legal-and-regulatory)
11. [Precedents and Lessons](#11-precedents-and-lessons)
12. [Roadmap](#12-roadmap)
13. [Team and Operations](#13-team-and-operations)
14. [Open Questions](#14-open-questions)
15. [Glossary](#15-glossary)

---

## 1. The Problem

E-commerce runs on trust, and the infrastructure for trust is broken.

Reviews are the backbone of online buying decisions. But review systems on every major platform — Amazon, Etsy, Shopify storefronts, vertical marketplaces — share the same structural flaw: there is no meaningful incentive to write honest, helpful reviews, and there is almost no cost to faking them.

A vendor can buy 500 five-star reviews for a few hundred dollars. A buyer who writes a detailed, honest review that helps dozens of other people gets nothing. Maybe a "Top Reviewer" badge. Maybe not even that.

The result is predictable. Fake reviews outnumber real ones in many categories. Buyers stop trusting reviews altogether. Vendors who do honest business have no way to prove it. Everyone loses except the review farms.

The deeper problem: **reputation is locked to individual platforms.** A vendor with 10 years of excellent reviews on Amazon starts from zero on Etsy. A buyer's review history on one platform means nothing on another. There is no portable proof of trustworthiness.

Current platforms respond to bad behavior with punishment — bans, delistings, review removal. This creates an adversarial relationship between the platform and its users. People optimize to avoid getting caught, not to be genuinely good.

TradeKarma inverts this. Instead of punishing bad behavior (which platforms already do poorly), we reward good behavior. We make reputation an economic asset that belongs to the user, not the platform.

---

## 2. The TradeKarma Approach

The idea is straightforward: what if your reputation on a marketplace was worth something real?

Not in the vague, hand-wavy "reputation is valuable" sense. In the concrete sense: you write an honest review, you earn a token. That token unlocks a discount, boosts your visibility, gives you a governance vote, or — eventually — generates yield when paired with investment capital.

The philosophical core is **positive reinforcement**. Behavioral science has studied token economies since the 1960s as systems for reinforcing desired behavior. They work. Blockchain makes the mechanism programmable, transparent, and portable across platforms.

Five principles guide the design:

**Earned, never bought.** The reputation token (KarmaRune) cannot be purchased. If you could buy reputation, the entire system collapses into pay-to-win. This is the single most important design decision and the single strongest differentiator from every other token project.

**Points first, tokens later.** We prove the behavioral economics work with an off-chain points system before we touch a blockchain. If the model does not drive measurable improvements in marketplace health with Web2 infrastructure, putting it on-chain will not fix that. This also buys time for legal clarity and lets us tune the earning algorithm based on real behavior data.

**Real yield from real revenue.** Any yield the system generates comes from actual platform fees — transaction commissions, listing fees, premium features. Not from new token buyers funding old token holders. If the revenue is not there, the yield is not activated. This is a hard rule.

**Swiss precision.** We are based in Basel and building within FINMA's regulatory framework. We move deliberately. Every token classification gets a legal opinion before issuance. We do not rush tokens to market because rushing creates rug-pulls.

**Progressive decentralization.** The platform starts centralized (faster iteration, clearer accountability) and moves toward DAO governance as the system matures and the community proves it can govern responsibly.

---

## 3. Three Tokens, Three Functions

Most token projects try to make one token do everything — pay for transactions, reward behavior, represent governance power, and attract investment. This creates conflicting incentives. People hoard a utility token for price appreciation instead of spending it. Speculators distort the economy that actual users depend on.

TradeKarma separates three distinct economic functions into three distinct tokens:

| Token | Ticker | Function | How You Get It |
|-------|--------|----------|----------------|
| **KarmaRune** | $KRUNE | Reputation and proof of participation | Earned only — through honest reviews, quality service, referrals, dispute resolution |
| **KarmaDex** | $KDEX | Investment and governance | Bought and sold on markets |
| **KarmaShard** | $KSHRD | Yield — the reward for combining reputation with capital | Generated by staking $KRUNE + $KDEX together |

Each token has a clear, non-overlapping purpose. Here is what that means in practice:

**KarmaRune ($KRUNE)** is your proof that you contributed to the marketplace. You write a helpful review, you get KRUNE. You ship on time with good packaging, you get KRUNE. You refer a buyer who stays active, you get KRUNE. Nobody can buy KRUNE on a DEX — it only enters circulation through positive actions scored by the platform.

**KarmaDex ($KDEX)** is the investment token. It has a fixed or controlled supply. It trades freely. If you believe TradeKarma will grow, you buy KDEX. It gives you governance votes on platform direction. It is the token investors and speculators interact with. It is deliberately separated from the reputation layer so that speculation does not distort the behavioral incentive system.

**KarmaShard ($KSHRD)** is where the two worlds meet. You generate KSHRD by staking your earned KRUNE alongside purchased KDEX. The requirement is simple: you need both. A whale who buys a million dollars of KDEX but has no KRUNE cannot stake. A power user who earned 100,000 KRUNE but has no KDEX cannot stake. You need earned reputation AND invested capital. This is the anti-whale mechanism, and it is the core innovation.

KSHRD is redeemable for stablecoin (USDC) from a treasury funded by platform fees. The yield is real because the revenue backing it is real.

---

## 4. The Phased Rollout: 1 to 3 Tokens

Launching all three tokens on day one would be a mistake. The board unanimously agreed on this. The economy has to be proven layer by layer.

### Phase 1: One Token — KarmaRune as Points (Months 1-12)

The first year is about proving the thesis with zero crypto complexity.

KarmaRune launches as an off-chain points system. No wallets, no gas fees, no seed phrases, no blockchain. Users see "Karma Points" in their account. They earn them by doing good things. They spend them on platform benefits — discounts, boosted listings, priority support, governance votes.

Everything runs on a standard database. The earning rates, spending sinks, and anti-gaming rules are tunable in real time. If the economics do not work, we adjust them in minutes, not in a smart contract upgrade that requires an audit.

**What this phase proves:**
- Do users change their behavior when positive actions earn tangible rewards?
- What is the natural earn/spend ratio?
- Which earning actions drive the most marketplace health improvement?
- What are the gaming vectors?
- Can the anti-gaming systems keep the economy honest?

**What triggers the next phase:** 500+ monthly active users, consistent engagement data over 3+ months, and a legal opinion from a Swiss crypto lawyer confirming the token classification.

This is the hardest phase psychologically. It looks like a loyalty points program, not a crypto project. That is intentional. A token that launches before the underlying economy is proven is a meme coin with extra steps.

### Phase 2: Two Tokens — KarmaRune On-Chain + KarmaDex (Months 6-18)

Once Phase 1 validates the behavioral model, KarmaRune migrates from database points to an ERC-20 token on Base (Coinbase's Ethereum L2). Users get real wallets. Their earned points convert to on-chain KRUNE. The migration event itself becomes a marketing moment — "your reputation is now yours, on-chain, portable."

Simultaneously, KarmaDex ($KDEX) launches as the investment and governance token. KDEX has a fixed supply. It is distributed through a combination of community allocation, team vesting, small investor rounds, and liquidity provision. KDEX trades freely on decentralized exchanges.

In this phase, the two tokens coexist but do not interact mechanically. KRUNE holders have governance power (1 KRUNE = 1 vote). KDEX holders also have governance power. The marketplace generates revenue through transaction fees, listing fees, and premium vendor features. Revenue accumulates in a multi-sig treasury.

**What this phase proves:**
- Does on-chain KRUNE behave the same as off-chain points?
- Is there organic demand for KDEX?
- Does the treasury grow from real revenue?
- Can the DAO governance system function?

**What triggers the next phase:** 1,000+ monthly active users, a treasury that has accumulated meaningful stablecoin reserves, and a clear legal opinion on the yield mechanism.

### Phase 3: Three Tokens — Yield Activation with KarmaShard (Month 12+)

This is where the three-token mechanic comes alive.

KarmaShard ($KSHRD) generation activates. Users who hold both earned KRUNE and purchased KDEX can stake them together in a staking contract. The staked position generates KSHRD over time. KSHRD is redeemable for USDC from the platform treasury.

The critical gate: **yield only activates when the treasury can sustain it.** The board's CFO modeled the numbers. At 100 active users, the yield pool pays roughly $23 per staker per month. Nobody cares about $23 per month — and activating yield at that level just creates a target for gaming. The board's consensus is that yield activation requires a minimum of 500-1,000 active users generating consistent revenue.

The phased rollout is not just a development timeline. It is a trust-building mechanism. Each phase proves that the next one is warranted. If Phase 1 fails to change user behavior, Phase 2 never happens. If Phase 2 does not generate real revenue, Phase 3 stays dormant. The tokens earn their way into existence.

```
Phase 1 (Year 1)         Phase 2 (Year 1-2)        Phase 3 (Year 2+)
─────────────────         ──────────────────         ─────────────────
Karma Points              $KRUNE on-chain            $KSHRD yield active
(off-chain, database)     $KDEX launches             Staking: KRUNE + KDEX
                          Treasury accumulates       Treasury pays real yield
                          DAO governance v1          DAO governance mature

1 token (points)     →    2 tokens (on-chain)   →   3 tokens (full economy)
Prove behavior       →    Prove investment       →   Prove yield
```

---

## 5. How the Three-Token Economy Works

### The Staking Mechanic

This is the part that matters. Here is the step-by-step:

1. **A user earns 500 KRUNE** over weeks or months of honest reviews, quality transactions, and community participation. This took real effort and time. KRUNE cannot be accelerated by spending money.

2. **The same user buys 500 KDEX** on a decentralized exchange. This costs real money. The user is making an investment decision.

3. **The user stakes both** into the staking contract. The contract requires a matching ratio — KRUNE and KDEX must be paired. (The exact ratio is discussed below.)

4. **The staked position generates KSHRD** over time. The generation rate depends on the total value locked, the KDEX market price, and the available treasury balance.

5. **The user redeems KSHRD for USDC** from the platform's revenue-funded treasury.

This is where the anti-whale property comes from. A whale can buy $10 million of KDEX. But without a proportional amount of earned KRUNE — which takes months of real platform participation — they cannot stake. The mechanism ties yield to reputation. You cannot buy your way past the gate.

### Token Flow Diagram

```
Positive Actions (reviews, support, referrals, quality trades)
    |
    v
$KRUNE (earned, never bought)
    |
    +---> SPEND on platform benefits (discounts, boosts, features)
    |     $KRUNE is burned
    |
    +---> LOCK in staking contract ──────┐
    |     (requires matching $KDEX)      |
    |                                    v
    |                              $KSHRD generated
    |                                    |
    |                              Redeem for USDC
    |                              from treasury
    |
    +---> BURN to mint $KSHRD directly
          (10,000 KRUNE = 1 KSHRD)
          $KRUNE destroyed permanently

$KDEX (bought on market)
    |
    +---> LOCK in staking contract (paired with KRUNE)
    |
    +---> GOVERNANCE (vote on platform parameters)
    |
    +---> TRADE freely on DEX
```

### The Ratio Question

The simplest approach is 1:1 — stake 500 KRUNE with 500 KDEX. Easy to explain, easy to understand.

The board's Critic raised a valid concern: when KDEX is cheap, users do minimal reputation work and unlock cheap staking. The incentive structure is off. When KDEX is expensive, the barrier to entry is too high for legitimate participants.

The recommended solution is a **dynamic ratio** that normalizes staking cost to a target dollar value:

```
Required KDEX = KRUNE amount x (Target Dollar Value / Current KDEX Price)
```

This means the real-money cost of staking remains roughly constant regardless of KDEX price. A user needs the same dollar-equivalent commitment whether KDEX is at $0.50 or $5.00. The earned KRUNE requirement stays constant — you always need the same amount of proof-of-participation.

### The KSHRD Burn Path

Beyond staking, there is a second way to create KSHRD: burning KRUNE permanently. The ratio is steep — 10,000 KRUNE to mint 1 KSHRD. This is intentional.

Burning creates a permanently deflationary pressure on KRUNE supply. Every KSHRD minted via burn represents thousands of positive actions that are now removed from circulation. It is "crystallized reputation" — the KRUNE that took months to earn is gone forever, converted into a scarce store of value.

The burn path exists for users who want long-term KSHRD exposure without the ongoing staking commitment. It also provides a natural sink for KRUNE that prevents inflation from spiraling.

### Supply Dynamics

| Token | Supply Type | What Creates It | What Destroys It |
|-------|------------|-----------------|------------------|
| $KRUNE | Inflationary | Minted when users perform positive actions | Burned when spent on platform features, burned when minting KSHRD, locked when staking |
| $KDEX | Fixed or controlled | Initial distribution; DAO can approve limited new issuance | Optional transaction fee burns (DAO-governed) |
| $KSHRD | Slow-growing, deflationary tendency | Minted through KRUNE staking or KRUNE burning | Burned on treasury redemption |

The system targets equilibrium where KRUNE minting (from positive actions) roughly equals KRUNE destruction (from spending, staking, and burning). If KRUNE inflates too fast, the earning rates are adjusted downward by governance. If KRUNE becomes too scarce, rates adjust upward.

---

## 6. Revenue and the Real Yield Question

This is the section that separates TradeKarma from every yield-farming scheme that collapsed in 2022-2023.

**The rule: KSHRD yield comes from platform revenue. Not from new investors. Not from token emissions. From fees that real people paid for real marketplace services.**

If that sounds boring compared to "10,000% APY," good. Projects that promise unsustainable yields attract capital that leaves the moment yield drops. Projects that deliver modest, real yields attract participants who actually use the platform.

### Revenue Sources

| Source | Mechanism | Rate |
|--------|-----------|------|
| Transaction fees | Commission on every trade | 1-3% of sale value |
| Vendor listing fees | Monthly subscription for vendors | CHF 29-199/month |
| Premium features | Analytics dashboards, boosted listings, verified badges | Variable |
| KDEX transaction tax | Small fee on every KDEX swap | 2-5% |
| KSHRD redemption fee | Fee when converting KSHRD to USDC | 5% |
| Protocol fees (Phase 3) | External platforms using the TradeKarma protocol | 2% of minted KRUNE + per-query fees |

### Revenue Allocation

Revenue is split into four pools, with the ratio shifting as the platform matures:

| Phase | Operations | Yield Pool | KDEX Buyback/Burn | Reserve |
|-------|-----------|-----------|-------------------|---------|
| 0-500 users | 70% | 0% (not active) | 10% | 20% |
| 500-2,000 users | 45% | 30% | 15% | 10% |
| 2,000+ users | 35% | 35% | 20% | 10% |

The yield pool is what backs KSHRD redemptions. When a user redeems KSHRD for USDC, the USDC comes from this pool. The pool balance is public and on-chain — anyone can verify how much backs the outstanding KSHRD supply.

### The Yield Reality Check

The board ran the numbers. Here is what yield looks like at different user levels:

| Active Users | Monthly Platform Revenue | Yield Pool (at maturity, 35%) | Per Staker / Month |
|-------------|------------------------|-------------------------------|-------------------|
| 100 | ~$1,400 | ~$500 | ~$20 |
| 500 | ~$6,900 | ~$2,400 | ~$19 |
| 1,000 | ~$13,800 | ~$4,800 | $19-28 |
| 10,000 | ~$137,500 | ~$48,000 | $19-38 |

At 100 users, yield is $20 per month per staker. That is not enough to attract anyone and barely enough to cover gas fees. This is why yield activation gates behind minimum user thresholds.

The yield is self-balancing. If KDEX price rises, more people want to stake. More stakers dilute the yield pool. Yield per person drops. Staking becomes less attractive. Some unstake. Pool concentrates again. Classic supply-demand equilibrium.

### What Happens If Revenue Drops?

KSHRD redemption is limited by the treasury balance. If the pool has $10,000 and 50,000 KSHRD are outstanding, each KSHRD redeems for $0.20. The system cannot pay out more than it has. This prevents the "print money from nothing" failure mode that killed Axie Infinity's SLP token.

If revenue drops to zero, no new KSHRD is generated (the yield pool is empty), existing KSHRD retains whatever treasury backing remains, and the system degrades gracefully to a reputation-only economy (KRUNE still works, the marketplace still functions). The token economy is a layer on top of a functional marketplace, not the other way around.

---

## 7. Anti-Gaming and Sybil Resistance

Every agent on the board flagged this as the make-or-break problem. If KRUNE can be farmed through fake accounts and wash trades, the anti-whale design collapses. A Sybil attacker creates 1,000 accounts, earns KRUNE through fake reviews on their own products, and suddenly the "earned reputation" requirement is worthless.

### Defense Layers

**Identity verification.** KYC for vendors (non-negotiable — you are selling products). For buyers, a lighter identity layer: phone number verification, email verification, and optional KYC for higher KRUNE earning limits. Integration with decentralized identity solutions (Gitcoin Passport, Worldcoin) as supplementary signals.

**Minimum transaction values.** KRUNE earning from reviews requires a verified purchase above a minimum value. You cannot earn KRUNE by buying a $0.01 item and reviewing it 500 times.

**Graph analysis.** Circular trading patterns, mutual review rings, and suspiciously correlated activity are detectable through social graph analysis. If accounts A, B, and C only transact with each other and always leave five-star reviews, that is a signal.

**Velocity limits.** Per-user KRUNE earning is capped per day and per week. Diminishing returns on repetitive actions. Cool-down periods between earning events. This limits the ROI of Sybil farming — even if you create 100 accounts, each one earns slowly.

**Review quality scoring.** AI-powered content analysis scores review authenticity. A one-sentence "great product!" earns minimal KRUNE. A detailed, specific review with photos earns significantly more. This raises the cost of farming because generating convincing fake reviews at scale is expensive.

**Progressive trust.** New accounts earn at reduced rates. Trust builds over time. Accounts with longer history and consistent positive behavior earn at full rates. This makes it expensive to repeatedly create and burn accounts.

**Community jury.** High-KRUNE users can review flagged cases. Decentralized human judgment for edge cases that automated systems cannot resolve.

**The honest assessment:** No anti-gaming system is perfect. Determined attackers with enough resources can game any reputation system. The goal is to make gaming more expensive than honest participation. If earning KRUNE honestly takes 1 hour and nets 50 KRUNE, gaming must take more than 1 hour per 50 KRUNE — otherwise honest participants are suckers.

---

## 8. Technical Architecture

### Blockchain: Base (Ethereum L2)

The board unanimously recommended Base for the following reasons:

- **Coinbase fiat on-ramp.** Swiss users can buy KDEX with a bank transfer through Coinbase. No seed-phrase-managing, no bridge-hopping. This matters for the non-crypto-native buyer persona.
- **Low fees.** ~$0.01 per transaction. KRUNE micro-rewards (earning 10 KRUNE for a review) are economically feasible.
- **Ethereum security.** Base is an optimistic rollup — it inherits Ethereum's security guarantees.
- **Smart Wallet.** Coinbase's Smart Wallet eliminates seed phrases. Users get a wallet tied to their email or biometric. The crypto part is invisible.
- **EVM compatibility.** Standard Solidity tooling. Large developer ecosystem. Easy to audit.

### Smart Contract Architecture

```
[TradeKarma Protocol Contracts — Base L2]

KarmaRune.sol        — ERC-20, mint/burn/transfer, earn-only minting via authorized callers
KarmaDex.sol         — ERC-20, fixed supply, standard transfer
KarmaShardVault.sol  — Staking contract: lock KRUNE + KDEX, mint KSHRD over time
KarmaShardBurn.sol   — Burn 10,000 KRUNE to mint 1 KSHRD
Treasury.sol         — Multi-sig, fee collection, KSHRD redemption
Governance.sol       — Snapshot-based voting, timelock execution
ReputationOracle.sol — Cross-platform reputation score queries (Phase 3)
```

All contracts are upgradeable (proxy pattern) during Phase 2. Upgrade authority transfers progressively from the founder to a DAO timelock. Full immutability (ownership renounced) is the Phase 3 endgame, gated by strict conditions: 2+ years of stable operation, zero critical incidents, community supermajority vote.

### Security

- Professional audit by a tier-1 firm (Trail of Bits, OpenZeppelin, or equivalent) before mainnet deployment
- Bug bounty program from day one
- Multi-sig treasury (3-of-5 signers: founder + 2 team + 2 community-elected)
- Circuit breakers: emergency pause on token operations if anomalies detected
- No admin mint function — nobody can create tokens arbitrarily
- All contracts verified and open-source on block explorer

### Cross-Platform Protocol (Phase 3)

The long-term vision is that TradeKarma becomes a protocol, not just a marketplace. Any e-commerce platform can integrate the KRUNE/KDEX/KSHRD economy through an open-source SDK.

```
[Marketplace A]  [Marketplace B]  [TradeKarma Marketplace]
      |                |                    |
      v                v                    v
  [Protocol SDK]   [Protocol SDK]    [Native Integration]
      |                |                    |
      +-------+--------+--------+----------+
              |
              v
   [TradeKarma Protocol — Base L2]
```

External platforms mint KRUNE for their users' positive actions. KRUNE is portable — a reputation earned on Marketplace A is recognized on Marketplace B. The protocol charges a 2% fee on KRUNE minted by external platforms and a per-query fee for cross-platform reputation lookups.

This is the endgame: TradeKarma transitions from a marketplace company to a protocol company. Revenue comes from protocol fees across an ecosystem of integrated marketplaces.

---

## 9. Governance

### Phase 2: Limited DAO

Governance starts narrow. KRUNE holders and KDEX holders vote on:
- KarmaRune earning rate adjustments
- New vendor categories
- Treasury allocation for marketing
- Feature prioritization (from a curated list)

The founder retains control over smart contract upgrades, treasury withdrawals, terms of service, and vendor onboarding criteria.

**Voting weight:**
- 1 staked $KRUNE = 1 vote
- 1 $KSHD = 3 votes (Phase 2), 10 votes (Phase 3)
- Quorum: 10% of circulating governance weight
- Voting period: 7 days
- Snapshot-based (off-chain votes, on-chain execution)

### Phase 3: Full DAO

All platform parameters are governed by the DAO. A Protocol Council (elected from DAO members) handles day-to-day governance execution. The founder role shifts from operator to protocol steward.

**Contract renouncement conditions (all must be met):**
- 2+ years of stable operation with zero critical incidents
- DAO has governed successfully for 12+ months
- Treasury is self-sustaining (fees exceed expenses for 6+ consecutive months)
- Community vote approves renouncement with 75%+ supermajority

---

## 10. Legal and Regulatory

Switzerland is one of the most favorable jurisdictions for token projects, but that does not mean we can skip the legal work.

### FINMA Token Classification

| Token | Target Classification | Key Requirements |
|-------|----------------------|------------------|
| $KRUNE | Utility token | Platform must be functional at issuance; token provides access to features; no investment promise |
| $KDEX | Payment/governance token | Subject to AML rules; may require money transmitter considerations |
| $KSHRD | Asset-backed / yield token | The most complex classification; potentially banking license territory under FINMA |

### Regulatory Strategy

**No ICO.** KRUNE is earned through platform usage, never sold for money. This removes the most common regulatory trigger.

**Functional platform first.** FINMA requires that a utility token's underlying platform is live and working at the time of token issuance. Our points-first approach satisfies this requirement — the economy is already running when we tokenize.

**Legal opinion before each phase.** Every token gets a FINMA classification opinion from a Swiss crypto lawyer before issuance. Budget: CHF 30,000-50,000 across all phases.

**KSHRD is the regulatory hot spot.** The board flagged KSHRD-to-USDC redemption as potentially falling under banking license territory. This is a blocking dependency. KSHRD does not launch without legal clearance. The fallback: drop KSHRD entirely and pay USDC directly to qualifying stakers (2-token model). The anti-whale mechanic works either way.

**Progressive decentralization as legal shield.** Swiss regulators are favorable toward genuine decentralization. Documenting the DAO transition roadmap and executing it transparently reduces long-term regulatory risk.

---

## 11. Precedents and Lessons

The three-token staking model is not entirely novel. Several projects have implemented related mechanics, with instructive outcomes.

| Project | Model | Outcome | Lesson for TradeKarma |
|---------|-------|---------|----------------------|
| **Curve (CRV/veCRV/3CRV)** | 3-token, lock-based yields, real fee revenue | Working. $2B+ TVL. But Convex controls 50%+ of governance. | Real revenue must back the flywheel. Governance concentration is a real risk. |
| **Axie Infinity (SLP/AXS)** | 2-token, uncapped earn token | SLP crashed 98%. Economy collapsed. | Uncapped earn tokens with one sink hyperinflate. KRUNE needs diverse sinks and caps. |
| **STEPN (GST/GMT)** | 2-token, move-to-earn | GST crashed 98% in 2 months. | When growth stops, earn-and-dump overwhelms buy pressure. |
| **Radiant Capital (dLP)** | Earned RDNT + bought ETH paired for yield | Worked mechanically. Then got hacked twice ($57M total). | The paired staking mechanic is proven. Security is more important than tokenomics. |
| **OlympusDAO (OHM/sOHM/gOHM)** | 3-token, rebase yields | Crashed 97.7%. 67% of users later called it a Ponzi. | If yield comes from new investors, it is a Ponzi. Period. |

**The closest precedent to TradeKarma's model is Radiant Capital's dLP mechanism:** you earn RDNT, pair it with ETH, and the staked position generates real fee yield. Mechanically, this is nearly identical to KRUNE + KDEX generating KSHRD. The mechanic worked until the protocol got exploited. The lesson: the economics are sound, but smart contract security is existential.

**The clearest cautionary tale is OlympusDAO:** high yields attracted capital, but the yield was funded by new participants, not by revenue. When growth slowed, the system collapsed. TradeKarma's yield is gated by real marketplace revenue. If revenue drops, yield drops proportionally. There is no mechanism for yield to exceed revenue.

---

## 12. Roadmap

| Period | Phase | Focus | Key Milestones |
|--------|-------|-------|----------------|
| Months 1-3 | 1a | Foundation | Legal entity, FINMA consultation, marketplace architecture, developer hired |
| Months 4-6 | 1b | Core Build | Marketplace functional: listings, cart, checkout, KRUNE points system live |
| Months 7-9 | 1c | Vendor Launch | 10+ vendors onboarded, first real transactions, anti-gaming v1 |
| Months 10-12 | 1d | Validation | 500+ MAU, KRUNE engagement data analyzed, tokenization decision made |
| Months 13-18 | 2a | Token Launch | KRUNE migrated on-chain (Base), KDEX launched, smart contracts audited |
| Months 19-24 | 2b | Treasury Growth | DAO governance v1, treasury accumulating, 5,000+ MAU |
| Months 25-36 | 2c | Scale | 200+ vendors, multiple categories, KRUNE/USDC trading pair, 15,000 MAU |
| Months 37-42 | 3a | Yield Activation | KSHRD staking live, treasury-backed yield, first redemptions |
| Months 43-48 | 3b | Protocol SDK | Open-source SDK, first external platform integration |
| Months 49-60 | 3c | Decentralization | Full DAO governance, contract ownership transferred, protocol self-sustaining |

---

## 13. Team and Operations

### Year 1

| Role | Who | Scope |
|------|-----|-------|
| Founder / CEO | Jamil | Vision, product, BD, vendor relationships, legal signatory |
| Full-Stack / Blockchain Dev | Hire (contract) | Smart contracts, backend, wallet integration |
| Frontend Dev | Hire (contract or part-time) | Marketplace UI, vendor dashboard |
| AI Agent Fleet | Automated | Tier-1 support, content moderation, review scoring, social media, analytics |

The AI-heavy operating model is a deliberate strategic choice. Traditional marketplace operations require 8-12 people. AI agents handle customer support (80%+ resolution rate), content moderation, review quality scoring, social media scheduling, and analytics reporting. Human oversight checkpoints catch what the AI misses.

Estimated cost savings: ~94% compared to hiring traditional Swiss staff for the same roles. The savings fund development, legal, and growth.

### Year 2-3

Team grows to 6-8 humans. CTO hire. Community manager. Marketing lead. Advisory board with tokenomics, e-commerce, and regulatory expertise. AI agents expand into dispute resolution triage, fraud detection, and treasury monitoring.

### Year 4-5

Team of 10-15. Protocol-focused. Engineering, community/DAO facilitation, legal (multi-jurisdiction), marketing/BD. AI agents handle day-to-day operations. Humans handle strategy, trust, and legal judgment.

---

## 14. Open Questions

This white paper is a first draft. Several decisions remain open and will be resolved through community input, legal consultation, and real-world data from Phase 1.

**Two tokens or three?** The board leans toward two tokens (KRUNE + KDEX) with direct USDC yield, dropping KSHRD as a separate token. The anti-whale mechanic works either way. KSHRD adds composability and treasury management flexibility but also adds regulatory surface area, liquidity fragmentation, and complexity. This decision is deferred until legal review is complete.

**What are the KRUNE sinks?** Beyond staking and burning for KSHRD, how else is KRUNE consumed? Listing boosts, dispute resolution deposits, premium feature access, and governance actions all burn KRUNE. The diversity of sinks determines whether KRUNE inflates or stays balanced.

**Fixed or dynamic KRUNE emission?** How much KRUNE per trade, review, referral? Is there a per-user cap? A global cap? The emission schedule determines the entire economy's stability. Phase 1 data will inform this.

**What happens to staked KRUNE after unstaking?** Burned? Returned? Locked in a cooldown? This affects whether power users can game the system by repeatedly staking and unstaking.

**Staking lock-up duration.** The board did not specify. Too short (instant unstake) and the yield commitment is meaningless. Too long (6+ months) and adoption suffers. A 30-90-180 day tiered system is proposed, with longer locks earning KSHRD at higher rates.

**Domain name.** Some board discussions used karmatrade.net, others tradekarma.net. This needs to be decided definitively before public launch.

---

## 15. Glossary

| Term | Definition |
|------|-----------|
| **KarmaRune ($KRUNE)** | Utility token earned through positive marketplace actions. Cannot be purchased. |
| **KarmaDex ($KDEX)** | Investment and governance token. Freely tradeable. Fixed or controlled supply. |
| **KarmaShard ($KSHRD)** | Yield token generated by staking KRUNE + KDEX together. Redeemable for USDC from treasury. |
| **Staking** | Locking KRUNE + KDEX in a smart contract to generate KSHRD yield. |
| **Burning** | Permanently destroying tokens (removing them from circulation). |
| **Treasury** | On-chain fund holding stablecoins, funded by platform fees, backing KSHRD redemption value. |
| **DAO** | Decentralized Autonomous Organization. Community governance of platform parameters. |
| **Base** | Ethereum Layer 2 network by Coinbase. Low fees, Ethereum security inheritance. |
| **FINMA** | Swiss Financial Market Supervisory Authority. |
| **Multi-sig** | Wallet requiring multiple approvals (e.g., 3-of-5 signers) for transactions. |
| **Sybil attack** | Creating many fake identities to game a reputation system. |
| **Timelock** | Smart contract delay between a governance vote and its execution. |
| **Circuit breaker** | Emergency mechanism to pause token operations if anomalies are detected. |
| **GMV** | Gross Merchandise Volume. Total value of goods sold through the platform. |
| **MAU** | Monthly Active Users. |

---

## Disclaimer

This white paper is a first draft and planning document. It is not a prospectus, investment solicitation, or financial advice. All financial projections are estimates based on assumptions that require validation through Phase 1 execution. Token designs are subject to change based on legal review, community feedback, and real-world data. No tokens have been issued. No investment is being offered.

This document should be reviewed with Swiss legal counsel before any token issuance or public commitments.

---

*TradeKarma — Reward good, don't punish bad.*

*Basel, Switzerland — March 2026*
