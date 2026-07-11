# KarmaTrade.net — Product Requirements Document

**Version:** 1.0
**Date:** March 17, 2026
**Author:** Jamil Wenzel / That Sky Walker Enterprise
**Status:** Draft — awaiting review
**Domain:** karmatrade.net

---

## 1. Overview

### What is KarmaTrade?

KarmaTrade is an e-commerce marketplace where honest participation is rewarded. Buyers earn reputation points for quality reviews, helpful answers, and community contributions. Vendors earn reputation for reliable service, transparent communication, and fair pricing. Reputation is earned — never purchased — and unlocks real economic benefits.

### Why does this need to exist?

The review economy is broken. You can buy 500 five-star reviews on Amazon for a few hundred dollars. A buyer who writes a genuine, detailed, 45-minute review gets nothing. This creates a trust deficit that costs the global e-commerce industry billions in returns, disputes, and lost customers.

Every existing platform punishes bad behavior. None meaningfully rewards good behavior. KarmaTrade flips that model: positive reinforcement over punishment.

### What makes it different?

1. **Reputation is earned, never bought.** No amount of money can shortcut trust on this platform.
2. **Reputation is portable.** Your track record belongs to you, not the platform. (Phase 2+: on-chain)
3. **Quality reviews are an income stream.** Eventually, earned reputation unlocks yield backed by real platform revenue.
4. **Vendor reputation is transparent and verifiable.** Buyers see exactly how a vendor earned their standing.

### One-liner

> Trade with trust. Earn with integrity.

---

## 2. Target Users

### Primary — Buyers

| Segment | Description | Pain Point |
|---------|-------------|-----------|
| **Quality-conscious shoppers** | Buy deliberately, read reviews before purchasing, care about getting what's advertised | Can't trust reviews — don't know what's fake |
| **Active reviewers** | Already write detailed reviews on Amazon/Trustpilot, motivated by helping others | No reward for effort, reviews locked to one platform |
| **Niche/specialty buyers** | Buy artisan, sustainable, or specialty goods where trust matters more than price | Mainstream platforms don't serve niche vendor relationships well |

### Primary — Vendors

| Segment | Description | Pain Point |
|---------|-------------|-----------|
| **Small-to-medium vendors** | Independent sellers with quality products but limited marketing budget | Drowned out by big sellers and fake-review competitors |
| **Niche/artisan producers** | Handmade, sustainable, specialty goods | Platforms like Amazon/Etsy commoditize their work, race to the bottom |
| **Multi-platform sellers** | Sell across 2+ platforms | Reputation doesn't transfer — start from zero on each platform |

### Secondary

| Segment | Description |
|---------|-------------|
| **Investors** | Buy KDEX token to participate in governance and yield (Phase 2+) |
| **Community moderators** | Earn KRUNE by helping maintain marketplace quality |
| **Affiliate/referrers** | Earn KRUNE by bringing quality users to the platform |

---

## 3. Product Scope

### Phase 1 — MVP Marketplace (Month 1-6)

**Goal:** Prove that positive reinforcement changes buyer and vendor behavior on a marketplace. No blockchain. No crypto jargon. Just a marketplace with a smart points system.

#### 3.1 Core Features

##### Marketplace

| Feature | Description | Priority |
|---------|-------------|----------|
| **Product listings** | Vendors create listings with title, description, images, price, category, shipping | P0 |
| **Product search & browse** | Full-text search, category filters, sort by relevance/price/reputation | P0 |
| **Shopping cart & checkout** | Standard e-commerce cart, Stripe payment processing (card + TWINT for CH) | P0 |
| **Order management** | Buyer: track orders. Vendor: manage orders, update status, handle shipping | P0 |
| **Vendor storefront** | Each vendor gets a profile page with their listings, reputation score, and history | P0 |
| **Category system** | Hierarchical categories. Start broad, refine based on vendor supply | P0 |
| **Messaging** | Buyer-vendor direct messaging for pre-sale questions and post-sale support | P1 |
| **Dispute resolution** | Structured process: buyer files claim → vendor responds → platform mediates | P1 |
| **Wishlist / saved items** | Buyers can save products for later | P2 |
| **Product comparisons** | Side-by-side comparison on key attributes | P2 |

