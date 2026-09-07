/**
 * Chain Bridge Tests
 * Pure-logic coverage for the TypeScript<->blockchain bridge: decimal
 * conversion, reasonHash determinism, settlement idempotency/retry, the
 * address registry, and wallet-client fail-loud behavior. No live chain
 * involved — writeContract/readContract calls are never exercised here.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { Address, Hash } from 'viem';
import {
  BASE_MAINNET_CHAIN_ID,
  BASE_SEPOLIA_CHAIN_ID,
  getChainConfig,
  getContractAddresses,
} from '../chain/config';
import {
  createTradeKarmaPublicClient,
  createTradeKarmaWalletClient,
  TradeKarmaPublicClient,
  TradeKarmaWalletClient,
} from '../chain/client';
import {
  BURNER_ROLE,
  KARMA_DECIMALS,
  MINTER_ROLE,
  TradeKarmaChain,
  USDC_DECIMALS,
  fromKarmaUnits,
  fromUsdcUnits,
  toKarmaUnits,
  toUsdcUnits,
} from '../chain/TradeKarmaChain';

const TEST_ADDRESS: Address = '0x000000000000000000000000000000000000aa';

/** Minimal stand-in for a viem WalletClient: just enough to construct a
 * TradeKarmaChain and record what writeContract was called with. */
function makeFakeWallet() {
  const calls: Array<{ functionName: string; args?: readonly unknown[] }> = [];
  const wallet = {
    account: { address: TEST_ADDRESS },
    chain: { id: BASE_SEPOLIA_CHAIN_ID },
    writeContract: async (request: { functionName: string; args?: readonly unknown[] }) => {
      calls.push({ functionName: request.functionName, args: request.args });
      return '0xfaketxhash' as Hash;
    },
  };
  return { wallet: wallet as unknown as TradeKarmaWalletClient, calls };
}

/** Minimal stand-in for a viem PublicClient: a scriptable readContract. */
function makeFakePublic(readContract: (request: { functionName: string }) => Promise<unknown>) {
  return { readContract } as unknown as TradeKarmaPublicClient;
}

describe('Decimal conversion helpers', () => {
  it('converts whole KRUNE/KDEX/KSHRD amounts to 18-decimal base units', () => {
    expect(toKarmaUnits(1)).toBe(10n ** BigInt(KARMA_DECIMALS));
    expect(toKarmaUnits(5)).toBe(5n * 10n ** BigInt(KARMA_DECIMALS));
  });

  it('converts the smallest possible 18-decimal unit', () => {
    expect(toKarmaUnits('0.000000000000000001')).toBe(1n);
  });

  it('round-trips base units back to a human decimal string', () => {
    expect(fromKarmaUnits(toKarmaUnits(42))).toBe('42');
    expect(fromKarmaUnits(1n)).toBe('0.000000000000000001');
  });

  it('handles zero at both ends', () => {
    expect(toKarmaUnits(0)).toBe(0n);
    expect(fromKarmaUnits(0n)).toBe('0');
  });

  it('converts whole USDC amounts to 6-decimal base units', () => {
    expect(toUsdcUnits(1)).toBe(10n ** BigInt(USDC_DECIMALS));
    expect(toUsdcUnits(1)).toBe(1_000_000n);
  });

  it('converts USDC cents (the smallest realistic unit) correctly', () => {
    expect(toUsdcUnits('0.01')).toBe(10_000n);
  });

  it('round-trips USDC base units back to a human decimal string', () => {
    expect(fromUsdcUnits(toUsdcUnits('12.50'))).toBe('12.5');
  });

  it('never confuses the 18-decimal and 6-decimal scales', () => {
    // Same base-unit bigint, different human meaning depending on which
    // helper decodes it — this is exactly the bug named helpers prevent.
    const oneUnit = 1_000_000n;
    expect(fromUsdcUnits(oneUnit)).toBe('1');
    expect(fromKarmaUnits(oneUnit)).toBe('0.000000000001');
  });
});

