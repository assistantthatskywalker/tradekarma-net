# TradeKarma

## Reputation earned through verified commerce

Whitepaper v4 — 7 September 2026 · Basel, Switzerland

## Status and scope

TradeKarma is a development-stage reputation and rewards project. The deployed website describes the proposal and offers a waitlist when its database integration is configured. It is not a working marketplace, investment offering, or live staking application.

The repository contains a TypeScript reference library, Solidity contracts, tests, deployment tooling, and documentation. It does not establish customer traction, profitable operations, regulatory approval, or independently audited mainnet deployments. Historical whitepapers and the original business plan are superseded by this document and docs/BUSINESS-MODEL.md.

## The hypothesis

Useful reviews, reliable fulfillment, and helpful answers can improve commerce. TradeKarma proposes rewards for verified contributions and asks merchants to pay for measurable benefits: lower fraud/support cost, better purchase decisions, and repeat customers.

These benefits must be measured against a control group. Rewarding activity can also encourage spam, collusion, and positive-review bias. Rewards should depend on verified usefulness, not favorable sentiment. No behavioral effectiveness or market-size claim is established by the current code.

## Token roles and launch conditions

| Instrument | Proposed role | Current implementation and limits |
| --- | --- | --- |
| KRUNE | Non-transferable reputation | Authorized minting and holder-transfer rejection exist in Solidity. There is no burn/spending path. Issuer trust and account-control sales remain risks. |
| KDEX | Optional capital participation and governance | Fixed genesis supply ERC-20. No implemented on-chain governance or vesting. Supply and distribution must be specified before issuance. |
| KSHRD | Optional transferable claim on funded rewards | Minted at staking exit, redeemable for USDC. Adoption requires a demonstrated need for a separate claim token and legal clearance. |

Reputation and spendable loyalty credits are separate concepts. Perk redemption must not burn KRUNE while staking relies on its non-decreasing balance. A separate loyalty-credit model is proposed but is not implemented here.

Fixed supply does not guarantee demand, price appreciation, or investment returns. Neither KDEX nor KSHRD is necessary for the initial merchant pilot. Direct funded reward claims will be compared with a separate KSHRD instrument before token launch.

## Verified earning

Agent requests do not establish their own identity, permissions, user access, purchase facts, or reward quality. A trusted server adapter must authenticate a credential and provide user-scoped capabilities with an expiry. A separate commerce adapter must verify evidence and register an immutable event ID. The supplied library fails closed without these adapters; it does not implement an identity provider, merchant order integration, or an AI fraud oracle.

The earning engine accepts a verified event only once. Reviews and helpful answers are unique per participant/subject; shipment and referral subjects cannot be rewarded repeatedly under fresh event IDs.

For reviews:

```
base(n) = 10 / log2(n + 2)
quality = min((photos ? 2 : 1) * (textLength > 200 ? 1.5 : 1) * (detailed ? 1.3 : 1), 5)
reward = round(base(n) * quality * (firstReviewOnProduct ? 3 : 1))
```

The present inputs permit a maximum quality factor of 3.9, below the configured 5 cap. A new user's first detailed photo review on an unreviewed product earns 117 KRUNE. The first-review premium is additional to the quality cap. The formula alone does not make farming uneconomic.

Helpful verified answers earn 5 KRUNE. Referrals earn 30 only after evidence of 90 days of activity, never for self-referrals. Shipment rewards are 0.1 KRUNE per unit of order value, rounded and capped at 100, with half the reward after three days. The merchant integration must establish the currency normalization, genuine order, account relationship, fulfillment facts, refunds, and minimum purchase rules before production earning.

## Staking mathematics

Staking requires positive KRUNE and KDEX. KRUNE stays in the wallet and is referenced; KDEX is escrowed. One position exists per wallet. Top-ups cannot reuse already referenced KRUNE and reset the 90-day lock on the entire position. There is no early exit or partial withdrawal.

```
weight = floor(sqrt(kruneBaseUnits)) * floor(sqrt(kdexBaseUnits))
SCALE = 10^18
pool = depositedUsdcBaseUnits + unallocatedFees
delta = floor(pool * SCALE / totalWeight)
allocated = ceil(delta * totalWeight / SCALE)
```

Each position checkpoints the global reward accumulator before changing weight. Yield is a share of transferred fee tokens, never a fixed annual return. No deposits means no additional rewards, regardless of elapsed time. Rounding can leave small amounts reserved but unattributable.

Fees arriving without active stakes are carried to the next allocation. That allocation can be triggered with a zero-value deposit by a newly eligible staker. This is an explicit current allocation rule, not proven fair; epoch allocation or a separate prelaunch reserve must be evaluated before launch.

The TypeScript staking module is a local simulation using whole reputation/capital amounts and integer USDC base units. Its cash ledger is not a real payment processor. Solidity operates with token base units and real transfers.

## Limits of the participation gate

The design blocks capital with zero reputation; it does not prevent concentration once reputation is positive. With two participants, 500 KRUNE/500 KDEX has weight 500, while 20 KRUNE/1,000,000 KDEX has weight approximately 4,472. The latter receives approximately 89.9% of that pool.