##### Review & Reputation System

| Feature | Description | Priority |
|---------|-------------|----------|
| **Structured reviews** | Star rating (1-5) + text + optional photos + structured fields (quality, shipping, accuracy) | P0 |
| **Karma Points (KRUNE-equivalent)** | Earned for reviews, answers, referrals, dispute resolution. Tracked in database | P0 |
| **Quality multiplier** | AI-scored review quality (0.5x–2.5x) based on detail, specificity, helpfulness | P0 |
| **Karma leaderboard** | Public leaderboard showing top contributors by category and overall | P0 |
| **Verified purchase badge** | Reviews from confirmed buyers get a badge and earn more points | P0 |
| **Vendor reputation score** | Composite score: shipping speed, product accuracy, communication, dispute rate | P0 |
| **Review helpfulness voting** | Users vote reviews as helpful — reviewer earns bonus points | P1 |
| **Q&A section** | Buyer questions on product pages, answerable by vendor or community | P1 |
| **Reputation history** | Full timeline of how a user's reputation was built — transparent and auditable | P1 |
| **Review challenges** | Vendors can flag suspicious reviews for AI + human review | P1 |

##### Points Economy (Phase 1 — Off-Chain)

| Action | Points Earned | Conditions |
|--------|--------------|------------|
| Write a review (verified purchase) | 10-50 | Scaled by quality multiplier |
| Write a review (non-purchase) | 3-15 | Lower base, still quality-scaled |
| Review with photos | +10 bonus | Minimum 2 photos |
| Answer a product question | 5-15 | Quality-scored |
| Helpful vote received on your review | 2 | Per vote, capped at 20/review |
| Refer a buyer (active after 30 days) | 30 | One-time per referral |
| Refer a vendor (active after 30 days) | 50 | One-time per referral |
| Complete order on time (vendor) | 5-20 | Scaled by order value |
| Resolve a dispute constructively | 15-30 | Platform-assessed |
| Report confirmed fraud | 20 | Must be verified |

| Spending Option | Cost | Description |
|-----------------|------|-------------|
| 5% purchase discount | 500 pts | One-time use per order |
| Featured review badge | 200 pts | Your review pinned to top of product page for 7 days |
| Priority support queue | 100 pts | Skip the line for platform support |
| Vendor listing boost | 1,000 pts | Listing appears higher in search for 14 days |
| Exclusive early access | 250 pts | Access to new features, beta programs |

##### Anti-Gaming & Trust

| Mechanism | Description | Priority |
|-----------|-------------|----------|
| **AI review scoring** | ML model scores review quality: length, specificity, detail, originality | P0 |
| **Velocity limits** | Max reviews/day, cooldown between actions, diminishing returns | P0 |
| **Graph analysis** | Detect coordinated review rings, fake account clusters | P1 |
| **Behavioral fingerprinting** | Typing patterns, time-on-page, interaction signals | P1 |
| **Human review threshold** | Accounts flagged by AI go to manual review queue | P0 |
| **Sybil resistance** | Phone verification + shipping address uniqueness for earning eligibility | P0 |
| **AI-generated review detection** | Classifier to detect GPT/LLM-generated fake reviews | P0 |

#### 3.2 Vendor Onboarding

Onboarding must be frictionless. Target: vendor goes from signup to first listing in under 15 minutes.

1. **Sign up** — email + password, or Google/Apple SSO
2. **Verify identity** — Swiss ID or international passport scan (for payout eligibility)
3. **Create store** — name, logo, description, category, shipping regions
4. **Add first product** — guided flow with image upload, pricing, description templates
5. **Connect payment** — Stripe Connect onboarding for payouts
6. **Go live** — listing published immediately (AI moderation checks async)

**Founding Vendor Program:**
- First 50 vendors get "Founding Vendor" permanent badge
- Free listings for 12 months (no subscription)
- Direct onboarding support (we set up their first 5 listings)
- Early access to token migration (Phase 2)

#### 3.3 Buyer Onboarding