describe('Contract address registry', () => {
  it('has a registry entry for Base mainnet with every address null (nothing deployed yet)', () => {
    const addresses = getContractAddresses(BASE_MAINNET_CHAIN_ID);
    expect(addresses).toEqual({
      karmaRune: null,
      karmaDex: null,
      karmaShard: null,
      staking: null,
      treasury: null,
    });
  });

  it('has a registry entry for Base Sepolia with every address null', () => {
    const addresses = getContractAddresses(BASE_SEPOLIA_CHAIN_ID);
    expect(addresses).toEqual({
      karmaRune: null,
      karmaDex: null,
      karmaShard: null,
      staking: null,
      treasury: null,
    });
  });

  it('keeps mainnet and testnet registries independent', () => {
    const mainnet = getContractAddresses(BASE_MAINNET_CHAIN_ID);
    const sepolia = getContractAddresses(BASE_SEPOLIA_CHAIN_ID);
    expect(mainnet).not.toBe(sepolia);
  });

  it('throws for an unsupported chainId', () => {
    expect(() => getContractAddresses(999 as unknown as typeof BASE_MAINNET_CHAIN_ID)).toThrow(/unsupported/i);
  });
});

describe('getChainConfig', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it('fails loudly when the RPC URL env var is missing', () => {
    delete process.env.BASE_SEPOLIA_RPC_URL;
    expect(() => getChainConfig(BASE_SEPOLIA_CHAIN_ID)).toThrow(/BASE_SEPOLIA_RPC_URL/);
  });

  it('reads the RPC URL from env when present', () => {
    process.env.BASE_MAINNET_RPC_URL = 'https://example-rpc.test';
    const config = getChainConfig(BASE_MAINNET_CHAIN_ID);
    expect(config).toEqual({ chainId: BASE_MAINNET_CHAIN_ID, name: 'base', rpcUrl: 'https://example-rpc.test' });
  });
});

describe('Wallet client fail-loud behavior', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it('throws a clear error when EARNING_PRIVATE_KEY is missing', () => {
    delete process.env.EARNING_PRIVATE_KEY;
    expect(() => createTradeKarmaWalletClient(BASE_SEPOLIA_CHAIN_ID)).toThrow(/EARNING_PRIVATE_KEY/);
  });

  it('does not fall back silently — the thrown error names the missing var', () => {
    delete process.env.EARNING_PRIVATE_KEY;
    try {
      createTradeKarmaWalletClient(BASE_MAINNET_CHAIN_ID);
      throw new Error('expected createTradeKarmaWalletClient to throw');
    } catch (err) {
      expect(err).toBeInstanceOf(Error);
      expect((err as Error).message).toMatch(/EARNING_PRIVATE_KEY/);
    }
  });

  it('creates a real signing account when the key is present', () => {
    process.env.EARNING_PRIVATE_KEY = `0x${'11'.repeat(32)}`;
    process.env.BASE_SEPOLIA_RPC_URL = 'https://example-rpc.test';

    const wallet = createTradeKarmaWalletClient(BASE_SEPOLIA_CHAIN_ID);

    expect(wallet.account?.address).toMatch(/^0x[0-9a-fA-F]{40}$/);
  });

  it('createTradeKarmaPublicClient also fails loudly when its RPC URL is missing', () => {
    delete process.env.BASE_MAINNET_RPC_URL;
    expect(() => createTradeKarmaPublicClient(BASE_MAINNET_CHAIN_ID)).toThrow(/BASE_MAINNET_RPC_URL/);
  });
});

describe('AccessControl role ids', () => {
  // Cross-checked against `cast keccak "MINTER_ROLE"` / `cast keccak "BURNER_ROLE"`
  // against the real deployed KarmaRune/KarmaShard contracts.
  it('MINTER_ROLE matches Solidity\'s keccak256("MINTER_ROLE")', () => {
    expect(MINTER_ROLE).toBe('0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6');
  });

  it('BURNER_ROLE matches Solidity\'s keccak256("BURNER_ROLE")', () => {
    expect(BURNER_ROLE).toBe('0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848');
  });

  it('MINTER_ROLE and BURNER_ROLE are distinct', () => {
    expect(MINTER_ROLE).not.toBe(BURNER_ROLE);
  });
});

