# TradeKarma deployment runbook

You are deploying five contracts and three role grants. Follow this file top to
bottom. It assumes you have read nothing else.

---

## READ THIS FIRST — the one thing that cannot be undone

`KarmaShard.lockRoles()` is **permanent**. No function, no role, no owner and no
upgrade reverses it. After it lands, `grantRole` / `revokeRole` / `renounceRole`
revert on KSHRD for every role, forever, and the set of addresses that may mint
and burn KSHRD is frozen exactly as it stands at that block.

- Lock it **before** Staking holds `MINTER_ROLE` → KSHRD can never be minted.
  Every staker's yield is permanently unclaimable.
- Lock it **before** Treasury holds `BURNER_ROLE` → `redeem()` reverts for
  everyone, forever. The USDC in the Treasury can never come out.
- Lock it with the **wrong** Staking or Treasury address → same outcome, and it
  looks fine until the first unstake.
- Lock it at all → there can never be a Staking v2 or a Treasury v2 on this
  KSHRD. A replacement Treasury could never obtain `BURNER_ROLE`, so outstanding
  shards could never be redeemed against it. See "What locking costs" below.

`Deploy.s.sol` cannot reach `lockRoles()`. There is no flag that turns it on.
It lives alone in `LockRoles.s.sol`, which refuses to run unless you set
`CONFIRM_LOCK_ROLES="I UNDERSTAND THIS IS IRREVERSIBLE"` **and** it can read the
two grants back off the chain itself.

**Do not lock on the same night you deploy.** Nothing breaks by waiting.

---

## Prerequisites

```bash
export PATH="$HOME/.foundry/bin:$PATH"     # foundry is not on the default PATH
forge build                                # must be clean
forge test                                 # 171 tests, all green
```

Import the deploy key into the keystore once, so it never appears in a shell
history, an env file, or a process list:

```bash
cast wallet import tradekarma-deployer --interactive
cast wallet address --account tradekarma-deployer      # note this address
```

Fund that address with a little ETH on the target chain. It needs about
0.012 ETH of gas at 2 gwei for the full deployment.

Then:

```bash
cp .env.example .env
$EDITOR .env
```

Fill in `USDC_ADDRESS`, `ADMIN_ADDRESS`, `EARNING_ENGINE_BRIDGE` and
`KDEX_INITIAL_SUPPLY`. Leave everything under "Deployed addresses" blank for
now. Leave `CONFIRM_LOCK_ROLES` empty. `forge script` loads `.env` from the
project root automatically.

### Getting the four inputs right

| Variable | Gets it wrong how | Recoverable? |
|---|---|---|
| `USDC_ADDRESS` | wrong token, wrong chain, bridged USDbC instead of native USDC | **No.** Treasury reads `decimals()` once and fixes `usdcScale` immutably. |
| `ADMIN_ADDRESS` | an EOA instead of a Safe; a contract that cannot move ERC-20s | **No** for the KDEX supply, which is minted here once and only here. |
| `EARNING_ENGINE_BRIDGE` | the wrong wallet | Yes — the multi-sig can re-grant `MINTER_ROLE` on KRUNE later. KRUNE is never locked. |
| `KDEX_INITIAL_SUPPLY` | typed in whole tokens instead of wei | **No.** KDEX has no mint function after construction. |

`ADMIN_ADDRESS` must be a **wallet**, not the Treasury contract. This is forced
by the constructors: `Treasury` needs KDEX's address, so KDEX is deployed first,
so KDEX's supply recipient cannot be the Treasury. The multi-sig receives the
whole supply and funds the Treasury afterwards with a plain `transfer`. Send it
only what the Treasury needs — `Treasury.recoverToken` deliberately refuses to
move KDEX or USDC back out, so overfunding it is one-way.

The script refuses to deploy if any of the four is missing or zero, if
`ADMIN_ADDRESS == EARNING_ENGINE_BRIDGE`, if `USDC_ADDRESS` has no code on the
target chain, or if `KDEX_INITIAL_SUPPLY < 1e18`.

---

## Base Sepolia (84532) — the full sequence

### 1. Rehearse locally first

Never let a testnet be the first place a script has run. Anvil's keys are public
dev keys and are safe to use here and nowhere else.

```bash
export PATH="$HOME/.foundry/bin:$PATH"
anvil --port 8545 &

# anvil prints its 10 deterministic dev keys on startup; export account 0 as:
#   export ANVIL_KEY=<anvil account 0 private key>
# These are public, well-known LOCAL-ONLY keys. Never use them on a real network.

# a 6-decimal stand-in for USDC
forge create test/mocks/MockERC20.sol:MockERC20 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$ANVIL_KEY" \
  --broadcast --constructor-args "USD Coin" "USDC" 6

USDC_ADDRESS=<printed above> \
ADMIN_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
EARNING_ENGINE_BRIDGE=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC \
KDEX_INITIAL_SUPPLY=100000000000000000000000000 \
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$ANVIL_KEY" \
  --broadcast

# then Verify with the printed addresses (step 3 below), then:
pkill -f "anvil --port 8545"
```

