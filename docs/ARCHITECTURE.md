# TradeKarma Architecture

## System Overview

TradeKarma is a positive-reinforcement token economy. Three tokens, three jobs,
introduced in phases. The codebase is deliberately layered so Phase 1 runs on a
plain database and Phase 2+ swaps in on-chain contracts behind the same logic.

```
┌─────────────────────────────────────────────────────────────┐
│                      Frontend (site/)                        │
│   index.html (toggle) → variant-opus.html / variant-gpt.html │
│   Live: https://tradekarmanet.vercel.app                     │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                    Agent-Agnostic API (src/agent/)           │
│   AgentInterface  ·  RequestValidator                        │
│   (any LLM / script speaks the same typed contract)          │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                     Core Logic (src/logic/)                  │
│   earning.ts (KRUNE)   ·   staking.ts (KRUNE+KDEX → KSHRD)   │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                      Models (src/models/)                    │
│   User · Transaction · KarmaRune · Tokens(KDEX/KSHRD)        │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│               Archive + Governance (src/archive, src/dao)    │
│   TransactionArchive · hash259  ·  Governance (KDEX votes)   │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│              On-Chain (contracts/) — Phase 2+                │
│   KarmaRune.sol · KarmaDex.sol · Staking.sol · Treasury.sol │
└──────────────────────────────────────────────────────────────┘
```

## The Three Tokens

| Token | Ticker | Job | Origin | On-chain (Phase 2) |
|-------|--------|-----|--------|--------------------|
| KarmaRune | $KRUNE | Reputation | **Earned only** — reviews, help, referrals, shipping | `KarmaRune.sol` (no public mint/buy) |
| KarmaDex | $KDEX | Investment + governance | Bought on a DEX; fixed supply | `KarmaDex.sol` (fixed supply) |
| KarmaShard | $KSHRD | Yield | Stake KRUNE + KDEX together | `Staking.sol` + `Treasury.sol` |

## Load-Bearing Invariants

1. **KRUNE is earned, never bought.** No purchase path exists — off-chain there
   is no "buy" endpoint; on-chain `KarmaRune.sol` has no payable function and
   only a `MINTER` (the earning engine) can create tokens via `mintEarned`.
2. **Anti-whale gate.** Staking requires BOTH tokens. A wallet with millions of
   KDEX and zero KRUNE cannot stake (`staking.ts` gate off-chain; `Staking.sol`
   `require()` on-chain). Yield accrues on `sqrt(KRUNE × KDEX)`, so both halves
   matter.
3. **Diminishing returns.** Earning uses `10 / log2(count + 2)` — the Nth action
   earns less than the first, discouraging farming. Quality (photos, detail,
   first-review) still multiplies up to 5×.
4. **Tamper-evident archive.** Every transaction is hash-linked (`hash259`);
   changing any record breaks every later link, and the chain validator detects
   it. Reads are role-gated (SYSTEM/ADMIN/AUDITOR/USER).

## Directory Map

```
site/                    Frontend (deployed)
src/
  models/                Data models (User, Transaction, KarmaRune, Tokens)
  logic/                 earning.ts, staking.ts
  archive/               Archive.ts (hash chain), hash259.ts
  agent/                 AgentInterface.ts, RequestValidator.ts
  dao/                   Governance.ts (KDEX-weighted voting)
  __tests__/             57 tests (earning, staking, archive, agent, DAO)
contracts/               Solidity (Phase 2): KarmaRune, KarmaDex, Staking, Treasury
docs/                    ARCHITECTURE.md, AGENT_API.md
BUILD-PLAN.md            6-sprint roadmap + finish conditions
```

## Phased Rollout

- **Phase 1 (now):** Database points. Prove the model with `src/`. No crypto.
- **Phase 2:** Migrate KRUNE → ERC-20 on Base; launch KDEX; enable staking.
- **Phase 3:** KSHRD yield live; DAO governance; open protocol.

## Testing & Quality

- 57 Jest tests, TypeScript strict mode (`tsc --noEmit` clean, zero `any`).
- Coverage threshold 80% (`jest.config.js`).
- Every load-bearing invariant has a test that would fail if it broke
  (anti-whale rejection, tamper detection, diminishing returns, provider
  agnosticism).