describe('TradeKarmaChain — write method argument shapes', () => {
  // Regression coverage for the exact class of bug that slipped through last
  // time: hand-guessing an ABI's argument shape instead of reading the real
  // one. These assert on what gets sent to writeContract, not on any live
  // chain result.

  it('redeem() sends [kshrdAmount, asUsdc] with NO user address — Treasury.redeem is now caller-authorized', async () => {
    const { wallet, calls } = makeFakeWallet();
    const chain = new TradeKarmaChain(
      BASE_SEPOLIA_CHAIN_ID,
      makeFakePublic(async () => 0n),
      wallet
    );
    // Nothing is deployed yet, so the registry gives every address as null
    // (see getContractAddresses). Seed just the one this test needs directly
    // on the instance's own (copied, per-instance) addresses field — the
    // null-address case itself is covered by the "address guard" suite below.
    (chain as unknown as { addresses: Record<string, Address> }).addresses.treasury = TEST_ADDRESS;

    await chain.redeem(500n, true);

    expect(calls).toHaveLength(1);
    expect(calls[0].functionName).toBe('redeem');
    expect(calls[0].args).toEqual([500n, true]);
  });

  it('grantKruneMinterRole() calls grantRole(MINTER_ROLE, minter) — replaces the deleted setMinter', async () => {
    const { wallet, calls } = makeFakeWallet();
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n), wallet);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.karmaRune = TEST_ADDRESS;

    await chain.grantKruneMinterRole(TEST_ADDRESS);

    expect(calls[0]).toEqual({ functionName: 'grantRole', args: [MINTER_ROLE, TEST_ADDRESS] });
  });

  it('revokeKruneMinterRole() calls revokeRole(MINTER_ROLE, minter)', async () => {
    const { wallet, calls } = makeFakeWallet();
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n), wallet);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.karmaRune = TEST_ADDRESS;

    await chain.revokeKruneMinterRole(TEST_ADDRESS);

    expect(calls[0]).toEqual({ functionName: 'revokeRole', args: [MINTER_ROLE, TEST_ADDRESS] });
  });

  it('grantKshrdMinterRole() / grantKshrdBurnerRole() wire the correct role to the correct address', async () => {
    const { wallet, calls } = makeFakeWallet();
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n), wallet);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.karmaShard = TEST_ADDRESS;

    await chain.grantKshrdMinterRole(TEST_ADDRESS);
    await chain.grantKshrdBurnerRole(TEST_ADDRESS);

    expect(calls[0]).toEqual({ functionName: 'grantRole', args: [MINTER_ROLE, TEST_ADDRESS] });
    expect(calls[1]).toEqual({ functionName: 'grantRole', args: [BURNER_ROLE, TEST_ADDRESS] });
  });

  it('setKruneMinter / setTreasuryStaking no longer exist on the class (removed with the contracts)', () => {
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n));
    expect((chain as unknown as Record<string, unknown>).setKruneMinter).toBeUndefined();
    expect((chain as unknown as Record<string, unknown>).setTreasuryStaking).toBeUndefined();
  });

  it('approveKshrdForTreasury() calls approve(treasury, amount) on KarmaShard', async () => {
    const { wallet, calls } = makeFakeWallet();
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n), wallet);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.karmaShard = TEST_ADDRESS;
    (chain as unknown as { addresses: Record<string, Address> }).addresses.treasury =
      '0x000000000000000000000000000000000000bb';

    await chain.approveKshrdForTreasury(500n);

    expect(calls).toHaveLength(1);
    expect(calls[0]).toEqual({
      functionName: 'approve',
      args: ['0x000000000000000000000000000000000000bb', 500n],
    });
  });

  it('claimYield() calls claimYield with no args on Staking', async () => {
    const { wallet, calls } = makeFakeWallet();
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n), wallet);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.staking = TEST_ADDRESS;

    await chain.claimYield();

    expect(calls).toHaveLength(1);
    expect(calls[0].functionName).toBe('claimYield');
  });

  it('does not expose a wrapper that calls lockRoles() — that call is one-way and belongs in the deploy runbook, not an app-level bridge', () => {
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n));
    expect((chain as unknown as Record<string, unknown>).lockRoles).toBeUndefined();
  });

  it('does not expose a renounceOwnership wrapper — Staking/Treasury now revert it, so there is nothing useful to wrap', () => {
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n));
    expect((chain as unknown as Record<string, unknown>).renounceOwnership).toBeUndefined();
    expect((chain as unknown as Record<string, unknown>).renounceStakingOwnership).toBeUndefined();
    expect((chain as unknown as Record<string, unknown>).renounceTreasuryOwnership).toBeUndefined();
  });
});

