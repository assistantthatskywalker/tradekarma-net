/**
 * Chain configuration for the on-chain bridge.
 * Supports Base mainnet and Base Sepolia testnet only. RPC URLs come from
 * environment variables — nothing network-related is ever hardcoded here.
 */

export const BASE_MAINNET_CHAIN_ID = 8453 as const;
export const BASE_SEPOLIA_CHAIN_ID = 84532 as const;

export type ChainId = typeof BASE_MAINNET_CHAIN_ID | typeof BASE_SEPOLIA_CHAIN_ID;

export interface ChainConfig {
  chainId: ChainId;
  name: string;
  rpcUrl: string;
}

/** Addresses of the 5 TradeKarma contracts on a given chain. Null = not deployed yet. */
export interface ContractAddresses {
  karmaRune: `0x${string}` | null;
  karmaDex: `0x${string}` | null;
  karmaShard: `0x${string}` | null;
  staking: `0x${string}` | null;
  treasury: `0x${string}` | null;
}

/**
 * Deployed-address registry, keyed by chainId. Nothing is deployed yet, so
 * every address is a placeholder null. Fill these in as `forge script`
 * deployments land.
 */
export const CONTRACT_ADDRESSES: Record<ChainId, ContractAddresses> = {
  [BASE_MAINNET_CHAIN_ID]: {
    karmaRune: null,
    karmaDex: null,
    karmaShard: null,
    staking: null,
    treasury: null,
  },
  [BASE_SEPOLIA_CHAIN_ID]: {
    karmaRune: null,
    karmaDex: null,
    karmaShard: null,
    staking: null,
    treasury: null,
  },
};

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`chain/config: missing required environment variable "${name}"`);
  }
  return value;
}

/**
 * Build a ChainConfig for the given chain, reading its RPC URL from env:
 * Base mainnet -> BASE_MAINNET_RPC_URL, Base Sepolia -> BASE_SEPOLIA_RPC_URL.
 * Fails loudly (throws) if the RPC URL is not set — never falls back to a
 * default/public endpoint silently.
 */
export function getChainConfig(chainId: ChainId): ChainConfig {
  switch (chainId) {
    case BASE_MAINNET_CHAIN_ID:
      return { chainId, name: 'base', rpcUrl: requireEnv('BASE_MAINNET_RPC_URL') };
    case BASE_SEPOLIA_CHAIN_ID:
      return { chainId, name: 'base-sepolia', rpcUrl: requireEnv('BASE_SEPOLIA_RPC_URL') };
    default:
      throw new Error(`chain/config: unsupported chainId "${chainId as number}"`);
  }
}

/**
 * Look up the deployed contract addresses for a chain. Returns a shallow
 * copy, not the registry's own object — callers must never be able to
 * mutate CONTRACT_ADDRESSES by poking the result (e.g. a TradeKarmaChain
 * instance's private `addresses` field is seeded from this and must not
 * leak into every other instance/lookup for the same chain).
 */
export function getContractAddresses(chainId: ChainId): ContractAddresses {
  const addresses = CONTRACT_ADDRESSES[chainId];
  if (!addresses) {
    throw new Error(`chain/config: unsupported chainId "${chainId as number}"`);
  }
  return { ...addresses };
}