### 2. Simulate against the real chain, then deploy

Simulation first. No `--broadcast`, so nothing is signed and nothing is sent:

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --account tradekarma-deployer
```

Read the `== TradeKarma deployment ==` block it prints. Check the chain id is
**84532**, the USDC decimals are **6**, and the admin and bridge addresses are
the ones you meant. If any of that is wrong, stop here — nothing has happened
yet.

Then deploy:

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --account tradekarma-deployer \
  --broadcast --slow \
  --verify --etherscan-api-key "$BASESCAN_API_KEY"
```

`--slow` waits for each transaction's receipt before sending the next. The role
grants depend on the contract creations having landed; do not skip it.

What this does, in one broadcast:

1. deploys KarmaRune, KarmaDex, KarmaShard, Staking, Treasury (in that order —
   the last two need the first three);
2. `kshrd.grantRole(MINTER_ROLE, staking)` — without it, `unstake()` cannot mint
   yield;
3. `kshrd.grantRole(BURNER_ROLE, treasury)` — without it, `redeem()` reverts for
   everyone;
4. `krune.grantRole(MINTER_ROLE, bridge)` — the off-chain settlement wallet;
5. `krune.revokeRole(MINTER_ROLE, deployer)` — KarmaRune seeds `MINTER_ROLE` on
   whoever deploys it; the deploy key gives it up now that the bridge has it;
6. hands `DEFAULT_ADMIN_ROLE` on KRUNE and KSHRD to `ADMIN_ADDRESS` and
   renounces the deploy key's.

It does **not** call `lockRoles()`.

Copy the `== paste into .env ==` block into your `.env`.

### 3. Verify before you trust it

```bash
forge script script/Verify.s.sol:Verify --rpc-url "$BASE_SEPOLIA_RPC_URL"
```

Read-only: no `--broadcast`, no `--account`, nothing signed. It prints one line
per check and reverts at the end if any failed. Expect `failures 0` and
`== deployment verified ==`.

It checks:

- all five addresses have code, and each reports the symbol you expect
  (catches an address pasted into the wrong variable);
- KDEX total supply equals `KDEX_INITIAL_SUPPLY`, KDEX and KSHRD are 18 decimals;
- KSHRD total supply is zero — any shards on a fresh deployment were conjured,
  not earned;
- `MINTER_ROLE` is on Staking and **not** on Treasury, the multi-sig, or the
  deploy key;
- `BURNER_ROLE` is on Treasury and **not** on Staking, the multi-sig, or the
  deploy key (Staking and Treasury swapped is the mistake this catches, and
  `lockRoles()` would make it permanent);
- KRUNE's `MINTER_ROLE` is on the bridge and on neither the multi-sig nor the
  deploy key;
- `DEFAULT_ADMIN_ROLE` on both tokens is on the multi-sig and **not** on the
  deploy key;
- `Staking.krune/kdex/kshrd` and `Treasury.usdc/kdex/kshrd` all point where they
  should — the two constructors take their arguments in different orders and
  every one of those addresses is immutable;
- both `owner()`s are the multi-sig, and Staking is not paused;
- `Treasury.usdcScale()` equals `10 ** (18 - USDC.decimals())` recomputed from
  the live USDC contract;
- `rolesLocked` equals `EXPECT_ROLES_LOCKED`.

**What it cannot check.** OpenZeppelin's `AccessControl` cannot enumerate role
holders, so `hasRole` proves the right address holds a role but never that it is
the *only* holder. Verify tests the plausible mistakes negatively; to close the
gap completely, scan the grant history yourself:

```bash
cast logs --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --from-block <deployment block> \
  --address "$KSHRD_ADDRESS" \
  'RoleGranted(bytes32,address,address)'
```

Every entry must be one of: `MINTER_ROLE`→Staking, `BURNER_ROLE`→Treasury,
`DEFAULT_ADMIN_ROLE`→deployer (from the constructor), `DEFAULT_ADMIN_ROLE`→
multi-sig. Anything else means someone else can mint your yield token. Do the
same on `$KRUNE_ADDRESS`.

### 4. Fund and smoke-test

From the multi-sig:

```bash
# KDEX for the redemption reserve, from the supply the multi-sig holds
cast send "$KDEX_ADDRESS" "transfer(address,uint256)" "$TREASURY_ADDRESS" <amount>
# USDC backing, via the accounted path
cast send "$USDC_ADDRESS" "approve(address,uint256)" "$TREASURY_ADDRESS" <amount>
cast send "$TREASURY_ADDRESS" "depositFees(uint256)" <amount>
```