1. **Sign up** — email + password, Google/Apple SSO, or "continue as guest" for browsing
2. **Browse & buy** — no account required to purchase (guest checkout)
3. **Earn prompt** — after first purchase, prompt: "Write a review and earn Karma Points"
4. **Profile creation** — progressive: only ask for details when they want to earn points or write reviews
5. **Phone verification** — required to earn points (prevents spam accounts)

---

## 4. Technical Architecture

### Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| **Frontend** | Next.js 14+ (App Router) | SSR for SEO, React ecosystem, fast development |
| **Backend** | Next.js API routes + Supabase | Serverless, scales to zero, integrated auth/DB |
| **Database** | Supabase (PostgreSQL) | Real-time subscriptions, RLS, existing team expertise |
| **Auth** | Supabase Auth (email, Google, Apple) | Built-in, handles SSO, phone verification |
| **Payments** | Stripe Connect | Marketplace split payments, multi-currency, TWINT (CH) |
| **Search** | Supabase full-text + pg_trgm | Start simple, migrate to Meilisearch if needed |
| **Image hosting** | Supabase Storage + CDN | Integrated, supports transforms |
| **AI/ML** | Claude API (review scoring), custom classifiers | Review quality, fraud detection, content moderation |
| **Email** | Zoho Campaigns (transactional + marketing) | Already in stack, free tier covers Phase 1 |
| **Hosting** | Vercel | Next.js native, auto-scaling, Swiss edge nodes |
| **Monitoring** | Vercel Analytics + Sentry | Performance + error tracking |

### Database Schema (Core Tables)

```
users
├── id, email, name, phone, avatar_url
├── role (buyer, vendor, admin)
├── karma_points (integer, running total)
├── reputation_score (computed, 0-100)
├── verified_at, created_at
└── referral_code

vendors (extends users)
├── store_name, store_slug, description, logo
├── stripe_account_id
├── shipping_regions[], return_policy
├── reputation_score, total_orders, avg_rating
└── founding_vendor (boolean)

products
├── id, vendor_id, title, description, price, currency
├── images[], category_id, tags[]
├── stock_quantity, shipping_weight
├── status (draft, active, paused, sold_out)
└── avg_rating, review_count

orders
├── id, buyer_id, vendor_id, status
├── items[], subtotal, shipping, total
├── stripe_payment_intent_id
├── shipped_at, delivered_at
└── tracking_number, tracking_url

reviews
├── id, product_id, buyer_id, order_id
├── rating (1-5), title, body, images[]
├── quality_score (AI: 0.0-1.0)
├── quality_multiplier (0.5-2.5)
├── karma_earned, helpful_votes
├── verified_purchase (boolean)
└── status (pending, published, flagged, removed)

karma_transactions
├── id, user_id, amount, balance_after
├── action_type (review, referral, purchase, spend, etc.)
├── reference_id, reference_type
└── description, created_at

categories
├── id, name, slug, parent_id
├── icon, description
└── product_count

messages
├── id, from_user_id, to_user_id
├── order_id (optional), body
└── read_at, created_at

disputes
├── id, order_id, buyer_id, vendor_id
├── reason, description, evidence_urls[]
├── status (open, vendor_responded, mediation, resolved)
├── resolution, resolved_at
└── karma_awarded (if constructive resolution)
```

### Infrastructure Diagram

```
                    ┌─────────────┐
                    │   Vercel     │
                    │  (Next.js)   │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
      ┌───────▼──┐  ┌─────▼─────┐ ┌───▼────────┐
      │ Supabase │  │  Stripe   │ │ Claude API │
      │ (DB/Auth │  │ (Payments)│ │ (AI/ML)    │
      │  Storage)│  │           │ │            │
      └──────────┘  └───────────┘ └────────────┘
```

---

## 5. Go-to-Market Strategy

### Pre-Launch (Month 1-2: Build)

| Week | Milestone |
|------|-----------|
| 1-2 | Core marketplace: listings, search, cart, checkout |
| 3-4 | Review system + karma points + vendor dashboard |
| 5-6 | Anti-gaming layer + AI review scoring |
| 7-8 | Testing, polish, Founding Vendor onboarding |