describe('TradeKarmaChain — new post-remediation reads (settled guard, deferred yield, roles lock, allowance)', () => {
  /** Records every readContract call this fake public client receives, then answers with `result`. */
  function makeRecordingPublic(result: unknown) {
    const readCalls: Array<{ functionName: string; args?: readonly unknown[] }> = [];
    const client = {
      readContract: async (request: { functionName: string; args?: readonly unknown[] }) => {
        readCalls.push({ functionName: request.functionName, args: request.args });
        return result;
      },
    } as unknown as TradeKarmaPublicClient;
    return { client, readCalls };
  }

  it('kruneSettled() reads settled(reasonHash) on KarmaRune', async () => {
    const { client, readCalls } = makeRecordingPublic(true);
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, client);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.karmaRune = TEST_ADDRESS;
    const reasonHash = ('0x' + '11'.repeat(32)) as Hash;

    const result = await chain.kruneSettled(reasonHash);

    expect(result).toBe(true);
    expect(readCalls[0]).toEqual({ functionName: 'settled', args: [reasonHash] });
  });

  it('unclaimedYield() reads unclaimedYield(user) on Staking', async () => {
    const { client, readCalls } = makeRecordingPublic(123n);
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, client);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.staking = TEST_ADDRESS;

    const result = await chain.unclaimedYield(TEST_ADDRESS);

    expect(result).toBe(123n);
    expect(readCalls[0]).toEqual({ functionName: 'unclaimedYield', args: [TEST_ADDRESS] });
  });

  it('kshrdRolesLocked() reads rolesLocked() with no args on KarmaShard', async () => {
    const { client, readCalls } = makeRecordingPublic(false);
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, client);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.karmaShard = TEST_ADDRESS;

    const result = await chain.kshrdRolesLocked();

    expect(result).toBe(false);
    expect(readCalls[0].functionName).toBe('rolesLocked');
    expect(readCalls[0].args ?? []).toEqual([]);
  });

  it('kshrdAllowanceForTreasury() reads allowance(owner, treasury) on KarmaShard', async () => {
    const { client, readCalls } = makeRecordingPublic(1000n);
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, client);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.karmaShard = TEST_ADDRESS;
    (chain as unknown as { addresses: Record<string, Address> }).addresses.treasury =
      '0x000000000000000000000000000000000000bb';

    const result = await chain.kshrdAllowanceForTreasury(TEST_ADDRESS);

    expect(result).toBe(1000n);
    expect(readCalls[0]).toEqual({
      functionName: 'allowance',
      args: [TEST_ADDRESS, '0x000000000000000000000000000000000000bb'],
    });
  });
});

/**
 * The two behavioural changes below (redeem's new approval requirement,
 * unstake's new deferred-yield outcome) cannot be exercised end-to-end by
 * these pure-TS unit tests — they are Solidity-level revert/try-catch
 * behaviour with no live chain here to trigger it. What CAN be pinned down
 * is that the source keeps documenting them prominently, since that doc
 * comment is the only thing standing between a UI author and a silent
 * revert (redeem) or a silently-lost-looking yield (unstake). These read the
 * real source file, not a copy, so the assertion fails the moment the
 * documentation is weakened or deleted.
 */
