/**
 * TradeKarmaChain — typed adapter over the 5 on-chain contracts.
 * Wraps a viem public client (reads) and an optional wallet client (writes)
 * with methods matching the Solidity ABI 1:1. This is the only place
 * application code should call readContract/writeContract for TradeKarma
 * contracts — the ABI and address wiring live here and in ./abis + ./config.
 */

import type { Address, Hash } from 'viem';
import { formatUnits, keccak256, parseUnits, toHex } from 'viem';
import { ChainId, ContractAddresses, getContractAddresses } from './config';
import type { TradeKarmaPublicClient, TradeKarmaWalletClient } from './client';
import { karmaDexAbi, karmaRuneAbi, karmaShardAbi, stakingAbi, treasuryAbi } from './abis';

/** All TradeKarma tokens (KRUNE, KDEX, KSHRD) use 18 decimals. */
export const KARMA_DECIMALS = 18;
/**
 * USDC uses 6 decimals — the one place this project deals with two decimal
 * scales. This is an assumption, not a guarantee: Treasury computes its own
 * `usdcScale` on-chain from the real USDC token's `decimals()` at
 * construction, since that can differ per deployment/chain. These constants
 * (and toUsdcUnits/fromUsdcUnits below) assume standard 6-decimal USDC, as
 * used on Base. Call `assertStandardUsdcScale()` once during setup to verify
 * a given Treasury deployment actually matches before relying on them.
 */
export const USDC_DECIMALS = 6;

/**
 * AccessControl role ids for KarmaRune / KarmaShard, computed locally to
 * match Solidity's `keccak256("MINTER_ROLE")` / `keccak256("BURNER_ROLE")`
 * exactly (cross-checked against `cast keccak`) — this avoids an RPC round
 * trip just to ask a contract for its own constant role id. Both KarmaRune
 * and KarmaShard use the same MINTER_ROLE value (same string, different
 * contracts/storage); KarmaShard additionally defines BURNER_ROLE.
 */
export const MINTER_ROLE: Hash = keccak256(toHex('MINTER_ROLE'));
export const BURNER_ROLE: Hash = keccak256(toHex('BURNER_ROLE'));

function strictUnits(amount: string | number, decimals: number): bigint {
  if (typeof amount === 'number' && (!Number.isSafeInteger(amount) || amount < 0)) {
    throw new Error('use a decimal string for fractional amounts');
  }
  const value = String(amount);
  if (!/^(0|[1-9][0-9]*)(\.[0-9]+)?$/.test(value) || (value.split('.')[1]?.length ?? 0) > decimals) throw new Error('invalid amount or excess precision');
  return parseUnits(value, decimals);
}

/** Human amount (e.g. "12.5" or 12.5) -> KRUNE/KDEX/KSHRD base units. */
export function toKarmaUnits(amount: string | number): bigint {
  return strictUnits(amount, KARMA_DECIMALS);
}

/** KRUNE/KDEX/KSHRD base units -> human decimal string. */
export function fromKarmaUnits(amount: bigint): string {
  return formatUnits(amount, KARMA_DECIMALS);
}

/** Human USDC amount (e.g. "12.50" or 12.5) -> USDC base units (6 decimals). */
export function toUsdcUnits(amount: string | number): bigint {
  return strictUnits(amount, USDC_DECIMALS);
}

/** USDC base units (6 decimals) -> human decimal string. */
export function fromUsdcUnits(amount: bigint): string {
  return formatUnits(amount, USDC_DECIMALS);
}

export interface StakingPosition {
  krune: bigint;
  kdex: bigint;
  startedAt: bigint;
  weight: bigint;
  rewardPerWeightPaid: bigint;
  accruedUsdc: bigint;
  active: boolean;
}

function requireAddress(addresses: ContractAddresses, key: keyof ContractAddresses): Address {
  const address = addresses[key];
  if (!address) {
    throw new Error(`TradeKarmaChain: no deployed address for "${key}" on this chain yet`);
  }
  return address;
}

export class TradeKarmaChain {
  private readonly addresses: ContractAddresses;

  constructor(
    private readonly chainId: ChainId,
    private readonly publicClient: TradeKarmaPublicClient,
    private readonly walletClient?: TradeKarmaWalletClient,
    addresses?: ContractAddresses
  ) {
    this.addresses = addresses ? { ...addresses } : getContractAddresses(chainId);
    if (publicClient.chain && publicClient.chain.id !== chainId) throw new Error("public client chain mismatch");
    if (walletClient?.chain && walletClient.chain.id !== chainId) throw new Error("wallet client chain mismatch");
  }

  getSettlementDomain() {
    return { chainId: this.chainId, karmaRune: requireAddress(this.addresses, 'karmaRune') };
  }

