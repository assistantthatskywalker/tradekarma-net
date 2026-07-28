# Decision Log

Newest entries on top. Each entry captures before/after state, why the choice was made,
why it was implemented this way, and what would justify revisiting it.

---

## 2026-07-28 — On-chain layer: Solidity toolchain, OpenZeppelin port, security remediation

### Before

`contracts/` held 4 hand-written Solidity files (339 LOC) that had **never been compiled** —
no `hardhat.config`, no `foundry.toml`, no remappings, no contract tests. The repo had zero
blockchain libraries; the only runtime dependency was `uuid`. `src/models/Tokens.ts` stated
outright: *"Phase 1: Database representation (not yet on-chain)"*. The crypto economy existed
as a well-specified off-chain TypeScript simulation (59 passing Jest tests) plus an unexecuted
design artifact in Solidity.

### After

- Foundry 1.7.1 toolchain, solc 0.8.28, `evm_version = cancun` (Base supports it), optimizer 200 runs.
- OpenZeppelin v5.6.1 vendored in `lib/`, all three tokens ported off hand-rolled ERC-20.
- **5 contracts** — `KarmaShard.sol` (KSHRD) is new; see below.
- **171 Foundry tests**, 100% line/statement/branch/function coverage on all 5 contracts.
- **TypeScript↔chain bridge** in `src/chain/` (viem), 116 Jest tests.
- Adversarial security audit in `SECURITY-AUDIT-CONTRACTS.md` — 25 findings.

### Decisions and rationale

**1. Foundry over Hardhat.** Native Solidity tests, built-in fuzzing and invariant testing,
no JS test harness between the assertions and the EVM. Money-handling code benefits more from
`forge`'s property testing than from Hardhat's plugin ecosystem, and this repo needs no
deployment framework beyond a script.

**2. OpenZeppelin port was non-negotiable.** Hand-rolled ERC-20 in money paths is an audit
liability regardless of correctness — auditors price unfamiliar token code, and the original
`transferFrom` allowance handling was non-standard. Same `name`/`symbol`/`decimals`, no ABI
break on standard methods.

**3. `KarmaShard` (KSHRD) created — it closed a hole, not a feature gap.** `Staking` accrued
`accruedKshrd` and `Treasury.redeem()` consumed a `kshrd` amount, but no KSHRD token existed and
nothing connected them. `unstake()` computed the yield, returned it as a return value (invisible
to an EOA), then `delete positions[msg.sender]` destroyed it. **Every staker's entire yield was
silently lost.** `unstake()` now mints KSHRD; `Treasury.redeem()` burns it before paying.

**4. Treasury decimal scaling read at construction, not hardcoded.** `redeem()` previously did
`paid = kshrd`, treating 18-decimal KSHRD as 6-decimal USDC — 1e18 KSHRD would attempt to pay
1e18 USDC base units (~$1 trillion). `usdcScale` is now an immutable
`10 ** (18 - IERC20Metadata(usdc).decimals())`. Read from the token rather than hardcoded to 6,
because the backing stablecoin is a deploy parameter and may not be USDC forever.

**5. Geometric mean is `sqrt(a) * sqrt(b)`, not `sqrt(a * b)`.** The original reverts on checked
overflow once `a * b` exceeds ~1.15e77 — reachable with two 18-decimal balances, and it would
have bricked `stake`, `unstake` **and** `pendingKshrd` for that position, trapping principal.
Both roots are ≤ 2^128−1 so the product can never overflow. Mathematically ≤ the true value
(short by at most `sqrt(a) + sqrt(b)`, ~63 gwei on two 1000-token balances), always rounding in
the protocol's favour.

**6. Lock restarts on every top-up (`startedAt` reset unconditionally).** The lock previously
evaluated against the *first* deposit forever: open a 1-wei position, wait 90 days, then top up
5M KDEX and `unstake()` in the same block — full principal exits immediately, setup cost 2 wei.

Chosen over a weighted-average lock because **weighted does not close the hole, it rescales it**:
remaining lock becomes `90d · gNew/(gOld+gNew)`, so adding 1/1000th of a seasoned position's
geometric weight unlocks the whole position in ~2 hours. Chosen over per-tranche locks because
`unstake()` would have to iterate tranches — unbounded is a gas-DoS that bricks a position,
bounded needs a tranche cap, partial-exit semantics and per-tranche accrual, which is a new
design rather than a security fix, and it would change the public `positions()` getter the
TypeScript bridge reads.

*Accepted cost:* an honest staker topping up on day 89 re-locks their mature principal for
another 90 days. Self-inflicted (only `msg.sender` can top up their own position), visible
on-chain before committing, and costs illiquidity only — `_accrue` settles the old principal at
the old size first, so no yield or principal is ever lost.

