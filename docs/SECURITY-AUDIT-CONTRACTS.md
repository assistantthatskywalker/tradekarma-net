# TradeKarma Smart Contract Security Audit — Adversarial Review

| | |
|---|---|
| **Scope** | `contracts/KarmaRune.sol`, `contracts/KarmaDex.sol`, `contracts/KarmaShard.sol`, `contracts/Staking.sol`, `contracts/Treasury.sol` |
| **Commit** | branch `feat/onchain-layer`, HEAD `f54b55f` + **uncommitted working-tree changes** (all five contracts are untracked/modified at review time — line numbers below refer to the working tree as read on 2026-07-28) |
| **Toolchain** | solc 0.8.28, evm_version `cancun`, optimizer on (200 runs), OpenZeppelin Contracts v5.6.1, forge 1.7.1 |
| **Target chain** | Base mainnet (8453) / Base Sepolia (84532) |
| **Method** | Manual review + 27 executed proof-of-concept tests in an out-of-tree Foundry project (`/tmp/tkaudit`). No repository files were modified. |
| **Auditor stance** | Adversarial. The brief was to refute a "clean" report, not confirm it. |

---

## Executive Summary

The contracts are small, readable, and free of the classic implementation bugs. Reentrancy is properly guarded, the arithmetic is checked, the rounding consistently favours the protocol, and the geometric-mean yield curve is genuinely Sybil-resistant — I attacked all of these and could not break them (see "What I Attacked and Could Not Break").

**The problems are not in the code's mechanics. They are in its economics and its trust model, and they are severe.**

Three structural facts dominate this review:

1. **The treasury can be emptied by a single private key.** The `KarmaShard` `DEFAULT_ADMIN_ROLE` holder can self-grant `MINTER_ROLE`, mint unlimited KSHRD from nothing, and redeem it for 100% of the Treasury's USDC and KDEX. There is no cap, no timelock, and no pause on `Treasury.redeem`. Executed, confirmed. (C-01)

2. **There is no price oracle anywhere in the system.** Yield is computed on *token quantities* and paid out in *US dollars* at a hardcoded 1:1. The Treasury loses money whether KDEX is cheap (H-01: staking becomes a money printer) or expensive (H-02: the +10% keepback branch overpays without limit). `YIELD_RATE_PER_SEC` is `constant` — it can never be lowered, not even by governance, not even by the DAO the whitepaper promises. (H-01, H-02, H-04)

3. **Several load-bearing claims in `WHITEPAPER.md` are not implemented in the contracts.** "Reputation cannot be bought at any price" — KRUNE is a plain transferable ERC-20; a whale buys it OTC in one transaction (H-05). "KSHRD cannot be conjured from nothing" — C-01 conjures it. "The yield pool sits at 0% below a minimum user threshold" — no such mechanism exists on-chain. "If you exit early you forfeit the accrued yield but recover your full principal" — early exit is not implemented; principal is hard-locked (M-06). These are not nitpicks; the anti-whale gate *is* the product, and it is enforced at mint but not at transfer.

### Severity counts

| Severity | Count | IDs |
|---|---:|---|
| **Critical** | 1 | C-01 |
| **High** | 5 | H-01 … H-05 |
| **Medium** | 6 | M-01 … M-06 |
| **Low** | 7 | L-01 … L-07 |
| **Informational** | 6 | I-01 … I-06 |
| **Total** | **25** | |

### Verdict (detail in the final section)

- **Public testnet:** Yes, with caveats — fix H-03 first or you will strand testers' principal.
- **Mainnet without an external professional audit:** **No.** Not close. C-01 alone is disqualifying, and the economic model (H-01/H-02/H-04) needs redesign, not patching.

---

## Reproducing the proofs

All PoCs below were executed. To re-run them without touching the repository:

```bash
export PATH="$HOME/.foundry/bin:$PATH"
mkdir -p /tmp/tkaudit && cd /tmp/tkaudit
cp -r <repo>/lib lib && forge install foundry-rs/forge-std --no-git
mkdir -p contracts test && cp <repo>/contracts/*.sol contracts/
cp <repo>/foundry.toml .
printf '@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/\nforge-std/=lib/forge-std/src/\n' > remappings.txt
# paste the PoC bodies below into test/Audit.t.sol
forge test -vv
```

Deployment fixture used throughout: KRUNE/KDEX/KSHRD/Staking/Treasury deployed by a single `admin`, 100,000,000 KDEX fixed supply, Treasury seeded with 1,000,000 USDC and 20,000,000 KDEX, `MINTER_ROLE` on KSHRD → Staking, `BURNER_ROLE` on KSHRD → Treasury.

---

# CRITICAL

## C-01 — KSHRD role admin can mint unlimited yield tokens and drain the entire Treasury

| | |
|---|---|
| **Severity** | Critical |
| **Files** | `contracts/KarmaShard.sol:28`, `contracts/KarmaShard.sol:32`; `contracts/Treasury.sol:66-89` |
| **Category** | Access control / centralization / rug-pull surface |
| **Status** | **Exploit executed and confirmed** |

### Root cause

`KarmaShard`'s constructor grants `DEFAULT_ADMIN_ROLE` to `admin` (line 28). Under OpenZeppelin `AccessControl`, `DEFAULT_ADMIN_ROLE` is the admin of *every* role including itself, so that key can `grantRole(MINTER_ROLE, anyone)` at any time. `mint()` (line 32) has no cap, no rate limit, and no check that the caller is the Staking contract — only that it holds a role the admin can hand out.

`Treasury.redeem` (line 66) then honours *any* KSHRD, regardless of provenance. It never asks whether the shard came from a real staking position. There is no `Pausable` on `Treasury` and no owner-callable stop on `redeem`, so once the mint transaction lands there is no defensive action available.

### Exploit — with numbers

Treasury seeded with **1,000,000 USDC** and **20,000,000 KDEX**.

```solidity
function test_F03_adminMintsShardsAndDrainsTreasuryUSDC() public {
    assertEq(usdc.balanceOf(address(treasury)), 1_000_000e6);

    vm.startPrank(admin);
    kshrd.grantRole(kshrd.MINTER_ROLE(), admin);   // one tx, no timelock
    kshrd.mint(admin, 1_000_000e18);               // conjured, zero staking
    uint256 paid = treasury.redeem(1_000_000e18, true);
    vm.stopPrank();

    assertEq(paid, 1_000_000e6);
    assertEq(usdc.balanceOf(address(treasury)), 0);   // PASSES
    assertEq(usdc.balanceOf(admin),            1_000_000e6);
}
```
```
[PASS] test_F03_adminMintsShardsAndDrainsTreasuryUSDC()
  F-03 drained USDC (6dp): 1000000000000
```

The KDEX reserve goes the same way, and the +10% keepback means it takes **less** KSHRD to take **more** KDEX:

