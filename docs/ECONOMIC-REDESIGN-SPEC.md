# Economic Redesign Spec — v2 token mechanics

**Status:** authoritative. Every agent implementing this works from this file.
**Decided by:** repo owner, 2026-07-28. **Author of spec:** orchestrating assistant.

Supersedes the economics in `docs/SECURITY-AUDIT-CONTRACTS.md` findings H-01, H-02, H-04, H-05.
The audit remains valid for everything else.

---

## Why this exists

The v1 contracts computed yield from **token quantities and time**, then paid it out in
**dollars** at a hardcoded 1 KSHRD = 1 USDC. No price appeared anywhere in the system, and both
principals were refunded on exit — so staking had no cost, and every KSHRD minted was an unhedged
dollar liability. Measured: a 1M/1M position minted $9,999/yr of USDC claims against ~$1,000 of
fully-refunded KDEX. Aggregate liability was `0.01 × sqrt(KRUNE × KDEX)` with **KRUNE uncapped**.

The whitepaper already promised the right mitigations (WHITEPAPER.md:207, :306) — "yield funded
only by real revenue", "pool held at 0% below a minimum user threshold". None of them reached
Solidity. This spec closes that gap.

---

## D1 + D2 — Pool-share yield (replaces the fixed dollar rate)

**Decision: option (a) for D1, options (b) AND (c) for D2.**

### The invariant

> KSHRD minted can never exceed USDC actually deposited as fees.

Solvency stops being a monitored property and becomes a structural one.

### Mechanism — Synthetix `StakingRewards` accumulator

Do **not** invent a new scheme. Use the battle-tested accumulator pattern.

- Each position's weight is its geometric mean `sqrt(krune) × sqrt(kdex)` (keep the existing
  overflow-safe `_geometricMean`; it is correct and Sybil-neutral).
- Global `totalWeight` = Σ of active position weights. Maintained incrementally on
  stake/unstake — never iterate positions.
- `rewardPerWeightStored` (scaled 1e18) increases **only** inside `depositFees()`:
  ```
  rewardPerWeightStored += (usdcAmount * SCALE) / totalWeight
  ```
  If `totalWeight == 0`, fees deposited are held and allocated to the next depositors —
  do NOT divide by zero and do NOT silently discard them. Track them in `unallocatedFees` and
  fold them in when weight next becomes non-zero.
- Each position stores `rewardPerWeightPaid`. Earned:
  ```
  earned_i = weight_i * (rewardPerWeightStored - rewardPerWeightPaid_i) / SCALE + accrued_i
  ```
- `unstake()` mints exactly `earned_i` as KSHRD (18-dec, denominated in USDC units × 1e12 so
  1 KSHRD still redeems for 1 USDC).

**`YIELD_RATE_PER_SEC` is deleted.** There is no rate. Yield is a share of real revenue, full stop.
This is what the whitepaper always claimed.

### Required accounting surface (D2 option b)

Add and expose:
- `totalWeight()` — sum of active position weights
- `totalKshrdOutstanding()` — minted minus burned (read from KarmaShard `totalSupply()`)
- `totalOutstandingLiability()` — outstanding KSHRD expressed in USDC units
- `collateralRatio()` — treasury USDC ÷ outstanding liability, 1e18-scaled

Emit an event when a fee deposit changes the ratio. Insolvency must be **observable before** it is
discovered by a failed redemption.

Note: with pool-share the ratio is ≥ 1 by construction. These reads exist so the property is
*provable on-chain* rather than merely believed, and so the front-end can display it.

### Redemption

`Treasury.redeem(kshrdAmount, asUsdc)` — USDC path unchanged in shape: burn KSHRD, pay
`kshrdAmount / usdcScale`. It is now solvent by construction rather than by a balance race.

### KDEX keepback branch — DEFAULT DISABLED

The `asUsdc=false` path pays `kshrd × 1.1` in KDEX with no price oracle. Audit H-02 measured
+450% overpayment at $5/KDEX. There is no KDEX market yet, so no honest rate exists.