### Launch Strategy (Month 3)

**Geography:** Start in Switzerland. Expand to DACH (Germany, Austria) in Month 6, EU in Month 9.

**Vertical strategy:** Launch category-agnostic but seed with 2-3 verticals where trust matters most:
- Artisan / handmade goods
- Sustainable / ethical products
- Specialty food & beverages
- Wellness & natural products

These verticals share a common trait: buyers already pay premium prices and care deeply about authenticity. Review trust is a purchase driver, not a nice-to-have.

**Vendor acquisition — Target: 20 vendors at launch**

| Channel | Method | Target |
|---------|--------|--------|
| Personal network | Jay's Basel contacts — direct outreach | 5 vendors |
| Local markets & fairs | Basel Christmas/spring markets, Markthalle vendors | 5 vendors |
| LinkedIn/Instagram outreach | Swiss artisan and small business communities | 5 vendors |
| Partnership | Swiss artisan associations, trade groups | 5 vendors |
| **Total** | | **20 vendors** |

**Vendor incentive:**
- Founding Vendor badge (permanent, exclusive to first 50)
- Free listings for 12 months
- White-glove onboarding: we photograph products, write first listings
- Early access to token economy (Phase 2)

**Buyer acquisition — Target: 500 users in first 3 months**

| Channel | Method | Target |
|---------|--------|--------|
| Vendor networks | Each vendor promotes to their existing customers | 200 buyers |
| Social media (Meta) | Instagram/Facebook ads targeting Swiss shoppers | 100 buyers |
| Content marketing | Blog: "Why you should get paid for honest reviews" | 50 buyers |
| Referral program | Invite a friend who reviews = both earn 50 pts | 100 buyers |
| Local PR | Basel/Swiss media: "Basel startup pays you for honest reviews" | 50 buyers |
| **Total** | | **500 buyers** |

**Launch campaign: "Your Opinion Has Value"**
- First 100 buyers who write a quality review earn CHF 10 store credit
- Share your review on social → bonus points
- Top reviewer of the month wins a CHF 100 gift card

### Scaling (Month 4-12)

- **Month 4-6:** Optimize based on Phase 1 data. Refine point values, review scoring, anti-gaming
- **Month 6:** Expand to DACH. Add German-language support (primary market: Germany)
- **Month 9:** Expand to EU. Add vendor tools (analytics, promotional tools, bulk upload)
- **Month 12:** Evaluate tokenization readiness against kill gates

---

## 6. Revenue Model

### Phase 1 Revenue Streams

| Stream | Model | Projected (Month 6) | Projected (Month 12) |
|--------|-------|---------------------|----------------------|
| **Transaction fee** | 5% on each sale | CHF 2,500/mo | CHF 8,000/mo |
| **Vendor subscription** | CHF 29/mo basic, CHF 99/mo premium | CHF 1,500/mo | CHF 5,000/mo |
| **Promoted listings** | CHF 5-20/day per listing boost | CHF 500/mo | CHF 2,000/mo |
| **Total** | | **CHF 4,500/mo** | **CHF 15,000/mo** |

**Assumptions:**
- Month 6: 200 MAU, 50 vendors (20 paid), CHF 50K GMV/month
- Month 12: 500 MAU, 100 vendors (50 paid), CHF 160K GMV/month
- Average order: CHF 80
- Conversion rate: 3% of visits → purchase

### Phase 2+ Revenue (Post-Tokenization)

- KDEX trading fees (DEX liquidity provision)
- Staking contract fees
- Premium vendor analytics
- API access for reputation data
- Cross-platform reputation verification fees

---

## 7. Success Metrics & Kill Gates

### Key Metrics (Phase 1)

