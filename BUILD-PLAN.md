# TradeKarma Build Plan

**Project:** TradeKarma — Positive-Reinforcement E-Commerce Token Economy  
**Status:** Phase 1 (MVP Database) → Phase 2 (On-Chain) → Phase 3 (DAO Governance)  
**Date:** 2026-07-11  
**Goal Completion:** 2026-08-31  

---

## Overview

Build the core token economy logic, file archive infrastructure, and agent-agnostic layers so the platform can:
1. **Track reputation** (KRUNE earning) in a database with verified attribution.
2. **Accept investment** (KDEX) with governance rights.
3. **Stake & yield** (KSHRD) by locking earned + invested tokens.
4. **Persist & audit** all transactions with cryptographic proof (hash259 archive).
5. **Enable any LLM/agent** to interact without lock-in.

---

## Phase 1: MVP Marketplace (Database, No Crypto)

### Sprint 1: Core Data Models & Earning Mechanics (Week 1–2)

**Deliverables:**
- `src/models/User.ts` — user profiles, reputation ledger
- `src/models/Transaction.ts` — KRUNE earning events (review, help, referral, ship)
- `src/logic/earning.ts` — logarithmic multiplier, quality bonus, retroactive helpfulness
- `src/models/KarmaRune.ts` — point ledger (database representation of KRUNE)
- Unit tests (Jest) for all earning scenarios

**Finish Condition:**
- All unit tests pass (>95% coverage)
- Example: "Write detailed photo review on $100 purchase → 30 KRUNE; generic text review → 7 KRUNE; detail multiplier 3–5x verified"
- Example: "First review on new product → 3× bonus verified"
- Example: "Helpful answer to buyer question → +5 KRUNE retroactively verified"

---

### Sprint 2: Staking & Yield Logic (Week 2–3)

**Deliverables:**
- `src/models/KarmaDex.ts` — investment token model (fixed supply, governance)
- `src/models/KarmaShard.ts` — yield token model (KRUNE + KDEX → KSHRD)
- `src/logic/staking.ts` — lock KRUNE + KDEX → generate KSHRD
- `src/logic/redemption.ts` — redeem KSHRD for USDC or KDEX (treasury backed)
- Anti-whale mechanic: whale with $10M KDEX but 0 KRUNE cannot stake (tests verify)

**Finish Condition:**
- Staking tests pass: "Stake 500 KRUNE + 500 KDEX (on paper) → KSHRD accrual per block verified"
- Redemption tests pass: "User redeems KSHRD for 50% USDC (treasury), 50% KDEX keepback verified"
- Anti-whale gate confirmed: "Whale with 10M KDEX and 0 KRUNE attempts stake → rejected, error message clear"

---

### Sprint 3: File Archive & Cryptographic Proof (Week 3–4)

**Deliverables:**
- `src/archive/FileArchive.ts` — immutable transaction log (append-only, hash-linked)
- `src/archive/hash259.ts` — SHA-256 + version tag (hash259-v1, hash259-v2, etc.)
- `src/archive/AccessControl.ts` — role-based read permissions (admin, auditor, user, system)
- `src/archive/Serializer.ts` — serialize transactions to binary, verify hash chain
- Integration tests: write 1000 transactions, verify chain integrity

**Finish Condition:**
- Hash chain verified: "Tamper one byte in transaction #500 → SHA-256 mismatch propagates to end, caught by validator"
- Access control verified: "User role cannot read admin audit log; auditor role can; system role can read all"
- Archive write-heavy performance: ">10k tx/sec write throughput on SSD verified"

---

## Phase 2: On-Chain Migration (KRUNE ERC-20, KDEX Launch)

### Sprint 4: Smart Contracts & Bridging (Week 5–6)

**Deliverables:**
- `contracts/KarmaRune.sol` — ERC-20 on Base, non-mintable (points migrate, not created)
- `contracts/KarmaDex.sol` — ERC-20 on Base, fixed supply, governance
- `src/bridge/PointsToTokenBridge.ts` — 1:1 migration of database KRUNE to on-chain KRUNE
- Wallet integration (Coinbase Smart Wallet, no seed phrases)
- Unit tests + testnet (Base Sepolia) deploy

**Finish Condition:**
- Testnet deploy verified on Base Sepolia
- Bridge swap verified: "10,000 database KRUNE → 10,000 on-chain KRUNE confirmed in wallet"
- Governance verified: "KDEX holder votes on parameter change, tally recorded"

---

### Sprint 5: Staking on-Chain (Week 6–7)

**Deliverables:**
- `contracts/Staking.sol` — lock KRUNE + KDEX → accrue KSHRD
- `contracts/Treasury.sol` — multi-sig holds USDC/KDEX for KSHRD redemption
- `contracts/YieldAggregator.sol` — distribute platform fees as yield to KSHRD holders
- Testnet harness: run 1000 staking + redemption txs, verify yield accuracy

