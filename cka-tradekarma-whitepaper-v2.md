# TradeKarma

**White paper, v2 draft**
**March 2026**

**tradekarma.net**

---

## What this is

TradeKarma is a reputation system for e-commerce that pays you for being good.

Write an honest review? You earn a token. Ship on time? Token. Help another buyer figure out a sizing question? Token. These tokens unlock real things: discounts, governance votes, visibility for your shop. Eventually, when paired with an investment token, they generate yield backed by actual platform revenue.

Three tokens, introduced one at a time over roughly two years. We start with plain database points. No wallets, no gas fees, no "connect your MetaMask." If the economics work with a regular database, we put them on-chain. If they don't, we adjust until they do. We don't launch tokens to see if the model works. We prove the model works, then launch tokens.

The part I keep coming back to: you can't buy KarmaRune. It only enters the system through participation. A whale with $10 million can buy all the investment tokens they want, but without months of earned reputation, they can't access the yield. That's the mechanic everything else is built on.

---

## Contents

1. [The problem we're solving](#1-the-problem-were-solving)
2. [How we think about it](#2-how-we-think-about-it)
3. [Three tokens, three jobs](#3-three-tokens-three-jobs)
4. [From one token to three](#4-from-one-token-to-three)
5. [How the staking works](#5-how-the-staking-works)
6. [How earning works](#6-how-earning-works)
7. [Where the money comes from](#7-where-the-money-comes-from)
8. [Gaming and fake accounts](#8-gaming-and-fake-accounts)
9. [Technical choices](#9-technical-choices)
10. [Governance](#10-governance)
11. [Legal situation](#11-legal-situation)
12. [Who tried this before](#12-who-tried-this-before)
13. [Roadmap](#13-roadmap)
14. [Team](#14-team)
15. [What we haven't figured out yet](#15-what-we-havent-figured-out-yet)
16. [Glossary](#16-glossary)

---

## 1. The problem we're solving

You can buy 500 five-star reviews on Amazon for a few hundred dollars. A buyer who spends 45 minutes writing a detailed, honest, genuinely helpful review gets nothing for it. Maybe a badge. Maybe not even that.

This has been true for over a decade and nobody has fixed it. The incentives are broken at a structural level: there is no cost to faking reviews and no reward for writing real ones.

It gets worse. A vendor who builds 10 years of excellent reviews on Amazon starts from zero on Etsy. Your reputation is locked inside whatever platform you happened to build it on. There's no portable proof that you're trustworthy. Switch platforms and you're a stranger again.

The standard response is punishment. Platforms catch bad actors, ban them, remove their reviews. This creates an arms race. Sellers optimize to avoid detection, not to be genuinely good. The entire system is adversarial, and it shows.

We want to try something different. Instead of building a better punishment system, we want to build a reward system. Make the honest review worth something. Make the reliable vendor's reputation into an asset they actually own.

---

## 2. How we think about it

Token economies for behavior change have been studied since the 1960s. The research is clear: positive reinforcement creates lasting habits more reliably than punishment. People optimize for what gets rewarded.

We're applying that to e-commerce. The idea is simple. The execution is not, which is why we're being careful about it.

A few things we decided early that shaped everything:

KarmaRune, the reputation token, can never be purchased. This is the one rule we won't compromise on. If reputation can be bought, the system is just pay-to-win with extra steps. Every feature, every mechanic, every token interaction was designed around this constraint.

We're starting with a plain points system. No blockchain. We've seen too many projects launch tokens before they have a working product. The sequence matters: build the marketplace, run the points system, see if people actually change their behavior, tune the numbers based on real data, then tokenize. If the points system doesn't improve review quality and marketplace health, no amount of blockchain will fix that.

Yield comes from revenue, or it doesn't come at all. The treasury that backs our yield token is funded by transaction fees and vendor subscriptions. If the marketplace doesn't generate enough revenue, yield doesn't activate. We'd rather have an honest "yield is not available yet" than a number that looks good on paper but is funded by new investors buying in. We all saw what happened to OlympusDAO.

We're building in Basel, which means FINMA. Switzerland has one of the clearer regulatory frameworks for tokens, but "clearer" still means we need a lawyer to confirm every token classification before we issue anything. That costs CHF 30,000-50,000 across all phases. We've budgeted for it.

The platform starts centralized. I know "centralized" is a dirty word in crypto, but a three-person team cannot govern by DAO. We retain control during the build phase, document every decision transparently, and move toward community governance as the user base grows and demonstrates it can handle it. The DAO is earned, same as KRUNE.

---

## 3. Three tokens, three jobs

Most token projects use one token for everything. It's supposed to be a currency, a reward, a governance vote, and an investment vehicle. These goals conflict with each other. People hoard a utility token hoping it appreciates instead of spending it, which breaks the utility.

We split the functions:

| Token | Ticker | What it does | How you get it |
|-------|--------|-------------|----------------|
| KarmaRune | $KRUNE | Reputation. Proof you participated and contributed. | Earned only. Reviews, good service, referrals. |
| KarmaDex | $KDEX | Investment. Governance. The token you buy if you believe in the project. | Buy on exchanges. |
| KarmaShard | $KSHRD | Yield. The thing you get when earned reputation meets invested capital. Redeemable for USDC or KDEX. | Stake KRUNE + KDEX together. |

KRUNE is your track record. It accumulates as you do good things on the platform. Write a detailed review with photos on a $100 purchase, earn 30 KRUNE. Post a generic one-liner on the same product, earn 7. Ship an order on time, earn KRUNE scaled to the order value. Refer someone who's still active three months later, earn 30. The earning mechanics are logarithmic, quality-weighted, and capped — full details in Section 6. You can spend KRUNE on platform perks (discounts, visibility boosts) or save it for staking.

KDEX is what investors interact with. Fixed supply. Trades on DEXs. Gives you governance votes. If TradeKarma grows, demand for KDEX grows. This is deliberately separated from the reputation layer so that price speculation doesn't mess up the behavioral incentives.

KSHRD is the bridge between the two. To generate it, you lock your earned KRUNE alongside purchased KDEX in a staking contract. You need both. A hedge fund that buys $5 million of KDEX but has never used the platform can't stake. A power user with 100,000 KRUNE but no skin in the game financially can't stake either. Both sides of the equation are required. KSHRD is redeemable for either USDC or KDEX from the treasury, funded by real platform fees. Choosing KDEX keeps the value inside the system and earns you a bonus — the mechanics are in Section 5.

I'll be honest: the board is split on whether KSHRD needs to exist as a separate token. The CFO and Critic think we should just pay USDC directly to qualifying stakers and skip the intermediary. Strategy argues KSHRD creates useful flexibility for treasury management and future composability. We're deferring the decision until our Swiss lawyer weighs in, because KSHRD-to-USDC redemption sits in a regulatory grey area under FINMA that could require a banking license. The anti-whale mechanic works the same either way.

---

## 4. From one token to three

We're not launching three tokens at once. That would be reckless. We phase them in, and each phase has to earn the next one.

### Phase 1: karma points, no blockchain (year 1)

Year one is a regular e-commerce platform with a points system. Users see "Karma Points" in their account. They earn them for the things we want to encourage. They spend them on benefits. Everything runs on Postgres.

This is intentionally boring from a crypto perspective. It looks like a loyalty program. Good. We're testing whether positive reinforcement actually changes behavior on a marketplace. Does review quality go up? Do vendors respond faster? Do people stick around longer? The data from this phase informs every decision that follows.

We can adjust earning rates and spending options in minutes. Try giving more points for reviews with photos. See if it works. Roll it back if it doesn't. This kind of iteration is nearly impossible once the economics are on-chain and require governance votes and contract upgrades.

Phase 2 doesn't happen until we hit 500 active monthly users with 3+ months of consistent engagement data, and a legal opinion confirming our token classification.

If this phase fails, we learned something for about CHF 120,000 instead of CHF 500,000+. That's the whole point of phasing.

### Phase 2: two tokens on-chain (months 6-18)

KarmaRune migrates from database to ERC-20 on Base. Users get wallets (Coinbase Smart Wallet, no seed phrases). Their accumulated points convert to on-chain KRUNE. The migration is a marketing event: "your reputation is now yours, portable, on-chain."

KDEX launches alongside it. Fixed supply, distributed through community allocation, team vesting, liquidity provision, and a small investor round. It trades on Uniswap (Base).

The two tokens coexist but don't mechanically interact yet. Both carry governance power. The marketplace generates revenue. The revenue accumulates in a multi-sig treasury. We watch whether on-chain KRUNE behaves the same as off-chain points, whether there's organic KDEX demand, and whether the treasury grows.

### Phase 3: yield goes live (month 12+)

KSHRD generation turns on. Staking is available. Users pair earned KRUNE with purchased KDEX, lock them in the staking contract, and start generating KSHRD redeemable for USDC.

But we put a hard gate on this. The CFO modeled it: at 100 users, the yield pool is about $500 per month. Split among stakers, that's roughly $20 each. Nobody's going to change their behavior for $20 a month, and activating yield at those levels just invites gaming. We need 500-1,000 active users generating consistent fee revenue before yield makes economic sense.

Each phase has to justify the next. If points don't change behavior, no blockchain. If the marketplace doesn't generate revenue, no yield. The tokens earn their existence.

```
Year 1                   Year 1-2                  Year 2+
Karma Points             $KRUNE on-chain           $KSHRD yield active
(database, no crypto)    $KDEX launches            Staking: KRUNE + KDEX
                         Treasury accumulates      Treasury pays real yield

1 token (points)    -->  2 tokens (on-chain)  -->  3 tokens (full economy)
Prove behavior      -->  Prove investment      -->  Prove yield
```

---

## 5. How the staking works

Say you've been using TradeKarma for six months. You've written reviews, helped other buyers in the forum, referred a few friends. You've accumulated 500 KRUNE. You also believe in the project, so you bought 500 KDEX on Uniswap.

You go to the staking page and lock both into the staking contract. Over the following weeks, your staked position generates KSHRD. You can redeem KSHRD for USDC or KDEX from the platform treasury whenever you want (more on the two paths below).

The person who bought $100,000 of KDEX last week but has never written a review? They can't stake. They don't have the KRUNE. The person who's earned 50,000 KRUNE through years of helpful participation but doesn't want to invest money? They can't stake either. You need both halves.

That's the whole trick.

### What ratio?

The naive answer is 1:1. Stake 500 KRUNE with 500 KDEX. Simple.

The problem: when KDEX is cheap, users do the bare minimum reputation work to unlock staking. When KDEX is expensive, legitimate participants can't afford to stake. The 1:1 ratio ties two fundamentally different types of value (labor and money) at an arbitrary rate.

The better approach adjusts the KDEX requirement based on price:

```
Required KDEX = KRUNE amount x (target dollar value / current KDEX price)
```

This keeps the real-money commitment roughly constant. Whether KDEX is $0.50 or $5, you're putting up about the same dollar value alongside your earned KRUNE. The reputation requirement doesn't change, only the financial one adjusts.

### Burning

There's a second way to create KSHRD: permanently destroy 10,000 KRUNE to mint 1 KSHRD. The ratio is steep on purpose. This path exists for people who want long-term KSHRD without ongoing staking, and it creates a permanent deflationary drain on KRUNE supply. Every KSHRD minted this way represents months of positive actions that are now removed from circulation forever.

### Redemption paths

You've staked your KRUNE and KDEX, generated some KSHRD. Now what?

The original plan: redeem KSHRD for USDC from the treasury. Cash out. But there's an obvious problem with making USDC the only exit. Every redemption drains the treasury. The money leaves the system completely. At small scale, that's fine. At larger scale, you've built an economy with a one-way valve — value flows in through fees, converts to KSHRD, and leaks out as USDC.

So we're adding a second option: redeem KSHRD for KDEX instead.

When you redeem, you pick:

| Path | Fee | What you get |
|------|-----|-------------|
| KSHRD → USDC | 5% | Dollar value, sent to your wallet |
| KSHRD → KDEX | 2% | KDEX at market rate + 5% premium, plus a small KRUNE bonus |

For the KDEX path, the treasury swaps your KSHRD value for KDEX at market rate on Uniswap, adds a 5% premium, and sends it to your wallet. On top of that, you receive a KRUNE bonus worth roughly 10% of the KSHRD value.

Why would anyone pick KDEX over cash? Lower fee saves 3%. The premium gives you more value per KSHRD. And the KRUNE bonus partially reloads your staking position. If you were planning to keep staking anyway, the USDC path means cashing out, paying a 5% fee, buying KDEX separately, and re-staking. The KDEX path cuts that down to one step.

The KRUNE bonus is the part I went back and forth on. It creates a loop:

```
Earn KRUNE → stake with KDEX → generate KSHRD → redeem for KDEX + bonus KRUNE → stake again
```

If the bonus is too generous, someone with deep pockets and enough KDEX could farm KRUNE indefinitely without ever using the marketplace. That kills the one rule we said we wouldn't break.

So the bonus is deliberately small, and it comes with friction. KRUNE earned through KDEX redemptions sits in a 30-day cooldown before it can be staked. You can spend it on platform perks right away — discounts, visibility boosts, whatever — but you can't lock it back into the staking contract for a month. There's also a quarterly cap per user. Redeem every week if you want; the bonus still tops out.

Where does the bonus KRUNE actually come from? Not from minting. When users spend KRUNE on discounts, a portion gets recaptured rather than burned. That recaptured pool feeds the redemption bonus. If the pool runs dry, bonuses pause until it refills. No new KRUNE enters circulation for this.

The CFO modeled it at 1,000 active users with 30% choosing the KDEX path. The treasury holds onto about $1,400 more per month in USDC. Modest on its own, but it compounds over quarters. The KDEX purchases also put steady buy pressure on the market, which is a side effect rather than a goal.

Here's what I didn't expect: this might help with the FINMA problem from Section 11. The board's worry was that KSHRD-to-USDC looks like a banking function — you're basically running a cash-out window. KSHRD-to-KDEX is a token-to-token conversion, different regulatory territory entirely. If we make KDEX the default redemption and USDC the premium option (higher fee, maybe a minimum holding period), we might not need the banking license at all. Our lawyers haven't confirmed this yet, but it's a thread worth pulling.

### Token flow

```
Positive actions (reviews, good service, referrals)
    |
    v
$KRUNE (earned, never bought)
    |
    +--- Spend on platform perks --> KRUNE partially burned, partially recaptured
    |
    +--- Lock in staking contract (requires matching KDEX)
    |         |
    |         v
    |    $KSHRD generated over time
    |         |
    |         +--- Redeem for USDC (5% fee, no bonus)
    |         |
    |         +--- Redeem for KDEX (2% fee, +5% KDEX premium, +10% KRUNE bonus)
    |                   |
    |                   +--- KDEX goes to your wallet (re-stake or trade)
    |                   +--- Bonus KRUNE: 30-day cooldown, then stakeable
    |
    +--- Burn 10,000 KRUNE --> mint 1 KSHRD (permanent destruction)

$KDEX (bought on market, or received via KSHRD redemption)
    |
    +--- Lock in staking contract (paired with KRUNE)
    +--- Vote on governance proposals
    +--- Trade freely

Recaptured KRUNE pool (from platform perk spending)
    |
    +--- Feeds KDEX-path bonus KRUNE
    +--- Pauses when pool is empty
```

---

## 6. How earning works

The earlier drafts of this paper had flat numbers — 10 KRUNE for a review, 20 for a referral, regardless of context. That was always a placeholder. Here's the actual framework. The specific values will get adjusted during Phase 1 based on real data, but the structure is set.

### Purchase-scaled base earning

Flat rates don't make sense. A review on a $15 phone case and a review on a $600 espresso machine shouldn't earn the same KRUNE. The person reviewing the espresso machine is helping buyers make a much bigger decision. But we can't go linear either — if it's 1 KRUNE per $10 spent, someone dropping $5,000 on a single order grinds out more reputation in one purchase than a regular user earns in months. That's buying reputation with a credit card, just with extra steps.

So the curve is logarithmic. Bigger purchases earn more, but each additional dollar of purchase price earns less than the one before it:

| Purchase amount | Base KRUNE |
|---|---|
| Under $10 | 0 (minimum threshold) |
| $10 | 5 |
| $25 | 8 |
| $50 | 12 |
| $100 | 15 |
| $250 | 20 |
| $500 | 25 |
| $1,000+ | 30 (hard cap) |

The hard cap is non-negotiable. Whether you spend $1,000 or $10,000, you earn 30 base KRUNE from the purchase itself. Past a certain amount, spending more money doesn't make your review more valuable to other buyers.

### Review quality multiplier

Base KRUNE is just the starting point. What you actually receive depends on what you put into the review:

| Review quality | Multiplier |
|---|---|
| Under 50 words, generic ("great product, fast shipping") | 0.5x |
| 50-200 words, mentions specifics | 1x |
| Includes photos | 1.5x |
| Photos + real usage context (sizing info, comparison to alternatives, durability after X weeks) | 2x |
| Video review | 2.5x |

A $100 purchase with a detailed photo review: 15 x 2.0 = 30 KRUNE. The same purchase with "5 stars, love it": 15 x 0.5 = 7 KRUNE. The review that helps someone decide whether to buy earns four times what the throwaway review earns.

The quality scoring is AI-assisted but not opaque. We're looking for specifics — did you mention how the product actually performed? Did you compare it to something else? Did you note anything a future buyer should know? The scoring criteria are public. Users can see why their review got the multiplier it got.

### Delayed helpfulness bonus

This is the mechanic I like most, because it's nearly impossible to game.

When you submit a review, you earn your base KRUNE immediately. Thirty days later, the system checks how other buyers interacted with your review:

- 5+ helpful votes: +25% of your original KRUNE
- 15+ helpful votes: +50%
- 50+ helpful votes: +100% (doubles your original earning)

To game this, you'd need dozens of fake accounts each making real purchases, then coordinating "helpful" votes on your review over a month-long window. The cost of that attack far exceeds what you'd earn. And the mechanic rewards the exact behavior we want: writing something that actually helped a real person make a real decision.

### First-review premium

Every marketplace has the same gap: popular products get hundreds of reviews, niche products get zero. The buyer considering that niche product has nothing to go on.

We fix this with a coverage multiplier:

| Existing reviews on the product | Multiplier |
|---|---|
| 0-2 reviews | 3x |
| 3-10 reviews | 1.5x |
| 10+ reviews | 1x |

The person who reviews a product nobody else has touched earns three times what reviewer #200 earns on a bestseller. This creates a self-balancing effect. KRUNE flows toward the parts of the marketplace that need coverage the most. As reviews fill in, the premium drops, and the earning incentive shifts to the next underserved product.

We're considering extending this to entire categories too. If the platform has strong review coverage in electronics but thin coverage in home goods, every review in home goods gets a temporary category multiplier. Recalculated weekly.

### Consistency streaks

We want people who show up regularly, not someone who blasts 20 reviews on a Saturday and vanishes for three months.

| Consecutive weeks with at least one qualifying action | Multiplier |
|---|---|
| Weeks 1-4 | 1x |
| Weeks 5-12 | 1.1x |
| Weeks 13-26 | 1.2x |
| Week 27+ | 1.3x (cap) |

Miss a week, drop one tier. Not to zero — that would feel punitive and people would give up. Just one step back. A user who's been consistent for six months and misses one week drops from 1.3x to 1.2x. Manageable. The streak rewards a pattern of sustained participation, which is exactly the behavioral profile we want in the staking pool.

### Vendor earning

Vendors earn KRUNE through how they run their shop, not through how much they sell. We don't want vendors gaming for volume; we want them treating customers well.

- **Shipping on time:** Same log curve as buyer purchases, but the cap is lower (max 15 KRUNE per order). Reliable fulfillment earns steadily.
- **Fast customer response** (reply within 4 hours during business hours): 5 KRUNE per interaction, max 10 per day. Enough to matter, capped so you can't farm it with fake inquiries.
- **Clean dispute resolution** (resolved without platform escalation): 20 KRUNE. Both sides walked away satisfied, nobody had to file a complaint. That's the behavior we're paying for.
- **Rating streak:** Maintain a 4.5+ average over 30 consecutive days, earn a one-time 50 KRUNE bonus. Resets after each payout. Consistent quality over time.
- **Trust ramp:** New vendors earn at 50% rate for their first 60 days. Prevents create-ship-farm-abandon shop accounts.

### Referrals reworked

The original flat 20 KRUNE for a referral is too simple. Sharing a link and getting someone to click "sign up" costs nothing and proves nothing. We're tying referral rewards to proof the referred user is real:

- Referred user signs up: 0 KRUNE
- Referred user makes their first verified purchase: 10 KRUNE
- Referred user is still active after 90 days: 20 KRUNE
- Cap: 5 referral bonuses per month

The reward triggers on evidence that the referral was genuine, not on the act of sharing a link.

### How it all stacks

Every earning event runs through the same formula:

```
Final KRUNE = base_amount × quality_multiplier × coverage_bonus × streak_multiplier
```

With hard caps on daily (50 KRUNE) and weekly (200 KRUNE) earnings per user. Even if every multiplier hits its maximum, there's a ceiling. The exact caps need Phase 1 data to confirm — 200/week is our starting assumption, and we expect to adjust it more than once in the first year.

### What we're still figuring out

**Should vendor and buyer KRUNE be distinguishable?** A vendor who earned 10,000 KRUNE from shipping reliably has a different reputation profile than a buyer who earned the same from reviews. They're both good actors, but in different ways. We're tracking the source of each KRUNE earning from day one, even if we don't differentiate them at the staking layer yet. The data might matter later.

**Cross-review validation.** If your review says "runs small, order a size up" and 15 subsequent buyers confirm that, should you get a retroactive accuracy bonus? Conceptually, yes. Technically, it requires matching unstructured review text against purchase/return data, which is non-trivial. Parking this for Phase 2.

---

## 7. Where the money comes from

I want to be direct about this because most crypto white papers are vague here and that vagueness hides a lot of sins.

KSHRD yield is funded by platform revenue. Transaction fees, vendor subscriptions, premium features. Actual money that actual people paid for actual services. If nobody is trading on the marketplace, the yield pool is empty and KSHRD doesn't generate.

Revenue sources:

| Source | Rate |
|--------|------|
| Transaction commission on trades | 1-3% |
| Vendor listing subscriptions | CHF 29-199/month |
| Premium features (analytics, boosts, badges) | Variable |
| Fee on KDEX swaps | 2-5% |
| Fee on KSHRD redemption | 5% (USDC path) / 2% (KDEX path) |
| Protocol fees from external platforms (Phase 3) | 2% of minted KRUNE |

How revenue gets split depends on where we are:

| Stage | Operations | Yield pool | KDEX buyback | Reserve |
|-------|-----------|-----------|-------------|---------|
| Under 500 users | 70% | 0% | 10% | 20% |
| 500-2,000 users | 45% | 30% | 15% | 10% |
| Over 2,000 users | 35% | 35% | 20% | 10% |

Note that the yield pool is 0% until we pass 500 users. This is deliberate.

### The numbers, honestly

| Active users | Monthly revenue | Yield pool (35%) | Per staker/month |
|-------------|----------------|-------------------|-----------------|
| 100 | ~$1,400 | ~$500 | ~$20 |
| 500 | ~$6,900 | ~$2,400 | ~$19 |
| 1,000 | ~$13,800 | ~$4,800 | $19-28 |
| 10,000 | ~$137,500 | ~$48,000 | $19-38 |

$20 a month won't change anyone's life. At small scale, the yield is unimpressive. That's fine. We're not marketing yield. We're building a marketplace where yield becomes available as a natural consequence of real economic activity.

The self-balancing part: if KDEX price rises, more people stake, yield per person drops, some unstake, yield concentrates. Standard supply-demand. No magic.

### When things go wrong

If revenue drops to zero, the yield pool empties and no new KSHRD generates. Existing KSHRD retains whatever treasury backing remains. The marketplace keeps working. KRUNE keeps working. The token economy is a layer on top of a functional business, not the business itself. If you strip away all three tokens, there's still a marketplace where people buy and sell things. That's the base case, and it has to be viable on its own.

---

## 8. Gaming and fake accounts

This is the problem that could kill the whole thing.

If someone can create 100 fake accounts, post fake reviews on their own products, and farm KRUNE, then the "earned reputation" gate is meaningless. Every defense we've designed works together, but none of them is bulletproof alone.

Vendors go through KYC. Non-negotiable. If you're selling products, we need to know who you are. Buyers get a lighter touch: phone and email verification, with optional KYC to unlock higher earning limits. We'll integrate decentralized identity (Gitcoin Passport or similar) as supplementary verification.

KRUNE only comes from reviewing verified purchases above a minimum dollar amount. You can't buy a $0.01 item and review it 500 times.

We run graph analysis on trading patterns. If accounts A, B, and C only transact with each other and always leave five-star reviews, that's a flag. Circular trading and mutual review rings are detectable.

Earning is velocity-limited. Daily and weekly caps. Diminishing returns on the same type of action. Even if you create 100 accounts, each one earns slowly.

AI scores review quality. A one-word "great!" earns almost nothing. A detailed, specific review with photos earns meaningfully more. This raises the cost of farming because generating convincing fake reviews at scale takes effort.

New accounts earn at reduced rates. Trust accumulates over time. This makes it expensive to create-and-burn throwaway accounts.

For edge cases, high-KRUNE users can serve as a community jury, reviewing flagged content that the automated systems can't resolve.

No system is gaming-proof. What we're optimizing for is making honest participation easier and cheaper than gaming. If an honest hour of activity earns more KRUNE than a dishonest hour, the system works. If it doesn't, we need to rethink the economics before we tokenize.

---

## 9. Technical choices

### Why Base

We're deploying on Base, Coinbase's Ethereum L2. Transactions cost about $0.01 each. Swiss users can buy KDEX through Coinbase with a bank transfer. Coinbase's Smart Wallet means users don't need to manage seed phrases. They get a wallet tied to their email. The crypto part is invisible to people who don't want to think about it.

Base inherits Ethereum's security through optimistic rollups. The developer tooling is standard Solidity/EVM. Large ecosystem. Easy to find auditors.

We considered Arbitrum (similar, slightly more mature), Polygon (cheaper but weaker security model), and Solana (different programming model, different ecosystem). Base won because of the Coinbase fiat on-ramp and Smart Wallet. Getting non-crypto-native marketplace users to create wallets is the hardest UX problem in this project. Smart Wallet mostly solves it.

### Contracts

```
KarmaRune.sol        - ERC-20, mint/burn, authorized minting only
KarmaDex.sol         - ERC-20, fixed supply
KarmaShardVault.sol  - Staking: lock KRUNE + KDEX, mint KSHRD
KarmaShardBurn.sol   - Burn 10,000 KRUNE, mint 1 KSHRD
Treasury.sol         - Multi-sig, fee collection, KSHRD redemption
Governance.sol       - Snapshot voting, timelock execution
ReputationOracle.sol - Cross-platform reputation queries (Phase 3)
```

Contracts are upgradeable (proxy pattern) during Phase 2. The founder controls upgrades initially. Control transfers progressively to a DAO timelock. Full immutability happens in Phase 3, once the system has run for 2+ years without incidents and the community votes for it with a 75% supermajority.

Security: tier-1 audit before mainnet, bug bounty from day one, multi-sig treasury (3-of-5 signers), circuit breakers for emergencies, no admin mint function, all contracts open-source and verified.

### The protocol vision

Long term, we want other marketplaces to plug into TradeKarma. An open-source SDK lets any platform mint KRUNE for its users' positive actions. Reputation earned on one marketplace is recognized on another. We charge a 2% protocol fee on externally minted KRUNE and a per-query fee for reputation lookups.

This is how TradeKarma goes from being a marketplace to being a protocol. We're not there yet, and we won't pretend to be. This is a year 3-5 goal.

---

## 10. Governance

In Phase 2, the DAO is limited. Token holders vote on earning rates, vendor categories, marketing budget allocation, and feature priorities. I retain control over contract upgrades, treasury withdrawals, and terms of service. A DAO run by 200 people in year one would be governance theater.

Voting weight: 1 staked KRUNE = 1 vote, 1 KSHRD = 3 votes (rising to 10 in Phase 3). Quorum at 10%. Voting window is 7 days. We use Snapshot for off-chain voting with on-chain execution through a timelock.

In Phase 3, the DAO takes over everything. An elected Protocol Council handles day-to-day execution. I shift from operator to protocol steward.

The conditions for full handover are strict: 2+ years of stable operations, zero critical security incidents, the DAO has successfully governed for at least a year, the treasury covers expenses for 6+ consecutive months, and the community approves the transition with a 75%+ vote. We're not handing the keys over until the system has proven it can run without us.

---

## 11. Legal situation

We're in Switzerland. That's good. FINMA has a clearer token classification framework than most regulators. But "clearer" is relative.

KRUNE is designed as a utility token. It provides access to platform features. The platform has to be live and functional when we issue it. Our points-first approach satisfies this since the economy is already running when we tokenize. No ICO, no token sale. KRUNE is only earned through usage.

KDEX is a payment/governance token. Subject to anti-money-laundering rules. May need money transmitter considerations depending on how it's used. Needs legal review.

KSHRD is the complicated one. Redeeming it for USDC from a treasury might look like a banking function to FINMA. Several board members flagged this as potentially requiring a banking license. This is why KSHRD doesn't launch without explicit legal clearance. The fallback plan is simple: drop KSHRD, pay USDC directly to qualifying stakers.

We're budgeting CHF 30,000-50,000 for legal opinions across all phases. We have candidates at MME and Walder Wyss. This is a blocking dependency, meaning we won't issue any token without the lawyer's sign-off, even if the tech is ready.

---

## 12. Who tried this before

We're not the first project to use multiple tokens or paired staking. Here's what happened to the ones that came before us:

Curve runs a three-token system (CRV, veCRV, 3CRV) with lock-based yields funded by real trading fees. It works. $2B+ in TVL. But Convex ended up controlling over half the governance, which created its own problems. Lesson: real revenue is non-negotiable, and governance concentration happens faster than you'd think.

Axie Infinity had SLP (earned by playing) and AXS (governance). SLP crashed 98%. It had no cap on minting and only one meaningful sink (breeding). When growth slowed, everyone dumped SLP. Lesson: an earn token with one sink and no emission cap will hyperinflate.

STEPN ran a similar dual-token model. GST crashed 98% in two months. Same story: when new user growth stopped, the sell pressure from existing earners overwhelmed everything. Lesson: the earn rate has to be sustainable independent of growth.

Radiant Capital is the closest mechanical precedent to what we're building. You earn RDNT, pair it with ETH in a liquidity position, and the combined stake generates real fee yield. The mechanic worked as designed. Then the protocol got hacked. Twice. For $57 million total. Lesson: the economics are secondary to security. Get the audit right.

OlympusDAO ran a three-token rebase system that offered 8,000% APY. It crashed 97.7%. In a post-mortem survey, 67% of users said it was a Ponzi. They were right. The yield came from new investors, not from revenue. Lesson: if you can't point to the specific revenue stream funding your yield, you don't have a yield, you have a time bomb.

Our design is closest to Radiant's. The earned-reputation-plus-invested-capital staking mechanic is proven. The risk is smart contract security, which is why we're spending serious money on audits.

---

## 13. Roadmap

| When | What happens |
|------|-------------|
| Months 1-3 | Legal entity, FINMA consultation, hire blockchain dev, design marketplace architecture |
| Months 4-6 | Marketplace live: listings, checkout, fiat payments. KRUNE points system running. |
| Months 7-9 | 10+ vendors onboarded. First real transactions. Anti-gaming v1 deployed. |
| Months 10-12 | 500+ MAU target. Analyze KRUNE engagement data. Make the tokenization call. |
| Months 13-18 | KRUNE migrates on-chain (Base). KDEX launches. Smart contracts audited. |
| Months 19-24 | DAO governance v1. Treasury accumulating. 5,000+ MAU target. |
| Months 25-36 | 200+ vendors across multiple categories. 15,000 MAU target. |
| Months 37-42 | KSHRD staking goes live (if legal and economic conditions are met). First yield. |
| Months 43-48 | Protocol SDK open-sourced. First external platform integration. |
| Months 49-60 | Full DAO governance. Contract ownership transferred. Protocol self-sustaining. |

These are targets, not promises. If Phase 1 takes 18 months instead of 12, we take 18 months. Rushing to hit a roadmap deadline is how projects ship insecure contracts.

---

## 14. Team

Year 1 is three people and a fleet of AI agents.

I (Jamil) handle product, business development, vendor relationships, and legal. One contracted blockchain/full-stack developer builds smart contracts and backend. One contracted frontend developer builds the marketplace UI.

AI agents handle customer support (80%+ resolution without human involvement), content moderation, review quality scoring, social media, and analytics. This lets a three-person team do the work that would traditionally need 8-12 people. The cost difference is dramatic: AI operations cost roughly CHF 13,000-26,000 per year versus CHF 340,000-450,000 for equivalent Swiss hires. That savings funds development and legal.

Humans have final say on anything involving money, disputes over CHF 100, banning users, legal responses, or smart contract changes. AI recommends, humans decide. There are weekly audit checkpoints where I review random samples of AI decisions.

Years 2-3: team grows to 6-8. CTO hire, community manager, marketing lead, advisory board (tokenomics, e-commerce, regulatory). AI agents expand into dispute triage, fraud detection, and treasury monitoring.

Years 4-5: 10-15 people, protocol-focused. Engineering team, DAO facilitation, multi-jurisdiction legal, marketing/BD. AI runs daily operations. Humans handle strategy and trust.

---

## 15. What we haven't figured out yet

I'd rather list the open questions than pretend we have all the answers.

**Two tokens or three.** The board is genuinely split. The anti-whale staking works with two tokens (KRUNE + KDEX, direct USDC yield) just as well as with three. KSHRD adds composability but also regulatory complexity and liquidity fragmentation. We're waiting for our lawyer's opinion.

**Exact KRUNE numbers.** Section 6 lays out the earning framework (log-scaled base, quality multipliers, streaks, caps), but every specific number in those tables is an educated guess. Phase 1 exists to find out which ones are wrong. We expect to adjust rates multiple times in the first year, especially the daily/weekly caps and the first-review premium.

**What happens to staked KRUNE after unstaking.** Does it come back to you? Get burned? Enter a cooldown period? Each option has different implications for gaming. Haven't decided.

**Lock-up duration for staking.** Too short and there's no commitment. Too long and people won't participate. We're thinking about a tiered system (30, 90, 180 days) with better KSHRD rates for longer locks, but the exact numbers aren't set.

**Which sinks keep KRUNE balanced.** Spending on discounts burns KRUNE. Minting KSHRD burns KRUNE. But we might need more: dispute resolution deposits, listing boosts, premium access. The number and depth of these sinks determines whether KRUNE inflates or stays stable.

**The domain.** Some planning docs say tradekarma.net, some say karmatrade.net. We need to pick one and commit before anything goes public.

---

## 16. Glossary

| Term | What it means |
|------|--------------|
| KarmaRune ($KRUNE) | Reputation token. Earned through positive marketplace actions. Can't be bought. |
| KarmaDex ($KDEX) | Investment and governance token. Freely tradeable. Fixed supply. |
| KarmaShard ($KSHRD) | Yield token. Generated by staking KRUNE + KDEX. Redeemable for USDC or KDEX (KDEX path has lower fee and earns bonus KRUNE). |
| Staking | Locking KRUNE + KDEX in a smart contract to generate KSHRD. |
| Burning | Permanently removing tokens from circulation. Irreversible. |
| Treasury | On-chain fund that backs KSHRD redemptions. Funded by platform fees. |
| DAO | Community governance. Token holders vote on platform parameters. |
| Base | Coinbase's Ethereum L2. Low fees. Smart Wallet integration. |
| FINMA | Swiss Financial Market Supervisory Authority. |
| Multi-sig | Wallet that needs multiple people to approve transactions. Ours is 3-of-5. |
| Sybil attack | Creating fake identities to farm reputation. Our biggest threat. |
| GMV | Gross Merchandise Volume. Total value of goods sold. |
| MAU | Monthly Active Users. |

---

This is a draft. Not a prospectus. Not investment advice. No tokens have been issued. The designs described here will change based on legal review, community feedback, and what we learn in Phase 1. The only thing we're committed to is the sequence: prove first, tokenize second.

Review by Swiss legal counsel is required before any token issuance.

---

*TradeKarma*
*Basel, Switzerland*
*March 2026*