**Implement as:** a governance-settable `kshrdPerKdexRate`, **defaulting to 0 = branch disabled**.
`redeem(..., false)` reverts with a clear message while disabled. Owner can enable it later once a
market exists. Do not hardcode 1:1. Do not add an oracle now.

*Flagged for owner: this is the one sub-decision not explicitly made. Safe default chosen; say the
word to change it.*

---

## D3 — KRUNE becomes soulbound

**Decision: option (a), true soulbound.**

`KarmaRune` must reject all holder-to-holder movement. Override the OZ `_update` hook so any
transfer where both `from` and `to` are non-zero reverts. Minting (`from == 0`) stays allowed via
`mintEarned`. No burn path is required.

`transfer`, `transferFrom`, `approve` must revert with an explicit "KRUNE: soulbound" style error
rather than silently failing. Do not leave a misleading ERC-20 surface that appears to work.

### Consequence — staking must reference, not escrow

`Staking.stake()` currently escrows KRUNE via `safeTransferFrom`. **That is impossible with a
soulbound token.** Redesign:

- `stake(kruneAmount, kdexAmount)` requires `krune.balanceOf(msg.sender) >= kruneAmount` and
  **records** `kruneAmount` in the position. KRUNE never moves.
- Only **KDEX** is actually transferred into the contract.
- `unstake()` returns KDEX only. There is no KRUNE to return — it never left.

This is safe because soulbound KRUNE cannot be transferred away mid-position, so the referenced
balance cannot vanish. It also strengthens the brand claim: reputation is permanently yours.

**Anti-whale gate is preserved unchanged** — `stake` still requires both `kruneAmount > 0` and
`kdexAmount > 0`, and weight is still the geometric mean. A whale with no earned KRUNE still
cannot stake.

**Guard against double-counting:** one position per address already prevents staking the same
KRUNE twice. Verify this holds under top-up. Do NOT add a `lockedOf` mapping unless a test proves
it is needed — KRUNE cannot leave the wallet, so a lock is redundant.

---

## D4 — No early exit

**Decision: keep the hard 90-day lock. Do NOT implement early exit.**

`unstake()` continues to revert while locked. No forfeiture path, no partial exit.

The `startedAt`-resets-on-top-up behaviour from the previous remediation **stays** — it closes a
proven exploit (1-wei seasoned position unlocking any size for 2 wei).

**Required:** `WHITEPAPER.md` currently claims early exit with yield forfeiture. That claim must be
removed or corrected. The code is the source of truth.

---

## Whitepaper claims that must be re-checked after implementation

All four were contradicted by v1. After this redesign, verify each is TRUE in code, or change the
prose:

| Claim | v1 | Expected v2 |
|---|---|---|
| "Reputation cannot be bought at any price" | False — freely transferable | **True** — soulbound |
| "KSHRD cannot be conjured from nothing" | False — admin self-grant, unbacked rate | **True** — pool-share + `lockRoles()` |
| "Yield pool sits at 0% below a threshold" | Not implemented at all | **True by construction** — no fees, no yield |
| "Exit early, forfeit yield, recover principal" | Not implemented | **Remove the claim** |

---

## Non-goals — do NOT implement

- Price oracles of any kind (Chainlink etc.). Pool-share removes the need.
- Upgradeability proxies. Contracts stay immutable.
- Governance modules, timelocks, supply caps beyond what is specified above.
- Slashing or KRUNE burning.
- Any change to `hash259`, the archive, the DAO module, or the agent API.

---

## Preserved from v1 — do not regress

- `KarmaShard.lockRoles()` one-way seal; NOT applied to KarmaRune (must keep minter-key rotation).
- `unstake()` never depends on the KSHRD mint succeeding — `try/catch` → `unclaimedYield` →
  `claimYield()`. Principal always exits.
- `mintEarned` on-chain `settled[reasonHash]` replay guard.
- `renounceOwnership()` reverts on Staking and Treasury.
- `KarmaShard.burnFrom` requires allowance AND `BURNER_ROLE`.
- `SafeERC20`, `ReentrancyGuard`, `Pausable` (pause gates `stake` only, never `unstake`).
- Treasury `usdcScale` read from the token at construction, never hardcoded.
- 100% test coverage on all contracts. Zero build warnings.