| Metric | Target (Month 3) | Target (Month 6) | Target (Month 12) | Kill Gate |
|--------|-------------------|-------------------|--------------------|-----------|
| Monthly Active Users | 100 | 200 | 500 | < 50 at Month 6 |
| Vendors (active) | 10 | 30 | 100 | < 10 at Month 6 |
| Reviews per user/month | 1.5 | 2.0 | 2.5 | < 0.5 at Month 6 |
| Review quality avg (AI score) | 0.5 | 0.6 | 0.7 | < 0.4 at Month 6 |
| Monthly revenue | CHF 1,000 | CHF 4,500 | CHF 15,000 | < CHF 1,000 at Month 6 |
| Vendor retention (monthly) | 80% | 75% | 70% | < 40% at Month 6 |
| Buyer repeat purchase rate | 15% | 25% | 35% | < 10% at Month 6 |
| Gross Merchandise Value | CHF 15K | CHF 50K | CHF 160K | < CHF 10K at Month 6 |

### Kill Gates (Hard Stops)

If **any** of these triggers hit, stop and reassess before proceeding to Phase 2:

1. **< 50 MAU at Month 6** — the marketplace isn't attracting users
2. **< 10 active vendors at Month 6** — supply side failed
3. **Review quality < 0.4 avg at Month 6** — positive reinforcement isn't working
4. **< CHF 1,000/mo revenue at Month 6** — business model isn't viable
5. **> 30% of reviews flagged as gaming** — anti-gaming system is overwhelmed
6. **Vendor churn > 60% in any quarter** — vendors don't see value

### Phase 2 Unlock Criteria (ALL must be met)

- [ ] 500+ MAU with 3+ months consistent data
- [ ] CHF 10,000+/mo revenue for 2+ consecutive months
- [ ] Review quality avg > 0.6
- [ ] Legal opinion on KRUNE token classification received
- [ ] FINMA pre-consultation completed
- [ ] Smart contract audit budget allocated (CHF 50-80K)

---

## 8. Competitive Landscape

| Competitor | What they do | Their weakness | Our advantage |
|-----------|-------------|---------------|---------------|
| **Amazon** | Everything marketplace | Fake reviews epidemic, vendor anonymity | Quality reviews rewarded, transparent reputation |
| **Etsy** | Artisan marketplace | Reviews not incentivized, platform takes increasing fees | Active review economy, lower take rate |
| **Trustpilot** | Review platform (not marketplace) | Reviews only, no commerce integration | Reviews + commerce + reputation economy |
| **Poshmark/Vinted** | Peer-to-peer fashion | Limited to fashion, basic reviews | Multi-category, quality-weighted reviews |
| **OpenBazaar** | Decentralized marketplace | Dead — failed at UX and adoption | Centralized UX first, decentralize later |
| **Origin Protocol** | Blockchain marketplace | Too crypto-native, scared off normal users | No crypto in Phase 1, earn trust first |

**Key differentiator:** Nobody pays users for quality reviews with a system that eventually becomes real yield. The closest thing is Amazon Vine (invite-only, product-specific) and Trustpilot (no payment for reviews). KarmaTrade's earned reputation → yield pipeline doesn't exist anywhere else.

---

## 9. Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| **Cold-start: no vendors** | High | Critical | Founding Vendor program, personal outreach, white-glove onboarding, Jay's network |
| **Cold-start: no buyers** | High | Critical | Seed via vendor networks, paid social, launch campaign with real cash incentives |
| **Review gaming at scale** | Medium | High | AI scoring + velocity limits + graph analysis + human review + GPT-detection |
| **Stripe blocks a category** | Low | Medium | Maintain Stripe-friendly categories. Separate high-risk verticals to Phase 2 with crypto payments |
| **Competitor copies model** | Medium | Medium | First-mover advantage, community moat, founding vendor loyalty |
| **FINMA blocks tokenization** | Low | Medium | Phase 1 runs fine without tokens. Points system works standalone |
| **AI review scoring bias** | Medium | Medium | Regular bias audits, transparency reports, appeal process |
| **Revenue below projections** | Medium | High | Kill gates trigger reassessment before overspending |
| **Team too small** | High | Medium | AI-augmented operations, focus on core features, outsource non-critical |

---

## 10. Team & Resources

### Phase 1 Team

| Role | Who | Responsibility |
|------|-----|---------------|
| **Founder / CEO** | Jamil Wenzel | Product vision, vendor acquisition, business development |
| **AI Operations** | Kali + AI agents | Content moderation, review scoring, customer support triage, marketing |
| **Full-stack dev** | TBD (contract or co-founder) | Marketplace development, infrastructure |
| **Design** | TBD (contract) | UI/UX, brand implementation |