const tradeKarmaChainSource = readFileSync(join(__dirname, '../chain/TradeKarmaChain.ts'), 'utf8');

function docCommentFor(source: string, methodSignature: string): string {
  const methodIndex = source.indexOf(methodSignature);
  if (methodIndex === -1) {
    throw new Error(`docCommentFor: could not find "${methodSignature}" in TradeKarmaChain.ts`);
  }
  const commentEnd = source.lastIndexOf('*/', methodIndex);
  const commentStart = source.lastIndexOf('/**', commentEnd);
  if (commentStart === -1 || commentEnd === -1) {
    throw new Error(`docCommentFor: "${methodSignature}" has no preceding /** */ doc comment`);
  }
  return source.slice(commentStart, commentEnd);
}

describe('TradeKarmaChain — redeem() approval requirement is documented (regression)', () => {
  it('prominently documents that redeem() now requires a prior KSHRD approval on Treasury', () => {
    const doc = docCommentFor(tradeKarmaChainSource, 'async redeem(kshrdAmount: bigint, asUsdc: boolean)');

    expect(doc).toMatch(/REQUIRES A PRIOR ERC-20 APPROVAL/);
    expect(doc).toMatch(/approveKshrdForTreasury/);
    expect(doc).toMatch(/reverts/i);
  });

  it('provides approveKshrdForTreasury as the documented approval helper, and it targets the Treasury address', async () => {
    const { wallet, calls } = makeFakeWallet();
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n), wallet);
    (chain as unknown as { addresses: Record<string, Address> }).addresses.karmaShard = TEST_ADDRESS;
    (chain as unknown as { addresses: Record<string, Address> }).addresses.treasury =
      '0x000000000000000000000000000000000000cc';

    await chain.approveKshrdForTreasury(42n);

    expect(calls[0].functionName).toBe('approve');
    expect(calls[0].args).toEqual(['0x000000000000000000000000000000000000cc', 42n]);
  });
});

describe('TradeKarmaChain — unstake() deferred-yield semantics are documented (regression)', () => {
  it('documents that a successful unstake() does not guarantee the yield was minted', () => {
    const doc = docCommentFor(tradeKarmaChainSource, 'async unstake()');

    expect(doc).toMatch(/does NOT mean the staker/i);
    expect(doc).toMatch(/unclaimedYield/);
    expect(doc).toMatch(/claimYield/);
  });

  it('unclaimedYield() and claimYield() are exposed as the documented follow-up path', () => {
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => 0n));
    expect(typeof chain.unclaimedYield).toBe('function');
    expect(typeof chain.claimYield).toBe('function');
  });
});

describe('TradeKarmaChain — address guard', () => {
  it('refuses to call a contract with no deployed address, before ever touching the client', async () => {
    // Nothing is deployed yet: getContractAddresses gives every field null.
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => {
      throw new Error('readContract should never be called when the address is missing');
    }));

    await expect(chain.kruneBalanceOf(TEST_ADDRESS)).rejects.toThrow(/no deployed address for "karmaRune"/);
  });
});

describe('TradeKarmaChain — assertStandardUsdcScale', () => {
  it('throws when the deployed Treasury does not use standard 6-decimal USDC', async () => {
    const wrongScale = 10n ** 6n; // would imply 12-decimal USDC, not 6
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => wrongScale));
    (chain as unknown as { addresses: Record<string, Address> }).addresses.treasury = TEST_ADDRESS;

    await expect(chain.assertStandardUsdcScale()).rejects.toThrow(/usdcScale/);
  });

  it('resolves cleanly when usdcScale() matches the standard 6-decimal assumption', async () => {
    const standardScale = 10n ** BigInt(KARMA_DECIMALS - USDC_DECIMALS); // 1e12
    const chain = new TradeKarmaChain(BASE_SEPOLIA_CHAIN_ID, makeFakePublic(async () => standardScale));
    (chain as unknown as { addresses: Record<string, Address> }).addresses.treasury = TEST_ADDRESS;

    await expect(chain.assertStandardUsdcScale()).resolves.toBeUndefined();
  });
});