Then, with a throwaway test wallet, walk one position end to end: mint KRUNE
from the bridge, `stake`, warp past the 90-day lock (testnet only — you cannot
warp Base Sepolia, so use a position you opened at the start of testing),
`unstake`, `approve` the Treasury, `redeem`. If `unstake` emits
`YieldMintDeferred` instead of minting, `MINTER_ROLE` is not where you think it
is — **stop, and do not lock roles.**

### 5. Lock roles — later, deliberately, and only after all of the above

Not tonight. When you do:

```bash
# Verify must pass FIRST, on this chain, against these exact addresses.
forge script script/Verify.s.sol:Verify --rpc-url "$BASE_SEPOLIA_RPC_URL"

CONFIRM_LOCK_ROLES="I UNDERSTAND THIS IS IRREVERSIBLE" \
forge script script/LockRoles.s.sol:LockRoles \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --account tradekarma-admin \
  --broadcast
```

The script re-derives everything itself before it will broadcast: both contracts
must have code, `Staking.kshrd()` and `Treasury.kshrd()` must both point back at
this exact KSHRD, Staking must hold `MINTER_ROLE`, Treasury must hold
`BURNER_ROLE`, roles must not already be locked, and the sender must hold
`DEFAULT_ADMIN_ROLE`. Any one of those failing aborts before a transaction is
sent.

If `ADMIN_ADDRESS` is a Safe, run the script **without** `--broadcast`: it
prints the `to` address and the calldata (`0x5841b246`) for you to execute
through the Safe UI instead.

Afterwards, set `EXPECT_ROLES_LOCKED=true` in `.env` and run Verify once more.

#### What locking buys, and what it costs

Buys: it closes audit finding C-01. Until it lands, the KSHRD admin can
self-grant `MINTER_ROLE`, mint unlimited shards from nothing, and redeem them
for 100% of the Treasury's USDC and KDEX — two transactions, no timelock, no
way for anyone to intervene. After the lock that path does not exist for anyone,
including a compromised multi-sig.

Costs: the minter and burner sets become permanent, so **there can never be a
Staking v2 or a Treasury v2 on this KSHRD**. Combined with audit M-03 — the
Treasury has no migration path and cannot release USDC except through
`redeem()` — locking converts the unresolved economic findings (H-01, H-02,
H-04) into permanent ones. Lock when the economics are settled, not when the
wiring is.

---

## Base mainnet (8453)

Identical, with `--rpc-url "$BASE_MAINNET_RPC_URL"` and `USDC_ADDRESS` set to
native USDC. Confirm the simulation prints **chain id 8453** before broadcasting.

The audit's verdict on mainnet is **no** — C-01, and the economic model
(H-01/H-02/H-04) needs redesign rather than patching. Read
`docs/SECURITY-AUDIT-CONTRACTS.md` before you consider it.

---

## If the deploy fails halfway

The broadcast is a sequence of transactions, not one atomic transaction. If it
dies partway, the deploy key may still hold `DEFAULT_ADMIN_ROLE` on KSHRD — and
that key can mint KSHRD from nothing. It is a live rug-pull surface for as long
as that is true.

Do not blindly re-run: `forge script --resume` re-sends the pending
transactions, but a plain re-run deploys a **second** set of contracts.

1. Read `broadcast/Deploy.s.sol/<chainid>/run-latest.json` to see exactly which
   transactions landed.
2. Fill in `.env` with whatever addresses do exist and run `Verify.s.sol`. It
   will tell you precisely which roles are missing.
3. Either finish the wiring by hand with `cast send` from the deploy key, or —
   if the contracts are cheap enough to abandon — redeploy clean and ignore the
   orphans. Nobody has staked in them yet.
4. Either way, retire the deploy key afterwards.

`--resume` is safe when the failure was purely an RPC or gas problem and no
transaction was mined out of order. Verify afterwards regardless.

---

## Key handling

- Never put a private key in `.env`. Use `--account` (keystore) or `--ledger`.
- `--private-key` on the command line is for **anvil only**. It lands in your
  shell history.
- If your RPC URL embeds a provider API key, note that forge writes it to
  `cache/<script>/<chainid>/run-latest.json`. That directory is gitignored;
  keep it that way.
- `broadcast/` and `cache/` are gitignored. Do not commit them.
- The deploy key holds KSHRD's admin role for the duration of the deployment and
  nothing afterwards. Treat it as critical for that window and retire it after.

> **Note for whoever owns `.gitignore`:** line 3 is `.env.*`, which matches
> `.env.example` and keeps the template out of the repository. Add
> `!.env.example` so it actually ships.
