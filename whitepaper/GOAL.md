# GOAL — TradeKarma White Paper (v3, canonical)

**Objective:** Produce `WHITEPAPER.md` at the repo root — the single canonical
TradeKarma white paper — by synthesizing the existing drafts (v1, v2), the
business plan, operations doc, and the *actually implemented* mechanics in
`src/` and `contracts/`. It must be internally consistent with the code.

## Finish condition (objective, machine-checked)

The draft is **DONE** when `whitepaper/eval_whitepaper.py` reports:

- **Score ≥ 85 / 100**, AND
- **all CRITICAL substance items present** (token facts + anti-whale gate).

The eval is the Ringer check: a writer worker drafts, the eval grades, and the
run only passes when the bar is met. No human "looks good" — the bar is the bar.

## Scoring rubric (100 pts)

### Structure — 40 pts (required sections, ~2.7 each)
Abstract/summary · Problem · Solution overview · The Three Tokens ·
Earning mechanics · Staking & yield · Anti-whale mechanic · Tokenomics/supply ·
Phased rollout (3 phases) · Governance/DAO · Treasury & redemption ·
Security & immutable archive (hash259) · Legal/regulatory (Switzerland/FINMA) ·
Risks · Roadmap · Conclusion.

### Substance — 35 pts (correct, code-consistent facts)
- KRUNE = reputation, **earned only / can never be bought** *(CRITICAL)*
- KDEX = investment + governance, **fixed supply**, bought on a DEX *(CRITICAL)*
- KSHRD = yield, from **staking KRUNE + KDEX together**, redeem USDC/KDEX *(CRITICAL)*
- Anti-whale: whale w/ millions of KDEX + 0 KRUNE **cannot** stake — need both halves *(CRITICAL)*
- Diminishing-returns / logarithmic, quality-weighted earning
- Geometric-mean (√(KRUNE·KDEX)) yield
- Base chain + Coinbase Smart Wallet
- Database-first: "prove the model, then launch tokens"
- hash259 immutable, tamper-evident, role-gated archive
- Basel, Switzerland origin

### Length & depth — 10 pts
≥ 3,500 words.

### Hygiene — 15 pts
Title "TradeKarma" · tagline "Earn Your Reputation, Never Buy It" ·
≥ 12 `##`/`###` headings · no lorem/TODO/placeholder ·
a "not financial advice" / forward-looking disclaimer.

## Method
1. Ringer writer worker (claude / Opus 4.8) drafts `WHITEPAPER.md`.
2. `eval_whitepaper.py` grades → exit 0 only at ≥85 + CRITICAL gate.
3. Ringer retries once with the eval's failure output injected.
4. On PASS: read it, spot-check, commit.