### Phase 1 Budget

| Category | Estimate (CHF) |
|----------|----------------|
| Development (contract dev, 6 months) | 40,000-60,000 |
| Design (contract, 2-3 months) | 10,000-15,000 |
| Infrastructure (Vercel, Supabase, Stripe) | 3,000-6,000 |
| AI tooling (Claude API, classifiers) | 3,000-6,000 |
| Marketing (launch campaign, ads) | 5,000-10,000 |
| Legal (entity setup, terms, privacy) | 5,000-10,000 |
| **Total Phase 1** | **66,000-107,000** |

*Note: FINMA token consultation (CHF 30-50K) deferred to Phase 2 preparation.*

---

## 11. Phased Roadmap

```
PHASE 1 — PROVE THE MODEL (Month 1-12)
├── Month 1-2: Build MVP (marketplace + reviews + points)
├── Month 3: Launch with 20 vendors, acquire first 100 buyers
├── Month 4-6: Iterate on review scoring, points economy, anti-gaming
├── Month 6: Expand to DACH, hit 200 MAU target
├── Month 7-9: Add vendor tools, referral program, Q&A
├── Month 10-12: Hit 500 MAU, evaluate kill gates
└── Decision point: proceed to Phase 2 or pivot

PHASE 2 — TOKENIZE (Month 12-24)
├── FINMA consultation + legal opinions
├── Smart contract development (KRUNE + KDEX)
├── Contract audit (Tier 1 auditor)
├── Points → KRUNE migration
├── KDEX token launch + DEX listing
└── Treasury setup + governance framework

PHASE 3 — YIELD ECONOMY (Month 24+)
├── KSHRD staking contract
├── Yield activation (revenue-backed)
├── DAO governance transition
├── Cross-platform reputation API
└── Protocol licensing to other marketplaces
```

---

## 12. Open Questions

These need answers before or during Phase 1:

| # | Question | Owner | Deadline |
|---|----------|-------|----------|
| 1 | Which 2-3 product verticals to seed at launch? | Jay | Before build starts |
| 2 | Contract developer: hire or co-founder? | Jay | Month 1 |
| 3 | TWINT integration via Stripe or direct? | Dev | Month 2 |
| 4 | Review quality AI: build custom or use Claude API scoring? | Dev | Month 2 |
| 5 | Vendor payout schedule: weekly or bi-weekly? | Jay + Finance | Month 2 |
| 6 | Should points have a monetary floor value (e.g., 100 pts = CHF 1)? | Jay + Finance | Month 3 |
| 7 | Multi-language from launch (DE + EN) or English-first? | Jay | Before build starts |
| 8 | Mobile app needed in Phase 1, or responsive web only? | Jay | Before build starts |
| 9 | How to handle cross-border shipping/taxes in DACH expansion? | Jay + Legal | Month 5 |
| 10 | KSHRD: separate token or direct USDC payout? (Deferred from whitepaper) | Jay + Legal | Phase 2 |

---

## 13. Dependencies

| Dependency | Status | Blocker? |
|-----------|--------|----------|
| Domain (karmatrade.net) | Decided | No — needs purchase |
| Stripe account (marketplace mode) | Not started | Yes — required for payments |
| Supabase project | Exists (Kali) — need separate project | No |
| Vercel account | Exists | No |
| Contract developer | Not hired | Yes — required for build |
| Legal entity (GmbH or Einzelfirma) | Existing (That Sky Walker Enterprise) | No — evaluate if separate entity needed |
| Brand assets (logo, design system) | Brand guide exists, no final logo | Partial — need designer |

---

## 14. Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-17 | Initial PRD based on whitepaper v2, board meeting analyses, and go-to-market planning |

---

*This PRD covers the marketplace product. For token economics, see `cka-tradekarma-whitepaper-v2.md`. For operations planning, see `cka-crypto-economy-operations.md`. For brand guidelines, see `cka-tradekarma-brand-marketing.md`.*