Non-transferable tokens do not stop account sales, rented wallet control, bribed issuers, or paid farming. Account splitting can reset earning histories. Identity, eligibility age, fraud detection, appeals, and reputation-linked capital limits require evidence and simulation. No claim of unconditional whale or Sybil resistance is made.

## Treasury and redemption

Fees enter through Staking.depositFees(), which transfers USDC to Treasury. Treasury has no depositFees() function. Deposits must transfer the stated amount; fee-on-transfer assets are rejected. Standard deployed KRUNE/KDEX/KSHRD and a verified USDC deployment are required.

After 90 days, unstake() returns escrowed KDEX. Earned rewards are minted as KSHRD. If that mint fails, principal still returns and the reward is recorded for a later claimYield(). The user approves Treasury to burn KSHRD, then calls redeem() from their own wallet. Treasury burns only the amount paid for and retains sub-USDC-unit dust in the holder's balance.

One whole KSHRD redeems for one whole USDC under normal token operation; this is not a guarantee that USDC equals a dollar or is always transferable. USDC issuer actions, token upgrades, chain outages and depegs are external risks.

Treasury.totalOutstandingLiability() counts minted claims only. Staking.totalReservedUsdc() additionally includes conservative unminted allocations and carried fees. These reserves are not operating cash. The accumulator proves receipt of tokens, not that deposits represent profitable merchant revenue; anyone can deposit.

The optional KDEX conversion ships disabled. Its owner-set rate and 10% bonus are not a manipulation-resistant market-price system. It must remain disabled until governance, price freshness, payout limits, slippage protection, and a subsidy budget are implemented and reviewed.

## Settlement and cryptographic integrity

Settlement uses a domain-separated replay key derived from the chain, KRUNE contract, schema namespace, and immutable event ID. The outbox separately commits to the user, recipient wallet, amount, event type, and timestamp. The KRUNE contract records the recipient/amount digest. A trusted wallet resolver must bind the user to a verified wallet; callers cannot substitute a recipient.

Broadcast, receipt, and finality are distinct. A matching digest in finalized chain state is required for confirmation. A durable SQLite outbox adapter is supplied for a Node 24 process on persistent storage. In-memory stores remain test/reference components. This adapter must not be placed on an ephemeral serverless filesystem. Production accounting, recovery operations, multi-worker nonce management, and merchant reconciliation still require service integration.

The legacy name hash259 denotes standard SHA-256 with a versioned format; it is not a novel cryptographic algorithm or additional security bits. Archive v2 uses unambiguous structured records, length-prefixed hash links, detached reads, access logging, complete timestamp-preserving backups, and optional Ed25519-signed checkpoints.

A hash chain without an independently retained checkpoint cannot detect an operator rewriting the whole history. Checkpoint signing keys and independently retained checkpoints must be operated separately from mutable storage. Role arguments to archive methods are trusted-server inputs, not public authorization credentials. The archive is not encryption and does not prove that the original business facts were true.

## Administrative power and recovery

KRUNE minting remains a trusted issuer capability. Compromise can inflate reputation and dilute other participants' funded reward shares. Deployment, earning, and administrative keys must be separate. Admin authority should be held by an independently operated multisig; the code does not prove signer independence.

KSHRD roles can be sealed irreversibly after wiring. The seal requires exactly one minter and one burner with separate addresses. Deployment verification must establish that those addresses are the reviewed Staking and Treasury contracts. Sealing prevents later role rotation; it is not a substitute for a migration and incident plan.

Staking pause stops new stakes. It does not stop mature principal exits or funded fee deposits. Treasury redemption is not pausable. Contracts are non-upgradeable. Recovery, emergency controls, governance and migration choices must be settled before mainnet deployment.

## Business and launch gates

The pilot charges merchants for verified commerce value. Subscription and transaction prices are hypotheses to test. Reward allocations should come from distributable surplus after refunds, payment costs, fraud/support costs, taxes, operations, and required reserves. Token-sale proceeds are financing, not evidence of operating demand.

Launch sequence:

1. Correctness, adversarial tests, reproducible artifacts, and secure evidence/authentication integrations.
2. Durable merchant accounting, reconciliation, backups, incident drills, and a paid merchant pilot.
3. Independently measured customer value, retention, fraud loss, and positive contribution margins.
4. Economic simulations and a documented necessity test for every proposed token.
5. Scoped legal clearance, independent contract/security review, remediation retest, and verified deployment.

## Legal and external evidence

Token treatment depends on economic function and the actual offering, not project labels. KDEX participation in income streams and KSHRD redemption require design-specific Swiss legal assessment; KRUNE's involvement in financial benefits must also be assessed. Direct payouts or token-to-token redemption are not assumed exemptions. Other markets require their own review.

Primary reference: [FINMA ICO guidelines](https://www.finma.ch/en/news/2018/02/20180216-mm-ico-wegleitung/) and [FINMA stablecoin guidance](https://www.finma.ch/en/news/2024/07/20240726-m-am-06-24-stablecoins/). These sources describe regulatory principles, not approval of TradeKarma.

No external professional audit, regulatory clearance, pilot outcome, return, token price, or launch date is represented as completed or guaranteed by this paper.