```solidity
function test_F03b_adminCanAlsoTakeAllTreasuryKDEX() public {
    vm.startPrank(admin);
    kshrd.grantRole(kshrd.MINTER_ROLE(), admin);
    kshrd.mint(admin, 18_181_818e18);              // < 20M, because of the bonus
    uint256 paid = treasury.redeem(18_181_818e18, false);
    vm.stopPrank();
    assertGt(paid, 19_999_999e18);                 // PASSES: 19,999,999.8 KDEX
}
```
```
[PASS] test_F03b_adminCanAlsoTakeAllTreasuryKDEX()
  F-03b KDEX extracted (18dp): 19999999800000000000000000
```

Total extraction from a two-transaction sequence by one key: **$1,000,000 USDC + 19,999,999.8 KDEX** — 100% of the Treasury.

### Why "it's a multi-sig in production" is not a sufficient answer

The NatSpec says "multi-sig in production", but nothing in the code enforces it, nothing verifies it post-deploy, and a multi-sig only changes the number of keys, not the fact that **the admin path to total loss is one transaction with zero delay and zero on-chain warning**. There is no `TimelockController`, no mint cap, and no circuit breaker on the payout side. A 3-of-5 multi-sig that is compromised, coerced, or simply wrong drains the treasury just as completely.

Note also `Treasury.recoverToken` (line 95) goes out of its way to protect USDC and KDEX from the *Treasury* owner — a good instinct — but that protection is meaningless because the *KarmaShard* admin can walk through the front door via `redeem`.

### Recommended fix

1. `KarmaShard.mint` should reject any caller other than an immutable `staking` address set at construction, e.g. `address public immutable staking;` + `require(msg.sender == staking)`. If a role is retained, make it non-grantable after setup by revoking `DEFAULT_ADMIN_ROLE` in the deploy transaction.
2. Put `DEFAULT_ADMIN_ROLE` on both `KarmaShard` and `KarmaRune` behind an OpenZeppelin `TimelockController` with a delay ≥ 48h, so any role change is publicly visible before it can be used.
3. Add `Pausable` to `Treasury` with a pause-only guardian role (separate key), so an anomalous mint can be frozen while the timelock runs.
4. Add a supply invariant: `KarmaShard.totalSupply()` should never exceed the sum of accrued-but-unredeemed staking yield. See H-04.

---

# HIGH

## H-01 — Yield is computed on token quantities but paid in US dollars; no oracle. Below a computable KDEX price, staking is a treasury money printer

| | |
|---|---|
| **Severity** | High |
| **Files** | `contracts/Staking.sol:40`, `95-103`, `110`; `contracts/Treasury.sol:71` |
| **Category** | Economic / oracle |
| **Status** | Mechanic confirmed by test; profitability is arithmetic |

### Root cause

`_yieldFor` (line 101) returns `mulDiv(sqrt(krune) * sqrt(kdex), YIELD_RATE_PER_SEC * elapsed, 1e18)` — a pure function of **token counts and time**. `Treasury.redeem` then converts that number to dollars at a hardcoded `1 KSHRD = 1 USDC` (line 71). Nowhere in the system does a price of KDEX or KRUNE appear.

Critically: **both principals are returned in full on `unstake()`** (lines 147-148). Staking therefore has no cost at all beyond illiquidity. Every KSHRD minted is a pure, unhedged dollar liability created against the Treasury.

### Exploit — with numbers

Annual USD liability created by one position = `0.01 × sqrt(K × D)` where K, D are whole-token counts.

Balanced position, `K = D = N`: the position generates `$0.01 × N` per year while tying up `N` KDEX. Ignoring the returned principal, the trade is profitable whenever

```
0.01 × N  >  N × P_kdex × r        ⟺        P_kdex  <  0.01 / r
```

At a 10% opportunity cost of capital that is **P_kdex < $0.10**. KDEX is a brand-new fixed-supply token with no price floor and no liquidity backstop; a launch price below $0.10 is the *expected* case, not the tail case.

Concrete, measured (`test_INFO_dustKruneWhaleYield`):

| Position | Measured 1-yr KSHRD | Treasury liability | KDEX capital at $0.001 |
|---|---:|---:|---:|
| 10,000 KRUNE + 10,000,000 KDEX | 3,162 KSHRD | **$3,162/yr** | $10,000 (returned in full) |
| 1,000,000 KRUNE + 1,000,000 KDEX | 9,999 KSHRD | **$9,999/yr** | $1,000 (returned in full) |

The second row is the alarming one: a position of 1M/1M costs $1,000 of KDEX at a $0.001 launch price, that $1,000 comes back in 90 days, and it mints $9,999 of hard USDC claims per year. That is a **~1,000% annual return on fully-refunded capital**, paid in real dollars out of marketplace fee revenue.

### Aggregate exposure

Maximum annual treasury liability = `0.01 × sqrt(KRUNE_staked × KDEX_staked)` dollars. KDEX is capped at 100,000,000. **KRUNE has no cap.** So:

| KRUNE staked | KDEX staked | Annual USD liability |
|---:|---:|---:|
| 100,000,000 | 100,000,000 | $1,000,000 / yr |
| 10,000,000,000 | 100,000,000 | $10,000,000 / yr |
| 1,000,000,000,000 | 100,000,000 | **$100,000,000 / yr** |

Because KRUNE is minted for reviews, referrals, and on-time shipping, **generosity with reputation points translates directly into dollar-denominated treasury debt via the square root.** The growth team's incentive (issue more KRUNE) is in direct opposition to treasury solvency, and nothing in the contracts couples them.

### Recommended fix

- Denominate the accrual in a *share of the actual yield pool*, not in dollars: `yield_i = pool_usdc × (geo_i × t_i) / Σ(geo × t)`. The treasury can then never owe more than it holds.
- If a fixed rate is kept, it must be a settable parameter behind governance, not `constant`, and it must be quoted against an oracle-priced notional (Chainlink KDEX/USD once a market exists), not raw token counts.
- Cap KRUNE supply, or exclude KRUNE quantity from the dollar-value calculation entirely (use it as a multiplier tier, not a linear term).

---

## H-02 — The KDEX keepback branch has no oracle and overpays without bound when KDEX trades above $0.909

| | |
|---|---|
| **Severity** | High |
| **File** | `contracts/Treasury.sol:79-86` (payout at line 82) |
| **Category** | Economic / oracle |
| **Status** | **Mechanic confirmed by test**; loss quantified below |

### Root cause

```solidity
paid = kshrdAmount + (kshrdAmount * KDEX_KEEPBACK_BONUS_BPS) / 10000;   // line 82
```

The branch pays `1.1 KDEX per 1 KSHRD` **regardless of what KDEX is worth**. The whitepaper (line 268) frames this as "you receive more value for choosing to keep it inside the ecosystem". Nothing keeps it inside the ecosystem — KDEX is freely transferable and the redeemer can sell it in the same block.

This is the mirror image of H-01. H-01 loses money when KDEX is cheap; H-02 loses money when KDEX is expensive. **There is no KDEX price at which the Treasury is safe.**

### Exploit — with numbers