**7. `unstake()` never depends on the yield path succeeding.** It previously called
`kshrd.mint()` unconditionally; if Staking lacked `MINTER_ROLE` — revoked, or simply not yet
granted mid-deploy — the call reverted and principal was unrecoverable **by anyone**. `pause()`
did not help. The mint is now wrapped in `try/catch`; on failure the amount lands in
`unclaimedYield[user]` for a later `claimYield()`, and principal transfers unconditionally.

Rejected the audit's alternative (`emergencyUnstake()`) as redundant surface — once the mint
cannot revert the exit, a second exit path adds attack surface for no gain.

**8. `KarmaShard.burnFrom` requires an allowance *and* `BURNER_ROLE`.** Role-gating alone let any
`BURNER_ROLE` holder destroy any holder's entire yield claim with no consent and no payout, and
silently broke the `ERC20Burnable.burnFrom` convention integrators assume. Both checks kept
deliberately: **the role says *who* may burn, the allowance says *whose and how many*.** Neither
substitutes for the other.

*Consequence:* `Treasury.redeem()` now requires the holder to `approve(treasury, amount)` on
KSHRD first. Any UI flow must approve before redeeming.

**9. `renounceOwnership()` reverts on Staking and Treasury.** Renouncing destroyed the emergency
pause permanently on Staking, and made `recoverToken` uncallable on Treasury. `transferOwnership`
still works.

**10. `mintEarned` has an on-chain `settled[reasonHash]` replay guard.** The TypeScript settlement
ledger preventing double-mints is in-memory and does not survive a process restart. Defence in
depth for a hot minter key: the on-chain `require` is the correctness mechanism; the TS check is
an optimisation that avoids submitting a doomed transaction.

**11. `lockRoles()` on KarmaShard only — deliberately NOT on KarmaRune.** A one-way irreversible
seal on role administration, making C-01's trust assumption verifiable on-chain instead of social.
Not applied to KarmaRune because freezing that role table would remove the ability to rotate a
compromised hot bridge minter key — strictly worse.

**⚠️ `lockRoles()` must be called only after `MINTER_ROLE` (Staking) and `BURNER_ROLE` (Treasury)
are confirmed granted. Called early, KSHRD is permanently unmintable and every staker's yield
permanently unclaimable.**

**12. ABIs are generated, never hand-written.** `npm run abis` (`scripts/generate-abis.mjs`) reads
`out/<Contract>.sol/<Contract>.json` and emits `src/chain/abis.ts`. Hand-transcribed ABIs drifted
from the contracts twice during this build — both times every gate stayed green, because neither
`tsc` nor Jest can detect an ABI that disagrees with bytecode. **Regenerate after every contract
change.**

### Open product decisions — NOT implemented, owner's call

Deliberately left alone; changing them is a tokenomics decision, not a security fix.
**Contracts are non-upgradeable and `YIELD_RATE_PER_SEC` is a `constant`, so none of these can be
corrected after deployment.**

1. **No price oracle anywhere** (audit H-01/H-02). Yield is computed on token *quantities* and paid
   in *dollars* at 1:1, and both principals are refunded. The treasury loses if KDEX is cheap
   (a 1M/1M position costs ~$1,000 at a $0.001 launch price and mints ~$9,999/yr of hard USDC
   claims) *and* if KDEX is expensive (the keepback pays 1.1 KDEX per $1 claim — +450%
   overpayment at $5/KDEX).
2. **KSHRD is unbacked by construction** (H-04). No solvency invariant, no revenue gate,
   first-come-first-served redemption — the last redeemers eat any shortfall.
3. **KRUNE is a freely transferable ERC-20** (H-05). The whitepaper claim *"reputation cannot be
   bought at any price"* is enforced at mint, not at transfer — a whale buys it in one `transfer`.
   The anti-whale gate's arithmetic is provably sound, which is precisely what puts a *computable*
   price on reputation (~$3,162/yr per 10,000 bought KRUNE). Making KRUNE soulbound would enforce
   the invariant in code but changes the economics.
4. **No early exit with yield forfeiture.** `src/logic/staking.ts` supports it off-chain; the
   contract simply reverts while locked.

### Verdict

**Base Sepolia testnet: yes.** **Mainnet without an external professional audit: no.** Nothing
produced here substitutes for that — the contracts are non-upgradeable, so every economic flaw
becomes permanent on deploy.

### Revisit when

- A KSHRD→KDEX pricing decision is made (unblocks the keepback branch, H-02).
- Top-up ergonomics matter enough to justify a scoped per-tranche lock change with a tranche cap,
  partial-exit path and a coordinated bridge update.
- Before any mainnet deploy — re-run the full audit against final HEAD.
