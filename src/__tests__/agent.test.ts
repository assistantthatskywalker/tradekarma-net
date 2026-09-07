import { VerifiedEventStore } from '../logic/earning';
import { TransactionType } from '../models/Transaction';
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

function authenticatedInterface(state: PlatformState, capabilities = caps, users = ['alice']) {
  const events = new VerifiedEventStore();
  events.register({ id: 'review1', userId: 'alice', type: TransactionType.REVIEW, subjectId: 'p1', verifiedAt: new Date(1),
    orderValue: 100, hasPhotos: true, textLength: 250, isDetailed: true });
  return new AgentInterface(state, token => token === 'trusted-session' ? {
    agentId: 'server-identity', capabilities, userIds: users, expiresAt: Date.now() + 60000,
  } : undefined, events);
}

describe('Agent trust boundary', () => {
  const req: AgentRequest = { agent: agent('local'), capability: 'write.review', userId: 'alice', payload: { eventId: 'review1', orderValue: 999999 } };
  it('ignores self-declared permissions and rejects missing authentication', () => {
    expect(new AgentInterface(freshState()).handle(req).ok).toBe(false);
    expect(authenticatedInterface(freshState()).handle(req, 'forged-token').ok).toBe(false);
    expect(authenticatedInterface(freshState(), ['read.reputation']).handle(req, 'trusted-session').ok).toBe(false);
    expect(authenticatedInterface(freshState(), caps, ['bob']).handle(req, 'trusted-session').ok).toBe(false);
  });
  it('uses verified server facts with the same result for every provider', () => {
    for (const provider of ['openai', 'anthropic', 'local']) {
      const api = authenticatedInterface(freshState());
      expect(api.handle({ ...req, agent: agent(provider) }, 'trusted-session').data.amountKRUNE).toBe(117);
      expect(api.handle(req, 'trusted-session').ok).toBe(false);
    }
  });
  it('checks rate limits inside handle, using the real identity', () => {
    const api = authenticatedInterface(freshState());
    for (let i = 0; i < 60; i++) expect(api.handle({ ...req, agent: agent(String(i)), capability: 'read.reputation' }, 'trusted-session').ok).toBe(true);
    expect(api.handle({ ...req, capability: 'read.reputation' }, 'trusted-session').error).toMatch(/rate limit/);
  });
  it('fails without evidence and preserves both ledgers', () => {
    const state = freshState(); const api = authenticatedInterface(state);
    expect(api.handle({ ...req, payload: { eventId: 'missing' } }, 'trusted-session').ok).toBe(false);
    expect(state.kruneLedger.get('alice')).toBe(0);
    expect(state.users.get('alice')!.getReputation()).toBe(0);
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

it('governance snapshots capital so moved balances cannot vote twice', () => {
  const ledger = new KarmaDexLedger(); ledger.set('a', 100);
  const governance = new Governance(ledger); const now = new Date();
  governance.createProposal('id', 'Title', 'Description', 'a', 10000, 100, now);
  ledger.subtract('a', 100); ledger.add('b', 100);
  expect(governance.vote('id', 'a', true, now).ok).toBe(true);
  expect(governance.vote('id', 'b', true, now).ok).toBe(false);
  expect(() => governance.createProposal('id', 'Overwrite', '', 'b', 10000, 1, now)).toThrow(/duplicate/);
});
