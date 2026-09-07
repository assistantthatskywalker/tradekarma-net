/** Local-only test: starts its own Anvil node, deploys actual artifacts, exercises the shipped client. */
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { createPublicClient, createWalletClient, createTestClient, http, defineChain } from 'viem';
import { mnemonicToAccount } from 'viem/accounts';
const require = createRequire(import.meta.url);
const { TradeKarmaChain, toKarmaUnits } = require('../dist/chain/TradeKarmaChain.js');
const { SettlementLedger } = require('../dist/chain/settlement.js');
const chain = defineChain({ id: 84532, name: 'Local TradeKarma test', nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: ['http://127.0.0.1:18545'] } } });
// Published Anvil test mnemonic; never a real wallet credential.
const account = mnemonicToAccount('test test test test test test test test test test test junk');
const anvil = spawn(process.env.ANVIL_BIN || `${homedir()}/.foundry/bin/anvil`, ['--host', '127.0.0.1', '--port', '18545', '--chain-id', '84532', '--silent'], { stdio: ['ignore', 'pipe', 'pipe'] });
let startupError, stderr = '';
anvil.on('error', e => { startupError = e; });
anvil.stderr.on('data', b => { stderr += b.toString(); });
const transport = http(chain.rpcUrls.default.http[0]);
const publicClient = createPublicClient({ chain, transport });
const wallet = createWalletClient({ chain, transport, account });
const test = createTestClient({ chain, transport, mode: 'anvil' });
const artifact = name => JSON.parse(readFileSync(new URL(`../out/${name}.sol/${name}.json`, import.meta.url)));
async function receipt(hash) { const r = await publicClient.waitForTransactionReceipt({ hash }); assert.equal(r.status, 'success'); return r; }
async function deploy(name, args) { const a = artifact(name); return (await receipt(await wallet.deployContract({ abi: a.abi, bytecode: a.bytecode.object, args }))).contractAddress; }
async function write(name, address, functionName, args = []) { return receipt(await wallet.writeContract({ address, abi: artifact(name).abi, functionName, args })); }
try {
  // Fail if another service occupies this port; never attach to someone else's node.
  await new Promise(r => setTimeout(r, 300));
  for (let i = 0; ; i++) {
    if (startupError || anvil.exitCode !== null) throw startupError || new Error(`Anvil failed: ${stderr}`);
    try { await publicClient.getBlockNumber(); break; } catch (e) { if (i === 30) throw e; await new Promise(r => setTimeout(r, 100)); }
  }
  const usdc = await deploy('MockERC20', ['USD Coin', 'USDC', 6]);
  const karmaRune = await deploy('KarmaRune', [account.address]);
  const karmaDex = await deploy('KarmaDex', [toKarmaUnits(1000000), account.address]);
  const karmaShard = await deploy('KarmaShard', [account.address]);
  const treasury = await deploy('Treasury', [usdc, karmaDex, karmaShard, account.address]);
  const staking = await deploy('Staking', [karmaRune, karmaDex, karmaShard, treasury, account.address]);
  const client = new TradeKarmaChain(84532, publicClient, wallet, { karmaRune, karmaDex, karmaShard, treasury, staking });
  await receipt(await client.grantKshrdMinterRole(staking));
  await receipt(await client.grantKshrdBurnerRole(treasury));
  await write('KarmaShard', karmaShard, 'lockRoles');
  assert.equal(await client.kshrdRolesLocked(), true);
  await test.mine({ blocks: 65 }); // Anvil finalized tag trails the head by 64 blocks.
  const event = { id: 'verified-local-review', userId: 'local-user', type: 'review', amountKRUNE: 100,
    timestamp: new Date(1), multiplier: 1, metadata: {} };
  const settlement = new SettlementLedger(client.getSettlementDomain(), () => account.address);
  await settlement.settle(client, event, account.address);
  await test.mine({ blocks: 65 });
  const settled = await settlement.settle(client, event, account.address);
  assert.equal(settled.status, 'confirmed');
  await settlement.settle(client, event, account.address);
  assert.equal(await client.kruneBalanceOf(account.address), toKarmaUnits(100));
  await receipt(await client.approveKdexForStaking(toKarmaUnits(100)));
  await receipt(await client.stake(toKarmaUnits(100), toKarmaUnits(100)));
  const position = await client.getStakingPosition(account.address);
  assert.equal(position.krune, toKarmaUnits(100)); assert.equal(position.active, true); assert.equal(position.weight, toKarmaUnits(100));
  await write('MockERC20', usdc, 'mint', [account.address, 100000000n]);
  await client.assertStandardUsdcScale();
  await receipt(await client.approveUsdcForFees(100000000n));
  await receipt(await client.depositFees('100'));
  assert.equal(await client.pendingKshrd(account.address), toKarmaUnits(100));
  await test.increaseTime({ seconds: 90 * 86400 }); await test.mine({ blocks: 1 });
  await receipt(await client.unstake());
  assert.equal(await client.kdexBalanceOf(account.address), toKarmaUnits(1000000));
  await receipt(await client.approveKshrdForTreasury(toKarmaUnits(100)));
  await receipt(await client.redeem(toKarmaUnits(100), true));
  assert.equal(await client.kshrdBalanceOf(account.address), 0n);
  assert.equal(await publicClient.readContract({ address: usdc, abi: artifact('MockERC20').abi, functionName: 'balanceOf', args: [account.address] }), 100000000n);
  console.log('PASS: real ABI / finalized settlement / role seal / approvals / stake / fee deposit / hard lock / principal / redemption');
} finally { if (anvil.exitCode === null) { anvil.kill('SIGTERM'); await new Promise(r => anvil.once('exit', r)); } }
