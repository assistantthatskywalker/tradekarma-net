/**
 * Sprint 6: Agent-agnostic API + DAO tests.
 * Proves ≥3 different "agents" (mock GPT, mock Opus, mock local) drive the same
 * API identically — no vendor lock-in.
 */

import { User } from '../models/User';
import { TransactionLog } from '../models/Transaction';
import { KarmaRuneLedger } from '../models/KarmaRune';
import { KarmaDexLedger, KarmaShardVault } from '../models/Tokens';
import { AgentInterface, PlatformState, AgentIdentity, AgentRequest } from '../agent/AgentInterface';
import { RequestValidator } from '../agent/RequestValidator';
import { Governance, ProposalStatus } from '../dao/Governance';

function freshState(): PlatformState {
  const users = new Map<string, User>();
  users.set('alice', new User('alice', 'alice@example.com', 'alice'));
  return {
    users,
    transactionLog: new TransactionLog(),
    kruneLedger: new KarmaRuneLedger(),
    kdexLedger: new KarmaDexLedger(),
    shardVault: new KarmaShardVault(),
  };
}

const caps: AgentIdentity['capabilities'] = [
  'read.reputation',
  'write.review',
  'write.referral',
  'stake.quote',
];

function agent(provider: string): AgentIdentity {
  return { agentId: `agent-${provider}`, provider, capabilities: caps };
}

describe('AgentInterface — provider agnostic', () => {
  it('mock GPT, Opus, and local agents all get identical results', () => {
    const req = (a: AgentIdentity): AgentRequest => ({
      agent: a,
      capability: 'write.review',
      userId: 'alice',
      payload: { productId: 'p1', orderValue: 100, hasPhotos: true, textLength: 250, isDetailed: true },
    });

    const results = ['openai', 'anthropic', 'local'].map((prov) => {
      const iface = new AgentInterface(freshState());
      return iface.handle(req(agent(prov)));
    });

    expect(results.every((r) => r.ok)).toBe(true);
    // Same deterministic KRUNE award regardless of "provider".
    const amounts = results.map((r) => r.data.amountKRUNE);
    expect(new Set(amounts).size).toBe(1);
  });

  it('rejects a capability the agent did not declare', () => {
    const iface = new AgentInterface(freshState());
    const limited: AgentIdentity = { agentId: 'x', provider: 'local', capabilities: ['read.reputation'] };
    const res = iface.handle({ agent: limited, capability: 'write.review', userId: 'alice', payload: {} });
    expect(res.ok).toBe(false);
    expect(res.error).toMatch(/capability/i);
  });

  it('read.reputation reflects prior writes', () => {
    const state = freshState();
    const iface = new AgentInterface(state);
    iface.handle({ agent: agent('local'), capability: 'write.review', userId: 'alice', payload: { productId: 'p1', orderValue: 100, textLength: 100 } });
    const rep = iface.handle({ agent: agent('local'), capability: 'read.reputation', userId: 'alice', payload: {} });
    expect(rep.ok).toBe(true);
    expect(rep.data.balance).toBeGreaterThan(0);
  });
});

describe('RequestValidator', () => {
  it('blocks self-referral', () => {
    const v = new RequestValidator();
    const res = v.validate({ agent: agent('local'), capability: 'write.referral', userId: 'alice', payload: { referredUserId: 'alice' } });
    expect(res.valid).toBe(false);
    expect(res.reason).toMatch(/self-referral/i);
  });

  it('enforces rate limits', () => {
    const v = new RequestValidator(3, 60_000);
    const mk = (): AgentRequest => ({ agent: agent('local'), capability: 'read.reputation', userId: 'alice', payload: {} });
    expect(v.validate(mk(), 1000).valid).toBe(true);
    expect(v.validate(mk(), 1000).valid).toBe(true);
    expect(v.validate(mk(), 1000).valid).toBe(true);
    expect(v.validate(mk(), 1000).valid).toBe(false); // 4th within window
  });

  it('validates stake payloads', () => {
    const v = new RequestValidator();
    const res = v.validate({ agent: agent('local'), capability: 'stake.open', userId: 'alice', payload: { kruneAmount: 0, kdexAmount: 10 } });
    expect(res.valid).toBe(false);
  });
});

describe('DAO Governance', () => {
  it('KDEX-weighted vote passes with quorum and majority', () => {
    const kdex = new KarmaDexLedger();
    kdex.set('a', 600);
    kdex.set('b', 300);
    kdex.set('c', 100);
    const gov = new Governance(kdex);

    const start = new Date(2026, 0, 1);
    const close = new Date(2026, 0, 2);
    gov.createProposal('prop-1', 'Lower staking lock to 60 days', 'desc', 'a', 24 * 3600 * 1000, 500, start);

    gov.vote('prop-1', 'a', true, start);
    gov.vote('prop-1', 'b', true, start);
    gov.vote('prop-1', 'c', false, start);

    const status = gov.finalize('prop-1', close);
    expect(status).toBe(ProposalStatus.PASSED); // 900 for vs 100 against, quorum 500 met
  });

  it('fails quorum → rejected', () => {
    const kdex = new KarmaDexLedger();
    kdex.set('a', 100);
    const gov = new Governance(kdex);
    gov.createProposal('p', 't', 'd', 'a', 24 * 3600 * 1000, 1000, new Date(2026, 0, 1));
    gov.vote('p', 'a', true, new Date(2026, 0, 1));
    const status = gov.finalize('p', new Date(2026, 0, 2));
    expect(status).toBe(ProposalStatus.REJECTED);
  });

  it('one vote per address; no KDEX → no voting power', () => {
    const kdex = new KarmaDexLedger();
    kdex.set('a', 100);
    const gov = new Governance(kdex);
    gov.createProposal('p', 't', 'd', 'a', 24 * 3600 * 1000, 1, new Date(2026, 0, 1));
    expect(gov.vote('p', 'a', true, new Date(2026, 0, 1)).ok).toBe(true);
    expect(gov.vote('p', 'a', true, new Date(2026, 0, 1)).ok).toBe(false); // double vote
    expect(gov.vote('p', 'nobody', true, new Date(2026, 0, 1)).ok).toBe(false); // no KDEX
  });
});