```solidity
function test_F05_kdexBranchIsPriceBlind() public {
    vm.startPrank(admin);
    kshrd.grantRole(kshrd.MINTER_ROLE(), admin);
    kshrd.mint(alice, 1_000_000e18);
    vm.stopPrank();
    vm.prank(alice);
    uint256 paid = treasury.redeem(1_000_000e18, false);
    assertEq(paid, 1_100_000e18);   // PASSES
}
```
```
[PASS] test_F05_kdexBranchIsPriceBlind()
  F-05 KDEX paid for $1,000,000 of KSHRD: 1100000
```

The rational redeemer takes whichever branch is worth more, so KSHRD's true redemption value is `max($1.00, 1.1 × P_kdex)`:

| P_kdex | Value extracted per 1 KSHRD | Treasury overpayment |
|---:|---:|---:|
| $0.50 | $1.00 (USDC branch) | 0% |
| $0.909 | $1.00 | 0% (break-even) |
| $2.00 | $2.20 | **+120%** |
| $5.00 | $5.50 | **+450%** |
| $20.00 | $22.00 | **+2,100%** |

Against the fixture's 20,000,000 KDEX reserve: at $5.00/KDEX the reserve is worth $100,000,000, and it can be fully extracted by **$18,181,818 of KSHRD liabilities** — a $81.8M loss versus honouring the same claims in USDC. A KDEX price appreciation, which is nominally *good news* for the project, is the trigger.

Slippage on the way out limits realised profit but does not fix the accounting: the Treasury has already parted with 1.1 KDEX for a $1 obligation.

### Recommended fix

Price the KDEX leg: `paid = mulDiv(kshrdAmount, 1e18, P_kdex_usd) × 1.1` using a Chainlink feed or a TWAP with staleness and deviation checks. Alternatively cap the branch: `paid = min(1.1 × kshrdAmount, kshrdAmount × 1e18 / floorPrice)`. Until a KDEX price feed exists, disabling the KDEX branch entirely is strictly safer than shipping it.

---

## H-03 — `unstake()` is bricked by KSHRD `MINTER_ROLE` state; principal is permanently trapped and there is no emergency exit

| | |
|---|---|
| **Severity** | High |
| **Files** | `contracts/Staking.sol:130-151` (fatal call at line 145); `contracts/KarmaShard.sol:32` |
| **Category** | DoS / funds trapped / operational |
| **Status** | **Exploit executed and confirmed (two variants)** |

### Root cause

`unstake()` unconditionally calls `kshrd.mint(msg.sender, kshrdMinted)` whenever accrued yield is non-zero (line 144-146). That call reverts with `AccessControlUnauthorizedAccount` unless Staking currently holds `MINTER_ROLE` on KarmaShard. Because the mint happens **inside** the same transaction that returns the principal, the revert takes the whole withdrawal with it.

There is no `emergencyWithdraw`, no "forfeit yield and exit" path, and no owner-callable escape. The code comment at line 127-128 explicitly claims *"Deliberately not pausable — a pause must never trap a user's principal."* That intent is correct and the implementation falsifies it: a **third-party contract's role state** traps the principal just as effectively as a pause would, and `pause()` cannot help.

Every real position hits this. Yield rounds to zero only below a geometric mean of ~406 wei; any position of practical size accrues > 0 within seconds.

### Exploit — with numbers

**Variant A — an admin action (or a compromised KSHRD admin key) permanently traps every staker:**

```solidity
function test_F02_minterRoleRevokeTrapsPrincipalForever() public {
    _fund(alice, 10_000e18, 1_000_000e18);
    vm.prank(alice);
    staking.stake(10_000e18, 1_000_000e18);
    vm.warp(block.timestamp + 200 days);        // lock long expired

    bytes32 mr = kshrd.MINTER_ROLE();
    vm.prank(admin);
    kshrd.revokeRole(mr, address(staking));     // one transaction

    vm.prank(alice);
    vm.expectRevert();                          // AccessControlUnauthorizedAccount
    staking.unstake();

    assertEq(krune.balanceOf(alice), 0);
    assertEq(kdex.balanceOf(alice),  0);
    assertEq(krune.balanceOf(address(staking)), 10_000e18);      // still stuck
    assertEq(kdex.balanceOf(address(staking)),  1_000_000e18);   // still stuck

    vm.prank(admin);
    staking.pause();                            // no help
    vm.prank(alice);
    vm.expectRevert();
    staking.unstake();
}
```
```
[PASS] test_F02_minterRoleRevokeTrapsPrincipalForever()
```

10,000 KRUNE and 1,000,000 KDEX are permanently unrecoverable, by any actor, forever. Scale that across every staker.

**Variant B — the deployment window. This one is an accident waiting to happen, not an attack:**

```solidity
function test_F02b_deployWindowBeforeMinterGrant() public {
    // Staking deployed, MINTER_ROLE grant not yet executed
    st2.stake(10_000e18, 1_000_000e18);
    vm.warp(block.timestamp + 91 days);
    vm.expectRevert();
    st2.unstake();     // PASSES — reverts
}
```
```
[PASS] test_F02b_deployWindowBeforeMinterGrant()
```

The documented deploy order is: deploy KarmaShard → deploy Staking → deploy Treasury → `grantRole(MINTER_ROLE, staking)` → `grantRole(BURNER_ROLE, treasury)`. **Between step 2 and step 4, `Staking` is live and accepting deposits from anyone who finds the address, and every one of those deposits is unwithdrawable until the grant lands.** There is no deploy script in the repository (`script/` does not exist), so this ordering exists only in prose. Skipping or reordering step 4 is a silent, total, permanent failure — it produces no error at deposit time, only 90 days later.

The `BURNER_ROLE` gap is comparatively benign: `redeem` simply reverts until granted, and nothing is lost.

### Recommended fix

1. Wrap the mint so a failure cannot take the principal with it:
   ```solidity
   if (kshrdMinted > 0) {
       try kshrd.mint(msg.sender, kshrdMinted) {} catch { emit YieldMintFailed(msg.sender, kshrdMinted); }
   }
   ```
   or record the shortfall in a `claimable[user]` mapping and expose a separate `claimYield()`.
2. Add `emergencyUnstake()` that returns principal and forfeits accrued yield unconditionally — no external calls at all.
3. Make `Staking` refuse to accept deposits before it is operational: check `kshrd.hasRole(kshrd.MINTER_ROLE(), address(this))` in `stake()`, or deploy `Staking` paused and unpause only after the grant.
4. Write a `forge script` deploy that performs deploy + role grants + a post-condition assertion in one atomic broadcast.

---

## H-04 — KSHRD is unbacked by construction: no solvency invariant, no rate control, no revenue gate, FCFS redemption

| | |
|---|---|
| **Severity** | High |
| **Files** | `contracts/Staking.sol:40` (`constant`), `144-146`; `contracts/Treasury.sol:53-56`, `76`, `83` |
| **Category** | Economic / solvency |
| **Status** | **Insolvency scenario executed and confirmed** |

### Root cause

Three independent gaps compound:

1. **No link between fees and yield.** `depositFees` (line 53) does nothing but move USDC and emit an event. It updates no accounting. `Staking` mints KSHRD on a pure time schedule with no reference to treasury balance.
2. **The rate can never be changed.** `YIELD_RATE_PER_SEC` is `uint256 public constant` (line 40). There is no setter. The whitepaper's headline mitigation — *"the yield pool [is] held at 0% until the platform crosses a minimum active-user threshold"* (WHITEPAPER.md:207) and *"yield is funded only by real revenue"* (line 306) — **has no on-chain implementation whatsoever.** Yield accrues at 1%/yr from the first block, forever, regardless of revenue, and not even a future DAO can turn it down.
3. **The balance check is a race, not a guardrail.** `require(usdc.balanceOf(this) >= paid)` (line 76) is presented in the whitepaper (line 270) as *"the guardrail that prevents the 'print money from nothing' failure mode."* It is not a solvency check. It converts insolvency into first-come-first-served, which is the textbook precondition for a bank run.

There is also **no aggregate accounting anywhere**: `Staking` has only `mapping(address => Position)` with no `totalStaked` or `totalAccrued`. Neither the protocol nor a user can compute outstanding liability on-chain. You cannot monitor a solvency ratio you cannot read.

### Exploit — with numbers

```solidity
function test_F06_yieldIsUnbackedAndOversubscribable() public {
    // Treasury reduced to 10 USDC of backing
    assertEq(usdc.balanceOf(address(treasury)), 10e6);

    _fund(alice, 1_000_000e18, 1_000_000e18);
    vm.prank(alice);
    staking.stake(1_000_000e18, 1_000_000e18);
    vm.warp(block.timestamp + 365 days);
    vm.prank(alice);
    uint256 minted = staking.unstake();      // succeeds — 9,999 KSHRD minted

    vm.prank(alice);
    vm.expectRevert(bytes("TREAS: insufficient USDC"));
    treasury.redeem(minted, true);           // PASSES — claim is worthless
}
```
```
[PASS] test_F06_yieldIsUnbackedAndOversubscribable()
  F-06 KSHRD minted (claims): 9999
  F-06 USDC available:        10
```

**9,999 dollars of claims minted against 10 dollars of reserves — a 999:1 shortfall — with no revert, no warning, and no event indicating a problem.** Combined with M-01 (lock bypass), the users who can exit and redeem first are precisely the ones who gamed the lock; honest 90-day-locked stakers cannot reach the door.

### Recommended fix

- Make `YIELD_RATE_PER_SEC` a governance-settable variable with an upper bound, and default it to **0** so that yield is opt-in per the whitepaper's own promise.
- Track `totalGeoSeconds` in `Staking` and expose `totalOutstandingLiability()`; refuse to accrue when `Treasury.usdcBalance() < outstanding × safetyFactor`.
- Better: switch to pool-share accounting (see H-01) so KSHRD is a claim on a *fraction of a real pool*, making over-issuance structurally impossible rather than merely discouraged.
- Emit an event and/or revert new accrual when the collateral ratio drops below a threshold, so insolvency is observable before it is discovered by a failed redemption.

---

## H-05 — "Reputation cannot be bought" is not enforced: KRUNE is a freely transferable ERC-20 and the minter is an uncapped hot key

| | |
|---|---|
| **Severity** | High |
| **File** | `contracts/KarmaRune.sol:17` (plain `ERC20`), `30-31`, `41-44`; `src/chain/client.ts:60-76` |
| **Category** | Economic / design invariant / key management |
| **Status** | **Confirmed by test; economics quantified** |

### Root cause

The whitepaper states the invariant in the strongest possible terms (WHITEPAPER.md:15): *"There is no purchase path — not off-chain, not on-chain. A whale can buy every investment token on the market and still be locked out of the yield, because the yield gate requires earned reputation they do not have **and cannot acquire with money**."* And line 164: *"the reputation half cannot be bought at any price."*

`KarmaRune` is `contract KarmaRune is ERC20, AccessControl` with **no transfer restriction of any kind**. The invariant is enforced at `_mint` and nowhere else. Anyone who earns KRUNE can sell it; a whale buys it OTC, on a DEX, or through a lending market, in one `transfer`.

```solidity
function test_NEG_kruneIsFreelyTransferable() public {
    krune.mintEarned(alice, 10_000e18, bytes32(0));
    vm.prank(alice);
    krune.transfer(holder, 10_000e18);   // whale buys reputation. PASSES.
    assertEq(krune.balanceOf(holder), 10_000e18);
}
```

### The gate's arithmetic works — that is what makes this finding sharp

I confirmed the geometric mean genuinely punishes imbalance. A whale with 10,000,000 KDEX and 1 wei of KRUNE earns **31,622,776,518 wei = 0.0000000316 KSHRD per year (≈ 3 cents per million years)**. The gate is not a paper defence; the maths is sound.

But that same maths puts a **computable dollar price on reputation**, which is exactly what the design set out to prevent:

| Whale's KDEX | KRUNE purchased | Measured annual yield | Implied rent per KRUNE/yr |
|---:|---:|---:|---:|
| 10,000,000 | 1 wei | $0.00000003 | — |
| 10,000,000 | 10,000 | **$3,162** | $0.32 |
| 10,000,000 | 100,000 | $10,000 | $0.10 |

Because the marginal value of the first KRUNE to a large KDEX holder is unbounded (`d/dK[0.01·√(KD)] → ∞` as `K → 0`), a deep, liquid OTC market for KRUNE is not a risk — it is the **predicted equilibrium**. Earning 10,000 KRUNE honestly takes years of reviews; buying it takes one transaction and, on these numbers, about $3/KRUNE of NPV.

### Compounding key-management issue

`KarmaRune`'s constructor grants the **same address** both `DEFAULT_ADMIN_ROLE` and `MINTER_ROLE` (lines 30-31). `src/chain/client.ts:60-76` signs `mintEarned` from `process.env.DEPLOYER_PRIVATE_KEY` — a **hot key inside a Node process**. If deployment uses that key as `admin` (which the constructor's design actively encourages), a single server compromise yields: unlimited KRUNE minting, the ability to grant `MINTER_ROLE` to attacker addresses, and the ability to revoke it from the legitimate bridge. KRUNE has no supply cap.

### Recommended fix

- If "earned, never bought" is load-bearing, make KRUNE **non-transferable** (soulbound): override `_update` to revert unless `from == address(0)`, `to == address(0)`, or the counterparty is the Staking contract. This is a small change and it converts a marketing claim into an enforced invariant. It also removes the whale's purchase path entirely, which is the stated design goal.
- If transferability is required, delete the "cannot be bought at any price" claim from the whitepaper and site copy — it is currently false and, given that KDEX is offered as an investment, that is a legal exposure as well as a technical one.
- Separate `admin` from `minter` at construction: do not seed `MINTER_ROLE` on the admin. Give `MINTER_ROLE` to the hot bridge key alone, put `DEFAULT_ADMIN_ROLE` behind a timelocked multi-sig, and add a per-epoch mint rate limit so a compromised bridge key has a bounded blast radius.

