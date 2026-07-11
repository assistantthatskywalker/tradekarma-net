# Positive-Reinforcement Crypto Token Economy for E-Commerce

## 5-Year Business Plan — FIRST DRAFT

**Project:** TradeKarma (tradekarma.net)
**Author:** Jamil / That Sky Walker Enterprise
**Location:** Basel, Switzerland
**Date:** February 2026
**Status:** Planning / Pre-Development

---

## Table of Contents

1. [Executive Overview](#executive-overview)
2. [Phase 1: The Safe Play (Year 1)](#phase-1-the-safe-play-year-1)
3. [Phase 2: The KarmaShard Vault (Years 2-3)](#phase-2-the-karmashard-vault-years-2-3)
4. [Phase 3: The Full Economy (Years 4-5)](#phase-3-the-full-economy-years-4-5)
5. [Token Architecture Summary](#token-architecture-summary)
6. [5-Year Financial Overview](#5-year-financial-overview)
7. [Legal and Regulatory Strategy](#legal-and-regulatory-strategy)
8. [Appendix: Glossary](#appendix-glossary)

---

## Executive Overview

### The Problem

E-commerce platforms incentivize transactions but not community health. Reviews are gamed, support is outsourced, and customer loyalty is bought with discounts that erode margins. The cannabis/CBD vertical is especially underserved: payment processors are hostile, platforms delist products arbitrarily, and communities have no ownership stake.

### The Solution

A **positive-reinforcement token economy** where users earn crypto tokens for actions that make the marketplace better — honest reviews, helping other customers, referring quality vendors, resolving disputes constructively. Instead of punishing bad behavior (which platforms already do poorly), this system rewards good behavior and lets those rewards compound into real economic value.

### The Architecture (3 Tokens + Stablecoin)

| Token | Purpose | Phase | Type |
|-------|---------|-------|------|
| **USDC/DAI** | Payments and settlements (Phase 1 bridge) | 1-3 | Existing stablecoin |
| **KarmaRune ($KRUNE)** | Utility token earned through positive actions | 1-3 | Utility token |
| **KarmaShard ($KSHD)** | Earned by locking $KRUNE long-term; backed by treasury; deflationary store of value | 2-3 | Asset-backed / deflationary token |
| **KarmaDex ($KDEX)** | Native payment and transaction token | 2-3 | Payment token |

### Why This Can Work

- **Founder-market fit:** Jamil operates CBD/cannabis businesses in Switzerland and understands the vertical's pain points — payment friction, regulatory uncertainty, community fragmentation.
- **Swiss regulatory clarity:** Switzerland (FINMA) has clear frameworks for utility tokens. A functional platform with a utility token is a well-trodden path.
- **AI-augmented lean operations:** AI agents handle customer support, content moderation, and anti-gaming — keeping the team small and costs low.
- **Points-first strategy:** Start as a points system (no blockchain, no regulatory burden), prove the behavioral economics work, then tokenize once product-market fit is validated.

### 5-Year Vision

By Year 5, the protocol is a decentralized standard that any e-commerce marketplace can integrate. $KRUNE flows across platforms. The DAO governs. The treasury self-funds. Jamil's company earns protocol fees from every integrated marketplace, not just its own.

---

## Phase 1: The Safe Play (Year 1)

**Timeline:** Months 1-12
**Tagline:** Prove the economy works with real users before touching a blockchain.

### 1.1 Executive Summary

Phase 1 builds a functional e-commerce marketplace (or plugin for an existing platform) with an off-chain points system called KarmaRune. Users earn KarmaRune points for positive actions. KarmaRune can be redeemed for platform benefits — discounts, priority support, featured listings. Payments happen in fiat or stablecoin (USDC/DAI). No custom payment token yet. No blockchain complexity. The goal is to validate that positive-reinforcement economics drive measurable improvements in marketplace health.

### 1.2 Value Proposition

**For Buyers:**
- Earn rewards for being a good community member, not just for spending money
- Honest reviews, helping other buyers, and constructive feedback are valued and rewarded
- KarmaRune balance unlocks tangible benefits (discounts, priority access, reputation badges)

**For Vendors:**
- Access to a community incentivized to leave real, helpful reviews
- Lower customer acquisition cost through community-driven referrals
- CBD/cannabis-friendly platform with no risk of arbitrary deplatforming

**For the Platform:**
- Higher-quality user-generated content (reviews, Q&A)
- Reduced support burden through community self-help
- Defensible moat: the KarmaRune economy gets harder to leave the more you've earned

### 1.3 Token/Points Design (Phase 1)

| Element | Detail |
|---------|--------|
| **KarmaRune (off-chain points)** | Earned for positive actions, tracked in database |
| **Stablecoin (USDC/DAI)** | Used for actual payments and settlements |
| **KarmaRune earning actions** | Write a review (+10), answer a question (+5), refer a buyer (+20), resolve a dispute (+15), vendor completes order with 5-star rating (+10) |
| **KarmaRune spending** | 5% discount coupon (500 $KRUNE), featured review badge (200 $KRUNE), priority support queue (100 $KRUNE), vendor boost listing (1000 $KRUNE) |
| **Anti-gaming** | AI moderation flags suspicious patterns; cooldown periods; diminishing returns on repeat actions; human review threshold |

**Why points first, not tokens:**
- No FINMA regulatory overhead until tokenization
- Faster to build (database vs. smart contracts)
- Easier to adjust economics based on real behavior data
- If the model doesn't work, you haven't burned credibility with a failed token launch

**Tokenization trigger:** When the platform has 500+ active monthly users and KarmaRune earning/spending shows consistent engagement patterns (3+ months of data), begin Phase 2 token design.

### 1.4 Platform Options

| Option | Pros | Cons | Recommended? |
|--------|------|------|--------------|
| **Custom marketplace (Next.js + Supabase)** | Full control, KarmaRune deeply integrated, can tailor to CBD | Longer build time, need to attract both buyers and vendors | Yes, if CBD-focused |
| **Shopify plugin** | Massive existing merchant base, fast to market | Limited KarmaRune integration depth, Shopify controls the platform | Fallback option |
| **WooCommerce plugin** | Open source, good control, large install base | PHP ecosystem, self-hosted complexity | Maybe for vendor self-hosting |
| **Medusa.js (headless commerce)** | Open source, Node.js, headless, composable | Smaller ecosystem, fewer plugins | Strong alternative to custom |

**Recommendation:** Build on **Medusa.js** (open-source headless commerce) with a **Next.js storefront**. This gives full control over the KarmaRune integration while leveraging existing e-commerce infrastructure (inventory, orders, payments). Supabase handles KarmaRune points, user profiles, and analytics.

### 1.5 Target Market

**Primary: CBD/Cannabis E-Commerce (Switzerland + EU)**
- Jamil's domain expertise and existing business relationships
- Underserved by mainstream platforms (Shopify bans, PayPal freezes)
- Community is tight-knit and values trust — perfect for reputation economics
- Swiss legal clarity for both CBD products and utility tokens

**Secondary: Broader Wellness/Alternative Products**
- Natural extension from CBD — supplements, herbal products, wellness devices
- Similar platform hostility from mainstream e-commerce
- Overlapping customer base

### 1.6 Revenue Model

| Revenue Stream | Model | Year 1 Estimate |
|----------------|-------|-----------------|
| **Transaction fees** | 3-5% per sale | CHF 30,000 - 75,000 |
| **Vendor listing fees** | CHF 29-99/month per vendor | CHF 12,000 - 36,000 |
| **Premium vendor features** | Boost listings, analytics dashboard, priority placement | CHF 6,000 - 18,000 |
| **Payment processing margin** | 0.5-1% spread on stablecoin settlements | CHF 5,000 - 15,000 |
| **Total Year 1 Revenue** | | **CHF 53,000 - 144,000** |

**Assumptions:**
- 20-50 active vendors by end of Year 1
- 500-2,000 active monthly buyers
- CHF 600,000 - 1,500,000 gross merchandise volume (GMV)
- Average order value CHF 50-80

### 1.7 Cost Structure

| Cost Item | Monthly | Annual |
|-----------|---------|--------|
| **Founder salary (Jamil, part-time)** | CHF 3,000 | CHF 36,000 |
| **Developer (1 full-stack, contract)** | CHF 5,000 - 8,000 | CHF 60,000 - 96,000 |
| **AI agents (Claude, automation tools)** | CHF 200 - 500 | CHF 2,400 - 6,000 |
| **Infrastructure (Supabase, hosting, CDN)** | CHF 100 - 300 | CHF 1,200 - 3,600 |
| **Legal (FINMA consultation, company setup)** | — | CHF 5,000 - 10,000 |
| **Marketing (organic + small paid budget)** | CHF 500 - 1,000 | CHF 6,000 - 12,000 |
| **Payment processing (Stripe, crypto on-ramp)** | Variable | CHF 3,000 - 8,000 |
| **Miscellaneous** | CHF 300 | CHF 3,600 |
| **Total Year 1 Costs** | | **CHF 117,200 - 175,200** |

**Funding:** Self-funded (bootstrapped) from existing CBD business revenue + personal savings. Total capital needed: CHF 120,000 - 180,000 runway.

### 1.8 Team

| Role | Person | Status |
|------|--------|--------|
| **Founder / CEO / Product** | Jamil | Active |
| **Full-stack Developer** | Hire (contract) | Months 1-2 |
| **AI Operations** | Claude / AI agents | Active |
| **Legal Advisor** | Swiss crypto lawyer (retainer) | Month 1 |

**AI Agent Responsibilities:**
- Customer support (first-line, with human escalation)
- Content moderation and review quality scoring
- KarmaRune anti-gaming detection
- Vendor onboarding assistance
- Basic analytics and reporting

### 1.9 Key Milestones

| Month | Milestone | Deliverable |
|-------|-----------|-------------|
| **1-2** | Foundation | Company registered (if not already), legal consultation, platform architecture decided, developer hired |
| **3-4** | Core Build | Basic marketplace functional — product listings, cart, checkout with stablecoin + fiat |
| **5-6** | KarmaRune System | Points system live — earning actions, spending actions, user dashboard, anti-gaming v1 |
| **7-8** | Vendor Onboarding | 10+ CBD vendors onboarded, product catalog populated, first real transactions |
| **9-10** | Community Launch | Public beta, marketing push, 100+ active buyers, KarmaRune economy generating data |
| **11-12** | Validation | 500+ monthly active users, KarmaRune engagement data analyzed, tokenization decision made |

### 1.10 KPIs / Success Metrics

| KPI | Target (End of Year 1) | Why It Matters |
|-----|------------------------|----------------|
| **Monthly Active Users (MAU)** | 500-2,000 | Market validation |
| **Gross Merchandise Volume (GMV)** | CHF 100,000+/month | Revenue viability |
| **KarmaRune Engagement Rate** | 40%+ of users earn $KRUNE monthly | Economy validation |
| **Review Quality Score** | 30%+ improvement vs. baseline | Core thesis proof |
| **Vendor Retention** | 80%+ monthly | Platform stickiness |
| **Net Revenue** | CHF 5,000+/month by Month 12 | Path to sustainability |
| **KarmaRune Earn/Spend Ratio** | 60-80% of earned $KRUNE gets spent | Economy health |
| **Support Tickets Resolved by Community** | 20%+ | AI + community leverage |

### 1.11 Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Low vendor adoption** | Medium | High | Start with Jamil's own CBD products and network; offer first 3 months free |
| **KarmaRune gaming/abuse** | High | Medium | AI anti-gaming from day 1; diminishing returns; human review queue; adjust rules fast |
| **Regulatory surprise** | Low | High | Swiss utility token framework is clear; legal counsel from Month 1; points-first approach buys time |
| **Payment processor issues (CBD)** | Medium | High | Stablecoin payments as primary; multiple fiat processors as backup; Swiss-friendly processors exist |
| **Low buyer demand** | Medium | High | Leverage Jamil's existing customer base; organic content marketing; community-first approach |
| **Technical debt / slow development** | Medium | Medium | Use existing frameworks (Medusa.js); AI-assisted development; keep scope minimal |
| **Founder burnout** | Medium | High | AI agents handle operations; hire early; keep Phase 1 scope disciplined |

---

## Phase 2: The KarmaShard Vault (Years 2-3)

**Timeline:** Months 13-36
**Tagline:** Tokenize the proven economy and add long-term value capture.

### 2.1 Executive Summary

Phase 2 converts the validated KarmaRune points system into an on-chain utility token, introduces KarmaShard ($KSHD) as a long-term staking mechanism backed by a real treasury, and expands the marketplace to multiple vendor categories. The blockchain integration uses an Ethereum L2 (recommended: Base) for low fees and high throughput. A DAO structure begins to give the community governance power. The treasury is funded by platform fees, making KarmaShard genuinely asset-backed rather than speculative.

### 2.2 Value Proposition (New in Phase 2)

**For $KRUNE Holders:**
- On-chain ownership of earned reputation — portable, verifiable, tradeable
- Lock $KRUNE to earn $KSHD — a token backed by real treasury assets
- Governance rights — vote on platform fees, KarmaRune earning rates, new features

**For $KSHD Holders:**
- Share of platform treasury — redeemable for stablecoin at treasury-backed floor price
- Long-term alignment incentive — the longer you lock, the more $KSHD you earn
- Governance weight — $KSHD holders get amplified voting power
- Deflationary store of value — $KSHD can also be minted by permanently burning $KRUNE

**For Vendors:**
- Access to a growing, engaged marketplace with verified reputation
- Accept $KRUNE for discounts (burns tokens, creates scarcity)
- DAO participation — influence platform direction

### 2.3 Token Design (Phase 2)

#### KarmaRune Token ($KRUNE — On-Chain)

| Property | Detail |
|----------|--------|
| **Type** | ERC-20 utility token |
| **Chain** | Base (Ethereum L2) |
| **Supply** | Inflationary (minted through positive actions), balanced by burn/lock mechanisms |
| **Earning** | Same actions as Phase 1, now minted on-chain |
| **Spending/Burning** | Platform discounts (burn), premium features (burn), vendor boosts (burn) |
| **Locking** | Lock $KRUNE for 30/90/180 days to earn $KSHD |
| **FINMA Classification** | Utility token — provides access to platform functionality |

#### KarmaShard ($KSHD)

| Property | Detail |
|----------|--------|
| **Type** | ERC-20 asset-backed / deflationary token |
| **Chain** | Base (Ethereum L2) |
| **Supply** | Minted when $KRUNE is locked or burned; supply grows slowly |
| **Backing** | Platform treasury funded by 20% of all transaction fees |
| **Earning (lock)** | Lock $KRUNE: 30 days = 1x $KSHD multiplier, 90 days = 3x, 180 days = 6x |
| **Earning (burn)** | Burn 10,000 $KRUNE to mint 1 $KSHD (permanent, deflationary) |
| **Redemption** | Redeem $KSHD for pro-rata share of treasury (minus 5% redemption fee) |
| **Governance** | 1 $KSHD = 3 votes (vs. 1 $KRUNE = 1 vote) |

#### KarmaShard Locking Mechanics

| Lock Period | $KRUNE Required | $KSHD Earned | Annualized Yield (est.) |
|-------------|-----------------|--------------|------------------------|
| 30 days | 1,000 $KRUNE | 10 $KSHD | ~12% |
| 90 days | 1,000 $KRUNE | 30 $KSHD | ~12% |
| 180 days | 1,000 $KRUNE | 60 $KSHD | ~12% |

*Yield estimated assuming treasury grows proportionally with platform usage. Actual yield depends on treasury size and $KSHD supply.*

#### Treasury Structure

```
Platform Revenue (transaction fees, listing fees, premium features)
    |
    v
[Revenue Split]
    |--- 60% --> Operating expenses (team, infrastructure, marketing)
    |--- 20% --> KarmaShard Treasury (backs $KSHD redemption value)
    |--- 10% --> Development fund (new features, audits, integrations)
    |--- 10% --> Reserve fund (emergency, legal, regulatory)
```

**Treasury Security:**
- Multi-signature wallet (3-of-5 signers: founder + 2 team + 2 community-elected)
- On-chain transparency — anyone can verify treasury balance
- Monthly treasury reports published
- No single person can withdraw funds

### 2.4 Blockchain Choice: Base (Ethereum L2)

| Criteria | Base | Arbitrum | Polygon | Solana |
|----------|------|----------|---------|--------|
| **Transaction cost** | ~$0.01 | ~$0.02 | ~$0.01 | ~$0.001 |
| **Ethereum security** | Yes (optimistic rollup) | Yes (optimistic rollup) | Partial (PoS sidechain) | No |
| **Ecosystem maturity** | Growing fast (Coinbase) | Mature | Mature | Mature but different |
| **Fiat on-ramp** | Coinbase native | Good | Good | Good |
| **Swiss regulatory fit** | Good (Ethereum-based) | Good | Good | Acceptable |
| **Developer tooling** | Excellent (EVM) | Excellent (EVM) | Excellent (EVM) | Different (Rust) |

**Recommendation: Base.** Backed by Coinbase (fiat on-ramp for Swiss users), low fees, Ethereum security inheritance, and the growing Coinbase ecosystem provides distribution. Arbitrum is a strong alternative.

### 2.5 DAO Governance

**Phase 2 DAO Scope (limited):**
- Vote on KarmaRune earning rate adjustments
- Vote on new vendor categories
- Vote on treasury allocation for marketing campaigns
- Vote on feature prioritization (from a curated list)

**What the DAO does NOT control in Phase 2:**
- Smart contract upgrades (founder retains)
- Treasury withdrawal (multi-sig controls)
- Platform terms of service
- Vendor onboarding criteria

**Governance Token Weight:**
- 1 $KRUNE (staked) = 1 vote
- 1 $KSHD = 3 votes
- Quorum: 10% of circulating governance weight
- Voting period: 7 days
- Snapshot-based voting (off-chain votes, on-chain execution)

### 2.6 Revenue Model

| Revenue Stream | Model | Year 2 Estimate | Year 3 Estimate |
|----------------|-------|-----------------|-----------------|
| **Transaction fees** | 3-5% per sale | CHF 150,000 - 300,000 | CHF 400,000 - 800,000 |
| **Vendor listing fees** | CHF 29-199/month | CHF 60,000 - 120,000 | CHF 120,000 - 240,000 |
| **Premium vendor features** | Analytics, boost, priority | CHF 30,000 - 60,000 | CHF 60,000 - 120,000 |
| **$KSHD redemption fees** | 5% on $KSHD-to-stablecoin | CHF 5,000 - 15,000 | CHF 20,000 - 50,000 |
| **Token listing/DEX fees** | Liquidity provision returns | CHF 5,000 - 10,000 | CHF 10,000 - 30,000 |
| **Total Revenue** | | **CHF 250,000 - 505,000** | **CHF 610,000 - 1,240,000** |

**Assumptions (Year 2-3):**
- 100-300 active vendors
- 5,000-20,000 MAU
- CHF 3,000,000 - 8,000,000 GMV Year 2; CHF 8,000,000 - 20,000,000 GMV Year 3
- KarmaShard treasury reaches CHF 50,000-200,000 by end of Year 3

### 2.7 Cost Structure

| Cost Item | Year 2 Annual | Year 3 Annual |
|-----------|---------------|---------------|
| **Team salaries (3-5 people)** | CHF 240,000 - 400,000 | CHF 300,000 - 500,000 |
| **Smart contract audit** | CHF 30,000 - 80,000 | CHF 15,000 - 30,000 |
| **Infrastructure** | CHF 6,000 - 12,000 | CHF 12,000 - 24,000 |
| **Legal (ongoing + token issuance)** | CHF 20,000 - 40,000 | CHF 10,000 - 20,000 |
| **Marketing** | CHF 36,000 - 72,000 | CHF 60,000 - 120,000 |
| **AI agents / tooling** | CHF 6,000 - 12,000 | CHF 12,000 - 24,000 |
| **Blockchain gas / node** | CHF 3,000 - 6,000 | CHF 6,000 - 12,000 |
| **Miscellaneous** | CHF 12,000 | CHF 18,000 |
| **Total** | **CHF 353,000 - 634,000** | **CHF 433,000 - 748,000** |

**Funding Phase 2:**
- Phase 1 revenue (if profitable by Month 12)
- Small seed round: CHF 200,000 - 500,000 (Swiss crypto investors, CBD industry angels)
- Alternatively: Swiss Innovation Agency (Innosuisse) grant for blockchain commerce
- No ICO/IEO for $KRUNE — distributed only through platform usage

### 2.8 Team (Phase 2)

| Role | Count | Notes |
|------|-------|-------|
| **Founder / CEO** | 1 | Jamil — strategy, BD, vendor relations |
| **CTO / Lead Dev** | 1 | Hire — smart contracts, architecture |
| **Full-stack Developer** | 1-2 | Marketplace, frontend, integrations |
| **Community Manager** | 1 | DAO facilitation, user support escalation |
| **Legal Counsel** | Retainer | Swiss crypto regulatory specialist |
| **Marketing** | 0.5-1 | Content, partnerships, growth (can be part-time/agency) |
| **AI Agents** | N/A | Customer support, moderation, analytics, anti-gaming |

### 2.9 Key Milestones

| Month | Milestone | Deliverable |
|-------|-----------|-------------|
| **13-15** | Token Architecture | Smart contract design, FINMA legal opinion obtained, audit firm selected |
| **16-18** | Smart Contract Development | $KRUNE ERC-20 deployed on Base testnet, locking contract, $KSHD minting |
| **19-20** | Audit + Security | Smart contract audit completed, bug bounty program launched |
| **21-22** | Token Migration | Existing KarmaRune points migrated to on-chain $KRUNE, user wallet onboarding |
| **23-24** | KarmaShard Launch | Locking mechanism live, treasury funded, first $KSHD minted |
| **25-27** | DAO v1 | Snapshot governance live, first community votes |
| **28-30** | Marketplace Expansion | 3+ vendor categories beyond CBD, 200+ vendors |
| **31-33** | Liquidity + Trading | $KRUNE/USDC pool on Uniswap (Base), basic trading available |
| **34-36** | Growth Validation | 10,000+ MAU, treasury > CHF 100,000, DAO functional |

### 2.10 KPIs / Success Metrics

| KPI | Year 2 Target | Year 3 Target |
|-----|---------------|---------------|
| **MAU** | 5,000 | 15,000 |
| **GMV** | CHF 5,000,000 | CHF 15,000,000 |
| **Active Vendors** | 100 | 250 |
| **$KRUNE Circulating Supply** | Track (no target — inflationary by design) | Track |
| **$KRUNE Lock Rate** | 20% of supply locked | 35% of supply locked |
| **KarmaShard Treasury Value** | CHF 50,000 | CHF 200,000 |
| **DAO Participation Rate** | 15% of eligible voters | 25% of eligible voters |
| **Smart Contract Incidents** | 0 critical | 0 critical |
| **Monthly Revenue** | CHF 20,000+ | CHF 50,000+ |
| **Customer Acquisition Cost** | < CHF 15 | < CHF 10 |

### 2.11 Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Smart contract vulnerability** | Medium | Critical | Professional audit (Trail of Bits, OpenZeppelin), bug bounty, upgradeable contracts initially |
| **FINMA regulatory action** | Low | High | Legal opinion before launch; utility token design; functional platform requirement met |
| **Low $KRUNE demand / value** | Medium | Medium | KarmaRune has intrinsic utility (discounts, features); not dependent on speculation |
| **Treasury management failure** | Low | High | Multi-sig, on-chain transparency, monthly reports, conservative investment |
| **Token speculation dominance** | Medium | Medium | No $KRUNE presale; earned-only distribution; lock-up incentives reduce selling pressure |
| **Key person risk (Jamil)** | Medium | High | Hire CTO early; document everything; progressive decentralization |
| **Market downturn (crypto winter)** | Medium | Medium | $KRUNE utility is platform-native, not dependent on broader crypto market |
| **Scaling issues** | Low | Medium | Base L2 handles high throughput; off-chain batching for micro-rewards |

---

## Phase 3: The Full Economy (Years 4-5)

**Timeline:** Months 37-60
**Tagline:** A self-sustaining, decentralized protocol for positive-reinforcement commerce.

### 3.1 Executive Summary

Phase 3 introduces KarmaDex ($KDEX) as the native payment token, enables deflationary $KSHD minting by burning $KRUNE at scale, achieves full decentralization (contract ownership renounced, DAO governs all parameters), and opens the protocol for cross-platform integration. Other marketplaces can plug into the $KRUNE/$KSHD/$KDEX economy, paying protocol fees. The team shifts from operating the marketplace to maintaining the protocol, with AI agents running day-to-day operations. This phase transforms That Sky Walker Enterprise from a marketplace company into a protocol company.

### 3.2 Value Proposition (New in Phase 3)

**For the Ecosystem:**
- Any e-commerce platform can integrate the positive-reinforcement economy
- Portable reputation — a user's KarmaRune score is meaningful across all integrated platforms
- $KSHD as a store of value that represents accumulated positive contributions to commerce
- $KDEX as the native payment rail, reducing reliance on third-party stablecoins

**For $KSHD Holders:**
- Deflationary token — supply only increases when $KRUNE is burned, and burning removes $KRUNE permanently
- Represents "crystallized" positive reputation
- Premium governance tier — $KSHD holders have highest voting weight
- Potential secondary market value driven by scarcity and utility

**For $KDEX Holders:**
- Native payment token for seamless transactions across all TradeKarma-integrated platforms
- Lower fees than external stablecoin settlements
- Growing utility as the ecosystem expands

**For Integrated Platforms:**
- Plug-and-play SDK to add positive-reinforcement economy
- Access to cross-platform reputation data
- Shared anti-gaming intelligence
- Revenue share from protocol fees

### 3.3 Token Design (Phase 3 — Complete)

#### KarmaDex ($KDEX)

| Property | Detail |
|----------|--------|
| **Type** | ERC-20 payment token |
| **Chain** | Base (Ethereum L2) |
| **Supply** | Fixed or controlled-inflation supply (DAO-governed) |
| **Purpose** | Native payment and settlement across TradeKarma ecosystem |
| **Utility** | Transaction fees paid in $KDEX receive discount; vendor settlements; cross-platform payments |
| **Coexistence** | USDC/DAI remain accepted; $KDEX is the native option with fee advantages |

#### KarmaShard ($KSHD — Deflationary Burn Mechanics)

| Property | Detail |
|----------|--------|
| **Type** | ERC-20 deflationary / asset-backed token |
| **Chain** | Base (Ethereum L2) |
| **Supply** | Deflationary — minted only by locking or burning $KRUNE |
| **Burn minting** | Burn 10,000 $KRUNE to mint 1 $KSHD (ratio adjustable by DAO) |
| **Lock minting** | Lock $KRUNE for 30/90/180 days to earn $KSHD (as in Phase 2) |
| **Deflation source** | Every burn-minted $KSHD permanently removes 10,000 $KRUNE from circulation |
| **Governance** | 1 $KSHD = 10 votes (vs. $KRUNE = 1 vote) in Phase 3 (upgraded from 3x in Phase 2) |
| **Utility** | Premium platform access, cross-platform reputation verification, protocol governance, treasury claim |

#### Complete Token Hierarchy

```
Positive Actions (reviews, support, referrals)
    |
    v
$KRUNE (utility, earned) --burn--> $KSHD (deflationary, store of value)
    |
    |--lock (30/90/180 days)--> $KSHD (asset-backed, treasury claim)
    |
    |--spend--> Platform benefits (discounts, features, boosts)
    |
$KDEX ---> Native Payments & Settlements
USDC/DAI ---> External Payments & Settlements (bridge)
```

#### Token Interaction Economics

| Action | $KRUNE Effect | $KSHD Effect | $KDEX Effect |
|--------|--------------|-------------|-------------|
| User writes quality review | +10 $KRUNE minted | — | — |
| User locks 1000 $KRUNE for 90 days | -1000 $KRUNE (locked) | +30 $KSHD minted | — |
| User unlocks after 90 days | +1000 $KRUNE (returned) | $KSHD retained | — |
| User redeems $KSHD | — | -X $KSHD burned | — |
| User burns 10,000 $KRUNE for $KSHD | -10,000 $KRUNE burned permanently | +1 $KSHD minted | — |
| User spends $KRUNE on discount | -500 $KRUNE burned | — | — |
| Vendor accepts $KRUNE payment | -$KRUNE transferred/burned | — | — |
| Buyer pays with $KDEX | — | — | $KDEX transferred to vendor |

### 3.4 Cross-Platform Protocol

#### Protocol Architecture

```
[Marketplace A]  [Marketplace B]  [Marketplace C]  [Jamil's Marketplace]
      |                |                |                    |
      v                v                v                    v
  [Protocol SDK]   [Protocol SDK]   [Protocol SDK]    [Native Integration]
      |                |                |                    |
      +--------+-------+-------+--------+
               |
               v
    [TradeKarma Protocol Smart Contracts]
    - KarmaRune.sol (mint/burn/transfer)
    - KarmaShardLock.sol (lock/unlock/$KSHD mint)
    - KarmaShardBurn.sol (burn $KRUNE, mint $KSHD)
    - KarmaDex.sol ($KDEX payment token)
    - Treasury.sol (multi-sig, fee collection)
    - Governance.sol (DAO voting)
    - ReputationOracle.sol (cross-platform scores)
               |
               v
         [Base L2 / Ethereum]
```

#### Protocol Fee Structure

| Fee Type | Rate | Collected By |
|----------|------|-------------|
| **$KRUNE minting (external platforms)** | 2% of $KRUNE minted goes to treasury | Protocol |
| **$KSHD redemption** | 5% redemption fee to treasury | Protocol |
| **$KSHD burn-minting** | 1% of $KRUNE burned goes to treasury (as $KRUNE) | Protocol |
| **Cross-platform reputation query** | 0.001 USDC per query | Protocol |
| **$KDEX transaction fee** | 0.1% per $KDEX payment | Protocol |
| **SDK license** | Free (open source) — fees are protocol-level | — |

### 3.5 Decentralization Roadmap

| Component | Phase 2 State | Phase 3 Target | Timeline |
|-----------|--------------|----------------|----------|
| **Smart contracts** | Upgradeable, founder-controlled | Immutable, ownership renounced | Month 48 |
| **Treasury** | Multi-sig (founder + team + community) | DAO-controlled multi-sig (all community-elected) | Month 42 |
| **Parameter changes** | Founder proposes, DAO votes | DAO proposes and votes, timelock execution | Month 40 |
| **Platform operations** | Team + AI agents | AI agents + community moderators, team maintains protocol | Month 45 |
| **Fee structure** | Founder sets | DAO votes on changes | Month 40 |
| **New integrations** | Team approves | Permissionless (any platform can integrate) | Month 50 |

**Contract Renouncement Conditions (all must be met):**
- 2+ years of stable smart contract operation with zero critical incidents
- DAO has successfully governed for 12+ months
- Treasury is self-sustaining (fees > expenses for 6+ consecutive months)
- Multiple independent smart contract audits completed
- Community vote approves renouncement with 75%+ supermajority

### 3.6 AI-Powered Anti-Gaming (Advanced)

| Layer | Mechanism | Description |
|-------|-----------|-------------|
| **Pattern Detection** | ML models trained on historical gaming attempts | Flags anomalous KarmaRune earning patterns |
| **Social Graph Analysis** | Network analysis of user interactions | Detects collusion rings (fake reviews, mutual boosting) |
| **Cross-Platform Intelligence** | Shared fraud signals across integrated platforms | Gaming on one platform flags the user everywhere |
| **Behavioral Biometrics** | Interaction timing, review writing patterns | Distinguishes real users from bots/farms |
| **Progressive Trust** | New users earn at reduced rates; trust builds over time | Limits ROI of creating new accounts to game |
| **Community Jury** | High-$KRUNE users review flagged cases | Decentralized human judgment for edge cases |

### 3.7 Revenue Model

| Revenue Stream | Year 4 Estimate | Year 5 Estimate |
|----------------|-----------------|-----------------|
| **Marketplace transaction fees** | CHF 800,000 - 1,500,000 | CHF 1,200,000 - 2,500,000 |
| **Vendor fees (listing + premium)** | CHF 240,000 - 480,000 | CHF 360,000 - 720,000 |
| **Protocol fees (external platforms)** | CHF 50,000 - 150,000 | CHF 200,000 - 600,000 |
| **$KSHD redemption fees** | CHF 40,000 - 100,000 | CHF 80,000 - 200,000 |
| **Cross-platform reputation queries** | CHF 10,000 - 30,000 | CHF 50,000 - 150,000 |
| **$KSHD burn-minting fees** | CHF 5,000 - 15,000 | CHF 15,000 - 50,000 |
| **$KDEX transaction fees** | CHF 10,000 - 30,000 | CHF 50,000 - 150,000 |
| **Total Revenue** | **CHF 1,155,000 - 2,305,000** | **CHF 1,955,000 - 4,370,000** |

**Assumptions:**
- 30,000-60,000 MAU on own marketplace
- 2-5 external platforms integrated by Year 5
- GMV own marketplace: CHF 20,000,000 - 40,000,000 (Year 4); CHF 30,000,000 - 60,000,000 (Year 5)
- Combined cross-platform GMV: CHF 5,000,000 - 20,000,000 additional by Year 5
- KarmaShard treasury: CHF 500,000 - 1,500,000 by end of Year 5

### 3.8 Cost Structure

| Cost Item | Year 4 Annual | Year 5 Annual |
|-----------|---------------|---------------|
| **Team (6-10 people)** | CHF 500,000 - 800,000 | CHF 600,000 - 900,000 |
| **Smart contract maintenance + audits** | CHF 30,000 - 60,000 | CHF 20,000 - 40,000 |
| **Infrastructure (multi-region)** | CHF 24,000 - 48,000 | CHF 36,000 - 72,000 |
| **Legal (multi-jurisdiction)** | CHF 30,000 - 60,000 | CHF 40,000 - 80,000 |
| **Marketing + BD** | CHF 120,000 - 240,000 | CHF 150,000 - 300,000 |
| **AI agents / ML infrastructure** | CHF 24,000 - 48,000 | CHF 36,000 - 72,000 |
| **Blockchain costs** | CHF 12,000 - 24,000 | CHF 18,000 - 36,000 |
| **Community incentives / grants** | CHF 30,000 - 60,000 | CHF 50,000 - 100,000 |
| **Miscellaneous** | CHF 24,000 | CHF 30,000 |
| **Total** | **CHF 794,000 - 1,364,000** | **CHF 980,000 - 1,630,000** |

### 3.9 Team (Phase 3)

| Role | Count | Notes |
|------|-------|-------|
| **Founder / CEO** | 1 | Jamil — protocol strategy, partnerships, governance |
| **CTO** | 1 | Protocol architecture, smart contracts |
| **Backend Engineers** | 2 | Protocol SDK, API, integrations |
| **Frontend / Product** | 1-2 | Marketplace UX, governance UI |
| **Community / DAO Lead** | 1 | Governance facilitation, community growth |
| **Marketing / BD** | 1-2 | Partnerships with external platforms, brand |
| **Legal** | 1 (retainer) | Multi-jurisdiction compliance |
| **AI / ML Engineer** | 1 | Anti-gaming models, AI agent management |
| **AI Agents** | N/A | Day-to-day operations, support, moderation, reporting |

### 3.10 Key Milestones

| Month | Milestone | Deliverable |
|-------|-----------|-------------|
| **37-39** | $KSHD Burn Design + $KDEX Design | KarmaShard burn-to-mint mechanics, KarmaDex payment token, economic modeling |
| **40-42** | Audit + Launch | Contracts audited, $KSHD burn-minting live, $KDEX payment live, first burns |
| **43-45** | Protocol SDK v1 | Open-source SDK for external platform integration |
| **46-48** | First External Integration | 1-2 external platforms using TradeKarma protocol |
| **49-51** | Full DAO Transition | Contract ownership transferred to DAO, all parameters governed |
| **52-54** | International Expansion | Compliance in 3+ jurisdictions (EU, UK, US states) |
| **55-57** | Protocol Growth | 5+ integrated platforms, cross-platform reputation functional |
| **58-60** | Sustainability Proven | Protocol revenue > costs for 6 months, treasury self-sustaining |

### 3.11 KPIs / Success Metrics

| KPI | Year 4 Target | Year 5 Target |
|-----|---------------|---------------|
| **MAU (own marketplace)** | 30,000 | 50,000 |
| **MAU (cross-platform)** | 5,000 | 25,000 |
| **Integrated Platforms** | 2 | 5+ |
| **GMV (own marketplace)** | CHF 25,000,000 | CHF 50,000,000 |
| **GMV (cross-platform)** | CHF 5,000,000 | CHF 15,000,000 |
| **$KSHD Minted (total)** | 500 | 2,000 |
| **$KRUNE Burned (cumulative)** | 5,000,000 | 20,000,000 |
| **KarmaShard Treasury** | CHF 500,000 | CHF 1,500,000 |
| **DAO Proposals Executed** | 20+ | 50+ |
| **Protocol Revenue** | CHF 100,000+/month | CHF 200,000+/month |
| **Smart Contract Incidents** | 0 critical | 0 critical |

### 3.12 Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **$KSHD speculation overtakes utility** | Medium | Medium | High burn cost (10,000 $KRUNE per $KSHD); no presale; earned-only $KRUNE |
| **Cross-platform adoption too slow** | High | Medium | Own marketplace remains primary revenue; protocol fees are bonus |
| **Regulatory fragmentation (multi-jurisdiction)** | Medium | High | Start with Swiss-friendly jurisdictions; legal counsel per market; modular compliance |
| **DAO governance attacks** | Low | High | Timelocked execution; guardian veto (first 12 months); quorum requirements |
| **Decentralization reduces quality** | Medium | Medium | AI agents maintain quality standards regardless of governance; gradual transition |
| **Competitor launches similar protocol** | Medium | Medium | First-mover in CBD/cannabis vertical; network effects from cross-platform reputation |
| **Economic model breaks at scale** | Low | Critical | Extensive economic simulation before each phase; adjustable parameters; circuit breakers |
| **Key talent attrition** | Medium | High | Equity/token incentives; progressive decentralization reduces key-person dependency |

---

## Token Architecture Summary

### Complete Token Flow

```
                    EARNING
                      |
    [Positive Action] --> +$KRUNE minted
                             |
              +--------------+--------------+
              |              |              |
           SPEND           LOCK          BURN
              |              |              |
    [Platform benefits]   [30/90/180d]   [10,000:1]
    $KRUNE burned        +$KSHD minted   +$KSHD minted
                         $KRUNE locked   $KRUNE burned
                              |          permanently
                           REDEEM
                              |
                    [Treasury claim]
                    $KSHD burned
                    USDC/$KDEX received
```

### Token Supply Dynamics

| Token | Supply Type | Inflationary Pressure | Deflationary Pressure |
|-------|------------|----------------------|----------------------|
| **KarmaRune ($KRUNE)** | Inflationary (minted via actions) | New user actions | Spending (burn), $KSHD minting (burn), locking (temporary) |
| **KarmaShard ($KSHD)** | Slowly growing / deflationary | $KRUNE locking and burning | Redemption (burn) |
| **KarmaDex ($KDEX)** | Fixed / controlled supply | DAO-governed emission (if any) | Transaction fee burns (optional, DAO-governed) |

### Economic Equilibrium

The system is designed to reach equilibrium where:
- $KRUNE minting rate (from positive actions) roughly equals $KRUNE burn rate (spending + $KSHD minting)
- $KSHD supply grows proportionally to treasury value (maintaining per-$KSHD backing value)
- $KSHD burn-minted supply grows very slowly (high burn cost creates scarcity)
- Platform revenue funds treasury, which backs $KSHD, which incentivizes $KRUNE locking, which reduces $KRUNE sell pressure
- $KDEX provides a stable, native payment rail that grows in utility with ecosystem adoption

---

## 5-Year Financial Overview

### Revenue Projection (CHF, Conservative - Optimistic Range)

| Year | Revenue (Low) | Revenue (High) | Costs (Low) | Costs (High) | Net (Low) | Net (High) |
|------|---------------|----------------|-------------|--------------|-----------|------------|
| **1** | 53,000 | 144,000 | 117,200 | 175,200 | -122,200 | -31,200 |
| **2** | 250,000 | 505,000 | 353,000 | 634,000 | -384,000 | 152,000 |
| **3** | 610,000 | 1,240,000 | 433,000 | 748,000 | -138,000 | 807,000 |
| **4** | 1,155,000 | 2,305,000 | 794,000 | 1,364,000 | -209,000 | 1,511,000 |
| **5** | 1,955,000 | 4,370,000 | 980,000 | 1,630,000 | 325,000 | 2,740,000 |

### Cumulative Cash Position

| Scenario | Year 1 | Year 2 | Year 3 | Year 4 | Year 5 |
|----------|--------|--------|--------|--------|--------|
| **Conservative** | -122,200 | -506,200 | -644,200 | -853,200 | -528,200 |
| **Moderate** | -76,700 | -193,200 | 141,300 | 792,300 | 2,324,800 |
| **Optimistic** | -31,200 | 120,800 | 927,800 | 2,438,800 | 5,178,800 |

**Interpretation:**
- **Conservative scenario:** Requires CHF 650,000-860,000 total funding over 4 years before reaching profitability in Year 5.
- **Moderate scenario:** Requires CHF 200,000-250,000 seed funding; profitable by Year 3.
- **Optimistic scenario:** Self-funding by Year 2; strong returns by Year 5.

### Total Funding Needed

| Scenario | Total External Funding Required | Break-Even |
|----------|---------------------------------|------------|
| **Conservative** | CHF 650,000 - 860,000 | Year 5 |
| **Moderate** | CHF 200,000 - 250,000 | Year 3 |
| **Optimistic** | CHF 120,000 - 180,000 (Phase 1 only) | Year 2 |

---

## Legal and Regulatory Strategy

### Swiss Framework (FINMA)

Switzerland classifies tokens into three categories:

| FINMA Category | Our Token | Classification | Key Requirements |
|----------------|-----------|----------------|------------------|
| **Payment Token** | KarmaDex ($KDEX) | Payment token | May require money transmitter license; Phase 3 legal review required |
| **Utility Token** | KarmaRune ($KRUNE) | Utility | Platform must be functional at issuance; token provides access to platform features |
| **Asset Token** | KarmaShard ($KSHD) | May qualify as asset token | If redeemable for treasury, may need securities compliance |

### Regulatory Action Items

| Phase | Action | Timeline | Cost Estimate |
|-------|--------|----------|---------------|
| **1** | Legal entity setup (GmbH or AG) | Month 1-2 | CHF 3,000 - 8,000 |
| **1** | FINMA utility token legal opinion | Month 6-8 | CHF 5,000 - 15,000 |
| **2** | $KSHD token classification opinion | Month 13-15 | CHF 10,000 - 20,000 |
| **2** | AML/KYC compliance (if required) | Month 16-18 | CHF 5,000 - 15,000 |
| **3** | $KDEX payment token classification + compliance | Month 37-39 | CHF 15,000 - 30,000 |
| **3** | Multi-jurisdiction compliance review | Month 37-40 | CHF 20,000 - 40,000 |
| **3** | DAO legal structure (Swiss association?) | Month 40-42 | CHF 10,000 - 20,000 |

### Key Legal Principles

1. **No ICO / Token Sale:** $KRUNE is earned through platform usage only. Never sold for fiat or crypto. This significantly reduces regulatory burden.
2. **Functional Platform First:** The marketplace must be live and functional before $KRUNE is tokenized. This is a core FINMA requirement for utility tokens.
3. **KarmaShard Treasury Transparency:** If $KSHD is classified as an asset token, implement securities-grade reporting and compliance.
4. **Progressive Decentralization:** Document the roadmap to DAO governance. Swiss regulators are favorable toward decentralization when done transparently.
5. **Cannabis Compliance:** Ensure all products sold comply with Swiss law (THC < 1% for CBD products). Platform terms of service must enforce this.
6. **$KDEX Payment Token Review:** KarmaDex as a payment token requires careful FINMA classification. Plan for potential money transmitter obligations.

---

## Appendix: Glossary

| Term | Definition |
|------|-----------|
| **KarmaRune ($KRUNE)** | Utility token earned through positive marketplace actions (reviews, support, referrals) |
| **KarmaShard ($KSHD)** | Token earned by locking or burning $KRUNE; backed by platform treasury; deflationary store of value |
| **KarmaDex ($KDEX)** | Native payment and transaction token for the TradeKarma ecosystem |
| **TradeKarma** | The project name and protocol brand (tradekarma.net) |
| **Treasury** | On-chain fund holding stablecoins, funded by platform fees, backing $KSHD value |
| **DAO** | Decentralized Autonomous Organization — community governance of platform parameters |
| **GMV** | Gross Merchandise Volume — total value of goods sold through the platform |
| **MAU** | Monthly Active Users |
| **Base** | Ethereum Layer 2 network by Coinbase — low fees, Ethereum security |
| **FINMA** | Swiss Financial Market Supervisory Authority |
| **Multi-sig** | Multi-signature wallet requiring multiple approvals for transactions |
| **Timelock** | Smart contract delay between governance vote and execution (safety mechanism) |
| **Circuit Breaker** | Emergency mechanism to pause token operations if anomalies detected |

---

*This is a FIRST DRAFT planning document. All financial projections are estimates based on assumptions that need validation through Phase 1 execution. This document should be reviewed with legal counsel before any token issuance or public commitments.*

*Last updated: February 2026*

*Author: cka (claude-kali-assistant)*