  async kruneSettlementDigest(reasonHash: Hash): Promise<Hash> {
    return this.publicClient.readContract({ address: requireAddress(this.addresses, 'karmaRune'),
      abi: karmaRuneAbi, functionName: 'settlementDigest', args: [reasonHash], blockTag: 'finalized' });
  }

  async waitForMintReceipt(hash: Hash): Promise<'success' | 'reverted'> {
    const receipt = await this.publicClient.waitForTransactionReceipt({ hash, confirmations: 1, timeout: 60_000 });
    return receipt.status;
  }

  async approveKdexForStaking(amount: bigint): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({ address: requireAddress(this.addresses, 'karmaDex'), abi: karmaDexAbi,
      functionName: 'approve', args: [requireAddress(this.addresses, 'staking'), amount], account: wallet.account, chain: wallet.chain });
  }

  async approveUsdcForFees(amount: bigint): Promise<Hash> {
    const token = await this.publicClient.readContract({ address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi, functionName: 'usdc' });
    const wallet = this.writer();
    return wallet.writeContract({ address: token, abi: karmaDexAbi, functionName: 'approve',
      args: [requireAddress(this.addresses, 'staking'), amount], account: wallet.account, chain: wallet.chain });
  }

  private writer(): TradeKarmaWalletClient {
    if (!this.walletClient) {
      throw new Error('TradeKarmaChain: no wallet client configured; write methods are unavailable');
    }
    return this.walletClient;
  }

  // ---- KarmaRune (KRUNE) — reputation, earned-only ----

  async kruneBalanceOf(user: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaRune'),
      abi: karmaRuneAbi,
      functionName: 'balanceOf',
      args: [user],
    });
  }

  async kruneTotalSupply(): Promise<bigint> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaRune'),
      abi: karmaRuneAbi,
      functionName: 'totalSupply',
    });
  }

  /**
   * MINTER-role only on-chain; reverts if the wallet account is not a
   * minter. Also reverts if `reasonHash` was already settled (KarmaRune's
   * `require(!settled[reasonHash])`) — that guard is what makes a retried
   * settlement safe against double-minting even across a process restart.
   * See settlement.ts for how the on-chain `settled()` read is used to avoid
   * submitting a transaction that is doomed to hit this revert.
   */
  async mintEarned(user: Address, amount: bigint, reasonHash: Hash): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'karmaRune'),
      abi: karmaRuneAbi,
      functionName: 'mintEarned',
      args: [user, amount, reasonHash],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /** True if `account` currently holds MINTER_ROLE on KarmaRune. */
  async kruneHasMinterRole(account: Address): Promise<boolean> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaRune'),
      abi: karmaRuneAbi,
      functionName: 'hasRole',
      args: [MINTER_ROLE, account],
    });
  }

  /**
   * True if `reasonHash` has already been minted by `mintEarned` (on-chain
   * replay guard added alongside the duplicate-reasonHash revert). Exposed
   * so callers — chiefly settlement.ts — can check before submitting a mint
   * rather than only finding out via a reverted transaction.
   */
  async kruneSettled(reasonHash: Hash): Promise<boolean> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaRune'),
      abi: karmaRuneAbi,
      functionName: 'settled',
      args: [reasonHash],
    });
  }

  /**
   * Grant MINTER_ROLE on KarmaRune (e.g. to the settlement bridge's wallet
   * or a new earning engine). Caller must hold KarmaRune's
   * DEFAULT_ADMIN_ROLE on-chain or this reverts. Replaces the old
   * `setMinter(minter, true)` — KarmaRune is now ERC20 + AccessControl.
   */
  async grantKruneMinterRole(minter: Address): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'karmaRune'),
      abi: karmaRuneAbi,
      functionName: 'grantRole',
      args: [MINTER_ROLE, minter],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /** Revoke MINTER_ROLE on KarmaRune. Replaces the old `setMinter(minter, false)`. */
  async revokeKruneMinterRole(minter: Address): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'karmaRune'),
      abi: karmaRuneAbi,
      functionName: 'revokeRole',
      args: [MINTER_ROLE, minter],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  // ---- KarmaDex (KDEX) — fixed-supply investment/governance token ----

  async kdexBalanceOf(user: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaDex'),
      abi: karmaDexAbi,
      functionName: 'balanceOf',
      args: [user],
    });
  }

  // ---- KarmaShard (KSHRD) — yield token ----

  async kshrdBalanceOf(user: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaShard'),
      abi: karmaShardAbi,
      functionName: 'balanceOf',
      args: [user],
    });
  }

  /** True if `account` currently holds MINTER_ROLE on KarmaShard (expected: the Staking contract). */
  async kshrdHasMinterRole(account: Address): Promise<boolean> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaShard'),
      abi: karmaShardAbi,
      functionName: 'hasRole',
      args: [MINTER_ROLE, account],
    });
  }

  /** True if `account` currently holds BURNER_ROLE on KarmaShard (expected: the Treasury contract). */
  async kshrdHasBurnerRole(account: Address): Promise<boolean> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaShard'),
      abi: karmaShardAbi,
      functionName: 'hasRole',
      args: [BURNER_ROLE, account],
    });
  }

  /**
   * True once KarmaShard's `lockRoles()` has been called — role
   * administration (grantRole/revokeRole/renounceRole, including
   * DEFAULT_ADMIN_ROLE) is then permanently frozen. Read-only: this bridge
   * deliberately does NOT expose a wrapper that calls `lockRoles()` itself.
   * That call is one-way and irreversible (audit C-01 hardening) and belongs
   * in the deploy runbook, executed deliberately after verifying Staking
   * holds MINTER_ROLE and Treasury holds BURNER_ROLE — not in an app-level
   * bridge where a stray call would seal the role table permanently.
   */
  async kshrdRolesLocked(): Promise<boolean> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaShard'),
      abi: karmaShardAbi,
      functionName: 'rolesLocked',
    });
  }

  /**
   * Current KSHRD allowance `owner` has granted the Treasury contract.
   * Check this before calling `redeem` to avoid submitting a doomed
   * transaction — Treasury.redeem's underlying `burnFrom` now spends this
   * allowance (see `redeem` doc below) and reverts without it.
   */
  async kshrdAllowanceForTreasury(owner: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'karmaShard'),
      abi: karmaShardAbi,
      functionName: 'allowance',
      args: [owner, requireAddress(this.addresses, 'treasury')],
    });
  }

  /**
   * Approve the Treasury contract to spend `kshrdAmount` of the caller's own
   * KSHRD. Required before `redeem` — see that method's doc for why. This
   * wallet's own account is both the approver and (via `redeem`) the
   * spender's counterparty, since Treasury.redeem is caller-authorized.
   */
  async approveKshrdForTreasury(kshrdAmount: bigint): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'karmaShard'),
      abi: karmaShardAbi,
      functionName: 'approve',
      args: [requireAddress(this.addresses, 'treasury'), kshrdAmount],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /**
   * Grant KarmaShard's MINTER_ROLE to the Staking contract. Required
   * one-time system wiring after deploying both. Without it, `unstake()`
   * no longer reverts (that changed with the H-03 fix) — instead the yield
   * mint fails silently into `unclaimedYield` and a `YieldMintDeferred`
   * event, and every staker has to `claimYield()` later once this role is
   * granted. Caller must hold KarmaShard's DEFAULT_ADMIN_ROLE.
   */
  async grantKshrdMinterRole(staking: Address): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'karmaShard'),
      abi: karmaShardAbi,
      functionName: 'grantRole',
      args: [MINTER_ROLE, staking],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /**
   * Grant KarmaShard's BURNER_ROLE to the Treasury contract. Required
   * one-time system wiring: without it, every Treasury.redeem() reverts
   * trying to burn the redeemer's KSHRD.
   */
  async grantKshrdBurnerRole(treasury: Address): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'karmaShard'),
      abi: karmaShardAbi,
      functionName: 'grantRole',
      args: [BURNER_ROLE, treasury],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  // ---- Staking — requires both earned KRUNE and purchased KDEX ----

  async stake(kruneAmount: bigint, kdexAmount: bigint): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'stake',
      args: [kruneAmount, kdexAmount],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /**
   * Close a matured stake: always returns principal (KRUNE + KDEX). Accrued
   * yield is minted as KSHRD in the same transaction IF KarmaShard currently
   * accepts the mint.
   *
   * IMPORTANT: this call resolving successfully does NOT mean the staker
   * received their KSHRD. Since the H-03 fix, `unstake()` wraps the yield
   * mint in try/catch on-chain: if KarmaShard refuses (e.g. Staking's
   * MINTER_ROLE was revoked), the transaction still succeeds, principal
   * still comes home, but the yield is recorded in `unclaimedYield(user)`
   * instead and a `YieldMintDeferred` event fires — no exception surfaces
   * here to distinguish the two outcomes. Callers that care whether the
   * yield actually landed must check `unclaimedYield(user)` (or the KSHRD
   * balance change) after this resolves; a nonzero `unclaimedYield` means
   * the user must separately call `claimYield()` later.
   */
  async unstake(): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'unstake',
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /**
   * Yield that a past `unstake()` deferred because KarmaShard refused the
   * mint at the time. Zero means nothing is owed — either there was never a
   * deferral, or a previous `claimYield()` already paid it out.
   */
  async unclaimedYield(user: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'unclaimedYield',
      args: [user],
    });
  }

  /**
   * Mint previously-deferred yield to the caller. Reverts on-chain if
   * `unclaimedYield(caller)` is zero, or if KarmaShard still refuses the
   * mint (e.g. Staking's MINTER_ROLE has not been restored yet).
   */
  async claimYield(): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'claimYield',
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  async pendingKshrd(user: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'pendingKshrd',
      args: [user],
    });
  }

  async getStakingPosition(user: Address): Promise<StakingPosition> {
    const [krune, kdex, weight, startedAt, rewardPerWeightPaid, accruedUsdc, active] = await this.publicClient.readContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'positions',
      args: [user],
    });
    return { krune, kdex, weight, startedAt, rewardPerWeightPaid, accruedUsdc, active };
  }

  /** Emergency-stops new stake() calls (unstake() is deliberately never pausable). Owner only. */
  async pauseStaking(): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'pause',
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /** Owner only. */
  async unpauseStaking(): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'unpause',
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  async isStakingPaused(): Promise<boolean> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'paused',
    });
  }

  // ---- Treasury — backs KSHRD redemption ----

  /** usdcAmount is in human units (e.g. 12.5); converted to 6-decimal base units internally. */
  async depositFees(usdcAmount: string | number): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'staking'),
      abi: stakingAbi,
      functionName: 'depositFees',
      args: [toUsdcUnits(usdcAmount)],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /**
   * Redeem KSHRD for USDC (asUsdc=true) or KDEX with the +10% keepback bonus
   * (asUsdc=false, 1000 bps). Redemption is CALLER-authorized: `redeem`
   * burns the caller's own KSHRD and pays the caller — there is no `user`
   * parameter (an earlier version of this contract took one; it's gone).
   *
   * IMPORTANT — this means the bridge cannot redeem on behalf of an
   * arbitrary end user. Whoever's KSHRD is being redeemed must be the
   * account signing this transaction, i.e. this TradeKarmaChain instance's
   * own wallet client must belong to that user, not the bridge's
   * DEPLOYER_PRIVATE_KEY. A single-key bridge wallet can only ever redeem
   * its own KSHRD balance.
   *
   * REQUIRES A PRIOR ERC-20 APPROVAL — THIS IS NEW AND WILL REVERT WITHOUT
   * IT. KarmaShard's `burnFrom` now spends an allowance in addition to
   * checking Treasury's BURNER_ROLE (audit fix): the caller must first call
   * `approveKshrdForTreasury(kshrdAmount)` (or otherwise `approve` the
   * Treasury address on KSHRD for at least `kshrdAmount`) or this call
   * reverts. This is the single most important behavioural change for any
   * UI/product code driving redemption — a "redeem" button that does not
   * first ensure an approval, or that does not surface this as a separate
   * approve step, will fail every time. Use `kshrdAllowanceForTreasury` to
   * check the current allowance before deciding whether an approval is
   * needed.
   */
  async redeem(kshrdAmount: bigint, asUsdc: boolean): Promise<Hash> {
    const wallet = this.writer();
    return wallet.writeContract({
      address: requireAddress(this.addresses, 'treasury'),
      abi: treasuryAbi,
      functionName: 'redeem',
      args: [kshrdAmount, asUsdc],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /**
   * Treasury's own USDC<->KSHRD scale, `10 ** (18 - usdc.decimals())`,
   * computed on-chain at construction from the real USDC token. This is
   * the source of truth for USDC decimals on this deployment — see
   * assertStandardUsdcScale().
   */
  async getTreasuryUsdcScale(): Promise<bigint> {
    return this.publicClient.readContract({
      address: requireAddress(this.addresses, 'treasury'),
      abi: treasuryAbi,
      functionName: 'usdcScale',
    });
  }

  /**
   * Verify a deployed Treasury actually backs standard 6-decimal USDC,
   * which is what toUsdcUnits/fromUsdcUnits (and depositFees) assume.
   * Throws if the on-chain usdcScale() disagrees. Intended to be called
   * once during setup/health-check, not on every conversion — usdcScale()
   * never changes after construction, and the 6-decimal helpers are pure
   * functions with no RPC access, so they cannot check this themselves.
   */
  async assertStandardUsdcScale(): Promise<void> {
    const scale = await this.getTreasuryUsdcScale();
    const expected = 10n ** BigInt(KARMA_DECIMALS - USDC_DECIMALS);
    if (scale !== expected) {
      throw new Error(
        `TradeKarmaChain: Treasury.usdcScale() is ${scale.toString()}, expected ${expected.toString()} ` +
          `for standard ${USDC_DECIMALS}-decimal USDC. toUsdcUnits/fromUsdcUnits assume ${USDC_DECIMALS} ` +
          'decimals and will misprice redemptions/deposits against this deployment.'
      );
    }
  }
}