---

# MEDIUM

## M-01 — `startedAt` is never refreshed on top-up; the 90-day lock is bypassed for 2 wei

| | |
|---|---|
| **Severity** | Medium |
| **File** | `contracts/Staking.sol:77-81` (the `if (!p.active)` guard), `135` |
| **Category** | Economic / broken invariant |
| **Status** | **Exploit executed and confirmed** |

### Root cause

`p.startedAt = block.timestamp` is set **only inside `if (!p.active)`** (lines 77-80). Every subsequent top-up adds principal (lines 82-83) without touching `startedAt`. The lock check (line 135) compares against that stale original timestamp.

### Exploit — with numbers

```solidity
function test_F01_lockBypassViaSeasonedDustPosition() public {
    _fund(alice, 10_000e18 + 1, 5_000_000e18 + 1);

    vm.prank(alice);
    staking.stake(1, 1);                          // 2 wei, day 0
    vm.warp(block.timestamp + 90 days);           // season it, once, ever

    vm.prank(alice);
    staking.stake(10_000e18, 5_000_000e18);       // the real capital
    (,, uint256 startedAt,,,) = staking.positions(alice);
    assertEq(startedAt, 1);                       // PASSES — still day 0

    vm.warp(block.timestamp + 2);                 // one Base block
    vm.prank(alice);
    staking.unstake();                            // PASSES

    assertEq(krune.balanceOf(alice), 10_000e18 + 1);
    assertEq(kdex.balanceOf(alice),  5_000_000e18 + 1);
}
```
```
[PASS] test_F01_lockBypassViaSeasonedDustPosition()
  F-01 lock bypassed. KDEX locked for seconds: 2
[PASS] test_F01_honestUserIsLocked()   // identical position, first stake at t=0: reverts "STAKE: locked" at day 89
```

**5,000,000 KDEX locked for 2 seconds instead of 90 days, at a one-time setup cost of 2 wei.**

### Impact

The setup is permanent — one dust stake, one 90-day wait, and that wallet is exempt from the lock forever. Direct extraction is zero (yield is strictly time-proportional; a zero-duration stake earns zero, confirmed by test), which is why this is Medium and not High. But:

- The lock is the *only* commitment device in the design; the whitepaper (line 138) sells it as the thing that makes yield "the reward for aligned commitment". It provides no TVL stickiness whatsoever against a prepared actor.
- It creates a **strict ordering advantage during insolvency (H-04)**. When outstanding KSHRD exceeds treasury USDC, the seasoned-dust user exits and redeems on demand while honest stakers are contractually barred from the door for up to 90 days. That is a real transfer of value from honest users to the exploiter.
- It removes the friction that made the H-01 borrow-and-farm trade impractical, turning it into a liquid, repeatable position.

### Recommended fix

Either reset the clock on top-up (`p.startedAt = block.timestamp;` unconditionally — simplest, mildly punitive to honest top-ups), or track a per-deposit weighted average:
```solidity
p.startedAt = (p.startedAt * oldGeo + block.timestamp * newGeo) / (oldGeo + newGeo);
```
or make each deposit its own indexed position with its own lock.

---

## M-02 — `mintEarned` has no `reasonHash` replay protection, and the off-chain settlement ledger is in-memory

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `contracts/KarmaRune.sol:41-44`; `src/chain/settlement.ts:86-136` |
| **Category** | Replay / accounting integrity |
| **Status** | **Confirmed by test** |

### Root cause

`reasonHash` is emitted for auditability but never recorded or checked. The same hash mints again, and again:

```solidity
function test_F12_reasonHashReplay() public {
    bytes32 reason = keccak256("earning-event-uuid-1234");
    krune.mintEarned(alice, 500e18, reason);
    krune.mintEarned(alice, 500e18, reason);
    krune.mintEarned(alice, 500e18, reason);
    assertEq(krune.balanceOf(alice), 1_500e18);   // PASSES
}
```
```
[PASS] test_F12_reasonHashReplay()
  F-12 KRUNE minted for ONE event: 1500
```

The off-chain layer is the *only* thing preventing duplicates, and its own documentation (`src/chain/settlement.ts:24-38`) admits two unhandled paths:

> *"If the RPC call to broadcast the transaction times out, we cannot tell from here whether it was actually mined. This layer marks that attempt FAILED and relies on retry"*
>
> *"Persistence across process restarts. The ledger is in-memory only"*

An in-memory `Map` means **a backend restart wipes the entire settlement history**. Re-running the earning backlog after a restart re-mints every event, and `KarmaRune` accepts all of it because the reason hash is unchecked and the amounts are uncapped.

### Impact

Silent, unbounded reputation inflation from ordinary operational events (a pod restart, an RPC timeout, a nonce race). Via H-01, inflated KRUNE converts directly into dollar-denominated treasury liability: doubling the KRUNE float multiplies every staker's yield by √2 = 1.41×.

### Recommended fix

Move the idempotency guard on-chain, where it belongs. Five lines:
```solidity
mapping(bytes32 => bool) public settled;
function mintEarned(address user, uint256 amount, bytes32 reasonHash) external onlyRole(MINTER_ROLE) {
    require(!settled[reasonHash], "KRUNE: already settled");
    settled[reasonHash] = true;
    _mint(user, amount);
    emit Earned(user, amount, reasonHash);
}
```
This makes the retry path safe by construction and removes the dependency on off-chain durability entirely. Separately, back `SettlementLedger` with a database before mainnet.

---

## M-03 — USDC blacklist or pause permanently strands the Treasury's USDC; `recoverToken` blocks the rescue and there is no migration path

| | |
|---|---|
| **Severity** | Medium |
| **File** | `contracts/Treasury.sol:76-78`, `95-100` |
| **Category** | External dependency / funds trapped |
| **Status** | **Exploit executed and confirmed** |

### Root cause

USDC on Base is an **upgradeable proxy with a blacklist and a global pause**, controlled by Circle. If the Treasury address is blacklisted (sanctions association, a tainted incoming fee deposit, a false positive), `usdc.safeTransfer` at line 78 reverts forever.

`recoverToken` (line 95) hard-blocks USDC and KDEX by design:
```solidity
require(token != address(usdc) && token != address(kdex), "TREAS: backing asset");
```
This is a good anti-rug instinct with a bad failure mode: **the only exit for USDC is `redeem`, and `redeem` is the exact thing that breaks.** There is no owner withdrawal, no migration function, and no upgrade path. `Treasury` is not upgradeable and holds no escape hatch.

### Exploit — with numbers

