/**
 * viem client factories.
 * Public client: read-only RPC access, no key material involved.
 * Wallet client: signs and sends transactions; requires a private key.
 */

import { createPublicClient, createWalletClient, http, type Chain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { BASE_MAINNET_CHAIN_ID, BASE_SEPOLIA_CHAIN_ID, ChainId, getChainConfig } from './config';

// Defined by hand instead of importing from 'viem/chains': that barrel pulls
// in every chain viem knows about (including experimental ones) and, under
// this project's tsconfig (module: commonjs, classic resolution), one of
// those transitively hits a packaging quirk in viem's "ox" dependency that
// breaks `tsc`. Base's identity (chain id, native currency, default RPC) is
// public and stable, so hand-defining it avoids the whole barrel.
// The `rpcUrls.default` below is inert for our usage — createTradeKarma*Client
// always passes an explicit `http(config.rpcUrl)` transport built from env.
const BASE_MAINNET: Chain = {
  id: BASE_MAINNET_CHAIN_ID,
  name: 'Base',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['https://mainnet.base.org'] } },
  blockExplorers: { default: { name: 'Basescan', url: 'https://basescan.org' } },
};

const BASE_SEPOLIA: Chain = {
  id: BASE_SEPOLIA_CHAIN_ID,
  name: 'Base Sepolia',
  nativeCurrency: { name: 'Sepolia Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['https://sepolia.base.org'] } },
  blockExplorers: { default: { name: 'Basescan', url: 'https://sepolia.basescan.org' } },
  testnet: true,
};

function resolveViemChain(chainId: ChainId): Chain {
  switch (chainId) {
    case BASE_MAINNET_CHAIN_ID:
      return BASE_MAINNET;
    case BASE_SEPOLIA_CHAIN_ID:
      return BASE_SEPOLIA;
  }
}

/** Read-only client for balances, positions, pending yield, etc. */
export function createTradeKarmaPublicClient(chainId: ChainId) {
  const config = getChainConfig(chainId);
  return createPublicClient({
    chain: resolveViemChain(chainId),
    transport: http(config.rpcUrl),
  });
}

/**
 * Signing client for write transactions (mintEarned, stake, unstake, redeem,
 * depositFees). Reads the private key from DEPLOYER_PRIVATE_KEY and fails
 * loudly if it is absent — this must never silently fall back to a
 * read-only/no-op client. The key itself is never logged or returned.
 */
export function createTradeKarmaWalletClient(chainId: ChainId) {
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error(
      'chain/client: DEPLOYER_PRIVATE_KEY is not set. Refusing to create a wallet client without an explicit signing key.'
    );
  }

  const config = getChainConfig(chainId);
  const account = privateKeyToAccount(privateKey as `0x${string}`);

  return createWalletClient({
    account,
    chain: resolveViemChain(chainId),
    transport: http(config.rpcUrl),
  });
}

export type TradeKarmaPublicClient = ReturnType<typeof createTradeKarmaPublicClient>;
export type TradeKarmaWalletClient = ReturnType<typeof createTradeKarmaWalletClient>;