**Finish Condition:**
- Yield accuracy: "1% platform fee over month → accurate KSHRD payout verified"
- Anti-whale gate on-chain: "0x1234...BEEF with 10M KDEX and 0 KRUNE attempts stake → tx reverts with clear reason"

---

## Phase 3: Open Protocol & DAO (Week 7–8)

### Sprint 6: DAO Governance & Agent Layer

**Deliverables:**
- `src/agent/AgentInterface.ts` — LLM-agnostic API for agents to query/write transactions
- `src/agent/RequestValidator.ts` — validate agent requests (no self-dealing, rate limiting)
- `src/dao/GovernanceProposal.ts` — create/vote proposals (KDEX holders, 1 token = 1 vote)
- `docs/AGENT_API.md` — detailed spec (no vendor lock-in, OpenAI/Anthropic/local LLM compatible)

**Finish Condition:**
- Agent API spec complete and reviewed
- Test harness: different agent implementations (mock GPT, mock Opus, mock open-source) all call same API successfully
- DAO vote recorded on-chain: "KDEX holders vote 60% yes → proposal passes, verified"

---

## Cross-Cutting Concerns

### Security & Audit

- [ ] Smart contracts audited (Echidna fuzzing at minimum)
- [ ] File archive tamper-evident (cryptographic proof verified)
- [ ] API rate limiting + anti-bot (fail tests)
- [ ] FINMA compliance memo drafted (Switzerland legal landscape)

### Monitoring & Observability

- [ ] Event logging to file archive (all state changes)
- [ ] Prometheus metrics (earnings, staking, yields per day)
- [ ] Dashboard: real-time KRUNE/KDEX/KSHRD volumes

### Documentation

- [ ] `docs/ARCHITECTURE.md` — system design, token flow diagrams
- [ ] `docs/API.md` — REST endpoints for frontend/agents
- [ ] `docs/AGENT_API.md` — agent interaction spec (LLM-agnostic)
- [ ] `docs/FILE_ARCHIVE.md` — format, hash verification, access control

---

## Success Criteria (Finish Conditions)

### Code Quality
- [ ] **Test Coverage:** >90% unit + integration tests, all passing
- [ ] **Type Safety:** TypeScript strict mode, zero `any`
- [ ] **Performance:** <100ms P95 for all API calls; >10k tx/sec archive write throughput

### Functionality
- [ ] **KRUNE:** Earned-only, logarithmic rewards, quality multipliers work as spec
- [ ] **KDEX:** Fixed supply, governance voting active
- [ ] **KSHRD:** Locked KRUNE + KDEX → yield accrual verified; redemption USDC/KDEX both paths work
- [ ] **Anti-Whale:** Whale with >$10M investment + 0 reputation cannot access yield (gate enforced)

### Security & Auditability
- [ ] **Hash Archive:** One-way hashes, tamper-evident, role-based access
- [ ] **Smart Contracts:** Testnet audit pass + mainnet audit roadmap
- [ ] **Compliance:** FINMA memo complete, legal review OK

### Agent Compatibility
- [ ] **API Spec:** LLM-agnostic, documented, no vendor lock-in
- [ ] **Multi-Agent Test:** ≥3 different agent implementations (GPT-4 mock, Opus mock, local LLM mock) all call same API successfully

### Deployment
- [ ] **GitHub:** All code pushed, CI/CD green
- [ ] **Testnet:** Contracts deploy & function on Base Sepolia
- [ ] **Mainnet Roadmap:** Deployment checklist drafted (dates TBD with legal)

---

## Effort Estimate

| Sprint | Work | Duration | Owner |
|--------|------|----------|-------|
| 1 | Earning mechanics | 2 weeks | Code |
| 2 | Staking & yield | 1–2 weeks | Code |
| 3 | File archive | 1–2 weeks | Code |
| 4 | Smart contracts | 2 weeks | Code |
| 5 | Staking on-chain | 1–2 weeks | Code |
| 6 | Agent layer & DAO | 1–2 weeks | Code |
| **Total** | **All sprints** | **~10–12 weeks** | **Autonomous** |

---

## Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| Smart contract bugs | Echidna fuzzing, Testnet audit before mainnet |
| Hash collision (unlikely) | SHA-256 proven; monitor academic literature |
| Agent abuse (spam, self-dealing) | Rate limiting, request validation, slashing rules |
| Legal/compliance delays | FINMA memo drafted early, legal review by week 2 |

---

## Next Steps

1. **Start Sprint 1:** Core data models + earning logic (target: 2026-07-18)
2. **Weekly Sync:** Code review + test pass verification
3. **Deploy Testnet:** End of Sprint 4 (2026-08-01)
4. **Final Integration:** Sprints 5–6, launch readiness check

**Go/No-Go Decision:** 2026-08-31 (mainnet deployment readiness)