```solidity
function test_F08_usdcBlacklistTrapsTreasuryForever() public {
    usdc.mint(address(treasury), 5_000_000e6);
    vm.prank(alice);
    assertEq(treasury.redeem(500e18, true), 500e6);   // works normally

    usdc.blacklist(address(treasury));                // Circle acts

    vm.prank(alice);
    vm.expectRevert(bytes("USDC: blacklisted"));
    treasury.redeem(500e18, true);

    vm.prank(admin);
    vm.expectRevert(bytes("TREAS: backing asset"));
    treasury.recoverToken(address(usdc), admin, 1);   // cannot rescue

    assertEq(usdc.balanceOf(address(treasury)), 4_999_500e6);   // PASSES
}
```
```
[PASS] test_F08_usdcBlacklistTrapsTreasuryForever()
  F-08 USDC permanently stranded (6dp): 4999500000000
```

**$4,999,500 permanently unrecoverable by anyone.** A global USDC pause produces the same outcome for its duration.

The same argument applies to any future need to migrate to a Treasury v2 — for example, to fix H-01, H-02, or H-04. The current design makes the treasury **immutable and unmigratable**, which is the opposite of what a system with unresolved economic flaws needs.

### Recommended fix

Add a timelocked migration escape hatch: `migrate(address newTreasury)` gated by `onlyOwner` + a ≥7-day `TimelockController` + an event at proposal time, so users can see it coming and redeem first. That preserves the anti-rug property (nobody can move funds without a week of public notice) while removing the permanent-loss failure mode.

---

## M-04 — `BURNER_ROLE` can confiscate any holder's KSHRD with no allowance

| | |
|---|---|
| **Severity** | Medium |
| **File** | `contracts/KarmaShard.sol:41-43` |
| **Category** | Access control / centralization |
| **Status** | **Confirmed by test** |

### Root cause

```solidity
function burnFrom(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
    _burn(from, amount);
}
```

The `burnFrom` name carries the ERC20Burnable convention of allowance-based burning; this implementation ignores allowances entirely. The NatSpec justifies it — *"no allowance is used because the role itself is the authorization"* — which is fine for the Treasury's actual usage (`redeem` only ever burns `msg.sender`), but the **role is not scoped to that usage**.

```solidity
function test_F04_burnerRoleConfiscatesArbitraryBalances() public {
    kshrd.mint(alice, 500e18);
    kshrd.grantRole(kshrd.BURNER_ROLE(), admin);
    kshrd.burnFrom(alice, 500e18);          // alice never approved anything. PASSES.
    assertEq(kshrd.balanceOf(alice), 0);
}
```

Any `BURNER_ROLE` holder — and `DEFAULT_ADMIN_ROLE` can grant it to itself at will, per C-01 — can zero out any user's yield claim. Combined with C-01, an admin can both mint themselves claims and delete everyone else's.

It also means **any future integrator granted `BURNER_ROLE`** (a Treasury v2, a bridge, a partner protocol) inherits blanket confiscation power over all holders, not just over its own users.

### Recommended fix

Scope the burn to the caller's own tokens plus an explicit allowance path:
```solidity
function burn(uint256 amount) external { _burn(msg.sender, amount); }
function burnFrom(address from, uint256 amount) external {
    _spendAllowance(from, msg.sender, amount);
    _burn(from, amount);
}
```
The Treasury then takes an approval before redeeming, which is standard, auditable UX and removes the confiscation power entirely.

---

## M-05 — `pause()` stops deposits but not liability accrual, and there is no circuit breaker anywhere on the Treasury

| | |
|---|---|
| **Severity** | Medium |
| **Files** | `contracts/Staking.sol:67` (`whenNotPaused` on `stake` only), `105-114`; `contracts/Treasury.sol:20` (no `Pausable`) |
| **Category** | Incident response / DoS |
| **Status** | **Confirmed by test** |

### Root cause

`_accrue` is a pure function of `block.timestamp` and position size; nothing consults the pause flag. `unstake()` is deliberately not pausable (correct, per H-03's intent) and mints in full regardless. `Treasury` inherits only `Ownable` and `ReentrancyGuard` — **there is no pause on `redeem` at all.**

```solidity
function test_F09_pauseDoesNotStopAccrual() public {
    staking.stake(1_000_000e18, 1_000_000e18);
    vm.prank(admin);
    staking.pause();                                  // emergency stop engaged
    vm.warp(block.timestamp + 365 days);
    assertGt(staking.pendingKshrd(alice), 9_999e18);  // PASSES
    vm.prank(alice);
    assertEq(staking.unstake(), staking.pendingKshrd(alice));   // mints in full
}
```
```
[PASS] test_F09_pauseDoesNotStopAccrual()
  F-09 liability at pause: 0
  F-09 liability +1yr paused (KSHRD/$): 9999
```

### Impact

During an incident — an exploit in progress, a discovered bug, a treasury shortfall — the operators' only lever stops *new deposits*, which is the one thing that is not hurting them. The liability keeps compounding at 1%/yr of the entire staked geometric mean, and the treasury keeps paying out on demand with no way to halt. If the system is paused for six months while H-01 is redesigned, six months of additional dollar claims accrue against a treasury that cannot be defended.

### Recommended fix

- Add a `paused` check inside `_accrue` (accrue up to the pause timestamp, then freeze the clock; resume on unpause).
- Add `Pausable` to `Treasury` with a dedicated guardian role that can *only* pause — not unpause, not move funds. That gives incident response a real lever without adding a new rug vector.

---

## M-06 — Documented early-exit-with-yield-forfeit is not implemented; principal is hard-locked for 90 days

| | |
|---|---|
| **Severity** | Medium |
| **File** | `contracts/Staking.sol:130-151`; contradicts `WHITEPAPER.md:138` |
| **Category** | Spec divergence / funds availability |
| **Status** | Confirmed by reading + `test_F01_honestUserIsLocked` |

The whitepaper is explicit:

> *"If you exit **early**, before the 90-day lock matures, you **forfeit the accrued yield** but recover your full KRUNE and KDEX principal — the penalty is the lost yield, never the principal."* (WHITEPAPER.md:138)

The contract implements no such path. `unstake()` is the only exit and it reverts with `"STAKE: locked"` until `startedAt + 90 days`:

```
[PASS] test_F01_honestUserIsLocked()   // 10,000 KRUNE + 5,000,000 KDEX, day 89 -> reverts
```

Users who stake on the strength of the published terms will discover on day 1 that their principal is unavailable for 90 days. This is a user-harm and disclosure problem independent of any exploit, and it is amplified by H-03 (where the principal may never come back at all) and M-01 (where a prepared actor is exempt from the lock the honest user is subject to).

Fix: implement the documented `exitEarly()` (return principal, zero `accruedKshrd`, no external mint call — which also gives you the H-03 emergency exit for free), or correct the whitepaper and all front-end copy before launch.

---

# LOW

**L-01 — Single-step `Ownable` on `Staking` and `Treasury`; `renounceOwnership` is reachable.**
`contracts/Staking.sol:22`, `contracts/Treasury.sol:20`. A `transferOwnership` to a mistyped or non-existent address irrecoverably loses `pause`/`unpause` (Staking) and `recoverToken` (Treasury). `renounceOwnership()` is inherited and unguarded — one call permanently removes the only emergency lever. Use `Ownable2Step` and override `renounceOwnership()` to revert.

**L-02 — Treasury validates USDC decimals but silently assumes KDEX is 18 decimals.**
`contracts/Treasury.sol:44-49` reads `IERC20Metadata(_usdc).decimals()` and rejects > 18 — good. The KDEX branch hardcodes the assumption in a comment only (line 80: *"KDEX is 18-decimal like KSHRD, so no scaling is needed"*) with no constructor check. Since `_kdex` is an arbitrary constructor address, a wrong deployment misprices the keepback branch by orders of magnitude with no revert. Add `require(IERC20Metadata(_kdex).decimals() == 18, "TREAS: KDEX decimals")`.

**L-03 — Constructor circularity forces 100% of the KDEX supply into an EOA at genesis.**
`contracts/KarmaDex.sol:21-24`, `contracts/Treasury.sol:42`. `Treasury` needs the KDEX address, so KDEX must be deployed first, so KDEX's `treasury` parameter **cannot** be the Treasury contract. Confirmed:
```
[PASS] test_F11_kdexSupplyCannotGoToTreasuryAtConstruction()
   kdex.balanceOf(admin)             == 100_000_000e18
   kdex.balanceOf(address(treasury)) == 0
```
The NatSpec ("minted to treasury") is therefore unachievable as written. The entire 100M supply sits in one externally-owned address with no vesting, no lock, and no distribution logic in code. Use CREATE2 to precompute the Treasury address, or add a one-shot `initialize` — and put the team/investor tranches behind an on-chain vesting contract rather than trusting a manual distribution.

**L-04 — Fee-on-transfer / rebasing principal tokens would break the staking ledger.**
`contracts/Staking.sol:73-74, 82-83` credit the *requested* amount, not the *received* amount. Not exploitable with the current hookless OZ tokens, but confirmed reachable if a non-standard token is ever configured:
```
[PASS] test_F10_feeOnTransferPrincipalUnderfunded()
  credited: 4000e18   actually held: 3960e18   -> last withdrawer reverts
```
Also `Treasury.depositFees` (line 55) emits the pre-fee amount. Since the token addresses are `immutable` this is a deployment-discipline issue, not a live bug — but measure balance deltas if there is any chance of a non-standard token.

**L-05 — Sub-unit KSHRD is redeemable for KDEX but not for USDC.**
`contracts/Treasury.sol:71-72`. Any amount below `1e12` wei reverts with `"TREAS: below one USDC unit"` while the KDEX branch accepts it at 1.1×. Asymmetric and mildly confusing; no value leak (the USDC dust accounting is exact — see I-01).

**L-06 — Floating pragma.** All five files declare `pragma solidity ^0.8.24` while `foundry.toml` pins 0.8.28. Pin the source pragma to the audited compiler so verification and any future re-compile are deterministic.

**L-07 — Missing sanity bounds in token constructors.** `KarmaDex` accepts `initialSupply == 0` (`contracts/KarmaDex.sol:21`), permanently creating a worthless token with no recovery. `KarmaRune` has no supply cap at all (`contracts/KarmaRune.sol:41`), which is what makes the H-01 liability table unbounded.

---

# INFORMATIONAL

**I-01 — The rounding is correct and consistently favours the protocol.** Verified, not a finding — recorded so it is not re-audited. `Math.sqrt` floors, `Math.mulDiv` floors, the USDC redemption burns exactly `paid * usdcScale` so the user keeps unpaid dust rather than being over- or under-credited. Fuzzed 256 runs: `sqrt(a)*sqrt(b) <= sqrt(a*b)` always holds.

**I-02 — `depositFees` performs no accounting.** `contracts/Treasury.sol:53-56` moves USDC and emits an event. The contract has no concept of a "yield pool" distinct from its balance, and cannot distinguish fee revenue from a donation or a stray transfer. Prerequisite for the H-04 fix.

**I-03 — `Staking` exposes no aggregate state.** No `totalStaked`, no `totalAccrued`, no position enumeration. Outstanding liability is not computable on-chain by anyone, which makes automated solvency monitoring impossible and makes the H-04 fix harder to retrofit.

**I-04 — `stake()` violates checks-effects-interactions.** `contracts/Staking.sol:73-83` performs both `safeTransferFrom` calls *before* writing `p.krune`/`p.kdex`. Currently safe only because of `nonReentrant` and because KRUNE/KDEX are hookless OZ ERC-20s. I attempted to exploit the resulting stale-read window in `pendingKshrd` and could not — there is no on-chain consumer of that view. Still, move the state writes above the transfers; the guard should be defence in depth, not the only defence.

**I-05 — `Treasury.redeem` is permissionless, contradicting the whitepaper.** WHITEPAPER.md:259 says the Treasury *"pays out redemptions only when called by the authorized staking flow."* It does not — `redeem` (line 66) accepts any KSHRD holder. This is correct and desirable behaviour (KSHRD is a bearer instrument), but the documentation should say so, because it means KSHRD bought on a secondary market, airdropped, or minted per C-01 redeems identically.

**I-06 — `recoverToken` can sweep KSHRD.** `contracts/Treasury.sol:95-100` excludes only USDC and KDEX, so KSHRD accidentally sent to the Treasury can be recovered by the owner and redeemed. Low impact (only affects users who misdirect tokens), but worth adding to the exclusion list or routing to a burn.

---

# What I Attacked and Could NOT Break

This section is deliberately detailed so this ground does not need re-auditing. Everything here was tested, not assumed.

### Reentrancy — clean
- `stake`, `unstake`, `redeem`, and `depositFees` all carry `nonReentrant`, with `Staking` and `Treasury` holding independent guards.
- `unstake()` (`Staking.sol:142`) executes `delete positions[msg.sender]` **before** any external call. Double-unstake confirmed to revert with `"STAKE: none"`.
- `redeem` burns before paying out in both branches (lines 77/84).
- **Read-only reentrancy against `pendingKshrd`:** the function makes no external calls and no on-chain contract consumes it. A stale-read window does exist inside `stake()` (see I-04) but is unreachable with the configured hookless tokens.
- **Cross-contract reentrancy** via a hostile token callback from `Staking` into `Treasury.redeem` (separate guards, so the guard does not block it): confirmed harmless — the in-flight staking position has no bearing on KSHRD balances or Treasury state.
- `recoverToken` is not `nonReentrant` and takes an arbitrary token address, but it is `onlyOwner` and the backing-asset `require` re-checks on every entry, so a malicious token cannot escalate.

### The geometric-mean yield curve — mathematically sound
- **Sybil splitting gives no advantage.** Measured: one position of 1,000,000 KRUNE + 4,000,000 KDEX over 90 days yields `4931506836288000000000`; the same capital split across ten wallets yields `4931506836269662605840` — **0.0000004% worse**. Cauchy–Schwarz guarantees `Σ√(kᵢdᵢ) ≤ √(ΣkᵢΣdᵢ)` with equality only at exact proportionality, and floor-rounding makes the split strictly lossy. Splitting can never beat a single position.
- **No retroactive boost on top-up.** `_accrue(msg.sender)` is called at `Staking.sol:71`, *before* the balances are increased at lines 82-83. Measured: a 1-token position held one year then topped up 1000× still shows only `9999999973584000` accrued (0.00999999997 KSHRD) — the earlier period is correctly valued at the earlier size. This is the obvious bug in this pattern and it is not present.
- **Accrual-frequency gaming does not inflate yield.** 1,000 forced accruals over 1,000 seconds produced `317097918999365000` versus `317097918999365804` for a single accrual — flooring means frequent accrual is always *worse*. There is no dust-accumulation attack.
- **`sqrt(a)*sqrt(b)` cannot overflow.** `Math.sqrt(type(uint256).max) == type(uint128).max`, and `(2¹²⁸−1)² = 1.1579e77 < 2²⁵⁶`. The NatSpec claim at `Staking.sol:88-93` is correct. Verified by execution, not by argument.
- **`_yieldFor`'s `mulDiv` cannot be pushed to revert.** Worst reachable case (KRUNE at `type(uint256).max`, KDEX at the full 100M supply) gives a geometric mean of `3.40e51` and a one-year yield of `3.40e49` — roughly 27 orders of magnitude below the `2²⁵⁶` revert threshold. There is no griefing DoS on `pendingKshrd` or `unstake` through arithmetic.
- **`YIELD_RATE_PER_SEC` is correct.** `317097919 × 31,536,000 / 1e18 = 0.0099999999736`, i.e. 0.99999999736%/yr. The truncation costs 2.6e-8 of the rate, in the protocol's favour. The NatSpec's arithmetic checks out.

### The anti-whale gate — arithmetically real
- `stake(0, anything)` reverts (`"STAKE: need earned KRUNE (reputation)"`); `stake(anything, 0)` reverts likewise.
- A whale with 10,000,000 KDEX and **1 wei** of KRUNE earns **31,622,776,518 wei/yr** — about 3 cents per million years. The geometric mean genuinely destroys imbalanced positions. The gate fails only at the market layer (H-05), never at the arithmetic layer.

### Arithmetic and rounding — no leak found
- Checked arithmetic throughout (0.8.28); **no `unchecked` blocks anywhere** in the five contracts.
- USDC redemption dust: `paid = kshrdAmount / 1e12`, `burned = paid × 1e12`. Verified the holder retains exactly `kshrdAmount − burned` and the Treasury pays exactly for what it destroys. No free value in either direction.
- KDEX keepback bonus floors. `p.accruedKshrd` cannot be overflowed at any reachable supply.

### Griefing and DoS against other users — none found
- Every position mutation is keyed on `msg.sender`. There is no third-party `stakeFor`/`unstakeFor`, so nobody can force another user into or out of a position, dilute them, or reset their lock.
- No shared reward pool, no price, no snapshot, and no epoch boundary — I found **no MEV or front-running extraction path** on `stake`, `unstake`, or `redeem` beyond the ordinary insolvency race described in H-04.
- Donating tokens to `Staking` or `Treasury` changes nothing (no balance-derived accounting on the staking side).
- Neither contract has a `receive()`, so forced-ETH tricks are irrelevant.

### Owner powers on Staking and Treasury — correctly minimal
- `Staking`'s owner can *only* `pause`/`unpause`. There is no sweep, no rescue, no rate setter, no way to touch principal. This is genuinely well-scoped and I could not find a path around it.
- `Treasury`'s owner cannot touch USDC or KDEX: `recoverToken`'s `require` at line 96 holds under every input I tried, including reentrant callbacks from a malicious recovered token.
- **The rug-pull surface is entirely on `KarmaShard`'s and `KarmaRune`'s `DEFAULT_ADMIN_ROLE`, not on the `Ownable` contracts.** If C-01 and H-05's key management are fixed, the remaining owner powers are defensible.

---

# Verdict

### Is this safe to deploy to a public testnet?

**Yes, with one blocking prerequisite.** Fix **H-03** first, or write the deploy as a single atomic `forge script` that grants `MINTER_ROLE` in the same broadcast — otherwise testers who stake during the deployment window will have their principal permanently trapped, which produces a bad, irreversible, and entirely avoidable first impression. Everything else is acceptable on a testnet, provided the testnet deployment is publicly labelled as economically unmodelled and no real value is bridged to it. Testnet is also the right place to gather the data you need for H-01/H-04 (what does the aggregate geometric mean actually look like at realistic user counts?).

### Is it safe for mainnet without an external professional audit?

**No. Emphatically not.**

Three independent reasons, any one of which is disqualifying:

1. **C-01 is a working, two-transaction total drain by a single key**, with no timelock, no cap, and no ability for anyone to intervene. That is not a residual risk to be disclosed; it is an open door.

2. **The economic model has no oracle and cannot be corrected after deployment.** H-01 and H-02 mean the Treasury loses money whether KDEX is cheap *or* expensive. `YIELD_RATE_PER_SEC` is `constant`, `Treasury` is not upgradeable, and M-03 shows there is no migration path — so **these flaws cannot be fixed post-deployment without abandoning the contracts and the funds in them.** This is the single most important structural point in this report: the design's immutability, which is a virtue when the design is right, converts every economic error here into a permanent one. The economics need redesign (pool-share accounting, an oracle, a settable rate), not parameter tuning.

3. **The system's headline invariant is not enforced in code.** The whitepaper says reputation "cannot be bought at any price" and that KSHRD "cannot be conjured from nothing". Both statements are false against these contracts (H-05, C-01). Since KDEX is offered as an investment token and KSHRD redeems for USDC — which the whitepaper itself flags at line 292 as *"potentially requiring a banking license"* — the gap between published claims and enforced behaviour is a legal exposure as much as a technical one. Fix the code or fix the copy, but do not ship them contradicting each other.

**Recommended path to mainnet:**

1. Fix C-01, H-03, H-05 (key management + soulbound KRUNE), M-02, M-04. These are small, well-understood changes.
2. Redesign the yield and redemption economics around pool-share accounting and/or a real price oracle (H-01, H-02, H-04). Budget for this properly — it is a design cycle, not a patch.
3. Add a timelocked migration path and a Treasury pause (M-03, M-05) so that the *next* mistake is survivable.
4. Build the test suite out to full branch coverage plus invariant/fuzz tests on the solvency ratio, and write the deploy as an atomic, asserted `forge script`.
5. **Then** commission an external professional audit, and separately an economic/token-model review — the two are different specialisms and this system needs both.
6. Launch with a capped TVL and a public solvency dashboard for the first quarter.

The implementation craft here is good; the code is clean, well-commented, and free of the bugs that catch most first drafts. The problem is that a correct implementation of an unsound economic model just loses money more reliably.

---

*Audit performed 2026-07-28. Read-only: no repository files outside this document were created, modified, or deleted. All 27 proof-of-concept tests were executed in an isolated Foundry project at `/tmp/tkaudit` against verbatim copies of the contracts.*
