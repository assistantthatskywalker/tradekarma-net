import type { SqliteEarningStore } from '../storage/SqliteEarningStore';
/**
 * Agent-Agnostic Interface
 *
 * A single, LLM-neutral API surface any agent (OpenAI, Anthropic, local model,
 * or a plain script) can drive without vendor lock-in. Agents speak in typed
 * requests; the platform validates and executes. No provider-specific concepts
 * leak into this contract — only capabilities and typed payloads.
 */

import { RequestValidator } from './RequestValidator';
import { VerifiedEventStore } from '../logic/earning';
import { User } from '../models/User';
import { Transaction, TransactionLog } from '../models/Transaction';
import { KarmaRuneLedger } from '../models/KarmaRune';
import { KarmaDexLedger, KarmaShardVault } from '../models/Tokens';
import {
  awardReview,
  awardHelpfulness,
  awardReferral,
  awardShipment,
} from '../logic/earning';
import { stake, unstake, checkAntiWhaleGate, StakingContext } from '../logic/staking';

export type AgentCapability =
  | 'read.reputation'
  | 'read.transactions'
  | 'write.review'
  | 'write.help'
  | 'write.referral'
  | 'write.shipment'
  | 'stake.open'
  | 'stake.close'
  | 'stake.quote';

export interface AgentIdentity {
  agentId: string;
  provider: string; // free-form: "openai", "anthropic", "local", "script" — NOT used for logic
  capabilities: AgentCapability[];
}

export interface AgentRequest {
  agent: AgentIdentity;
  capability: AgentCapability;
  userId: string;
  payload: Record<string, any>;
}

export interface AgentResponse {
  ok: boolean;
  data?: any;
  error?: string;
}

export interface PlatformState {
  users: Map<string, User>;
  transactionLog: TransactionLog;
  kruneLedger: KarmaRuneLedger;
  kdexLedger: KarmaDexLedger;
  shardVault: KarmaShardVault;
}

/**
 * The single entry point agents use. Deliberately provider-agnostic: routing is
 * by `capability`, never by which model is calling. Swap GPT for Opus for a
 * local model and this contract is unchanged.
 */
export interface AuthenticatedAgent {
  agentId: string;
  capabilities: AgentCapability[];
  userIds: string[];
  expiresAt: number;
}

export class AgentInterface {
  private validator = new RequestValidator();
  constructor(
    private state: PlatformState,
    private authenticate: (credential: string) => AuthenticatedAgent | undefined = () => undefined,
    private verifiedEvents = new VerifiedEventStore(),
    private persistentEarnings?: SqliteEarningStore
  ) {}

  private requireUser(userId: string): User {
    const user = this.state.users.get(userId);
    if (!user) {
      throw new Error(`unknown user ${userId}`);
    }
    return user;
  }

  private stakingContext(user: User): StakingContext {
    return {
      userId: user.profile.id,
      user,
      kruneLedger: this.state.kruneLedger,
      kdexLedger: this.state.kdexLedger,
      shardVault: this.state.shardVault,
    };
  }

  handle(req: AgentRequest, credential = ''): AgentResponse {
    try {
      const identity = this.authenticate(credential);
      if (!identity || !Number.isFinite(identity.expiresAt) || identity.expiresAt <= Date.now()) {
        return { ok: false, error: 'authentication required' };
      }
      if (!identity.capabilities.includes(req.capability) || !identity.userIds.includes(req.userId)) {
        return { ok: false, error: 'capability or user access denied' };
      }
      // Rate limits key on the authenticated identity, never the request's claimed identity.
      const checked = this.validator.validate({ ...req, agent: { ...identity, provider: 'authenticated' } });
      if (!checked.valid) return { ok: false, error: checked.reason };
      if (this.persistentEarnings) {
        if (req.capability === 'read.reputation') return { ok: true, data: { balance: this.persistentEarnings.balance(req.userId) } };
        if (req.capability === 'read.transactions') return { ok: true, data: this.persistentEarnings.transactions(req.userId) };
        if (req.capability.startsWith('write.')) {
          const proof = this.persistentEarnings.getVerifiedEvent(req.payload.eventId);
          const types: Partial<Record<AgentCapability, string>> = { 'write.review': 'review', 'write.help': 'help', 'write.referral': 'referral', 'write.shipment': 'ship' };
          const expectedType = types[req.capability];
          if (!proof || proof.userId !== req.userId || proof.type !== expectedType) throw new Error('verified event ownership/type mismatch');
          return { ok: true, data: this.persistentEarnings.award(proof.id) };
        }
        throw new Error('local staking simulation is disabled with persistent accounting; use the chain client');
      }
      const user = this.requireUser(req.userId);
      const proof = typeof req.payload.eventId === 'string' ? this.verifiedEvents.get(req.payload.eventId) : undefined;
      const ctx = { userId: req.userId, user, transactionLog: this.state.transactionLog, evidence: proof };
      // Earning parameters are loaded from trusted evidence; request fields cannot inflate rewards.
      const p = req.capability.startsWith('write.') ? {
        productId: proof?.subjectId, questionId: proof?.subjectId, referredUserId: proof?.subjectId,
        orderId: proof?.subjectId, ...proof,
      } as Record<string, any> : req.payload;

      // Every KRUNE award is mirrored into the ledger (Phase 1 dual bookkeeping).
      const award = (tx: Transaction): AgentResponse => {
        this.state.kruneLedger.add(req.userId, tx.amountKRUNE);
        return { ok: true, data: tx };
      };

      if (req.capability.startsWith('write.') &&
          this.state.kruneLedger.get(req.userId) !== user.getReputation()) {
        throw new Error('reputation ledgers require reconciliation');
      }
      switch (req.capability) {
        case 'read.reputation':
          return { ok: true, data: { balance: user.getReputation() } };

        case 'read.transactions':
          return {
            ok: true,
            data: this.state.transactionLog.getByUser(req.userId),
          };

        case 'write.review':
          return award(awardReview(ctx, p.productId, p.orderValue, !!p.hasPhotos, p.textLength ?? 0, !!p.isDetailed));

        case 'write.help':
          return award(awardHelpfulness(ctx, p.questionId, p.answerText ?? ''));

        case 'write.referral':
          return award(awardReferral(ctx, p.referredUserId));

        case 'write.shipment':
          return award(awardShipment(ctx, p.orderId, p.orderValue, p.daysToShip ?? 0));

        case 'stake.quote': {
          const gate = checkAntiWhaleGate(this.stakingContext(user));
          return { ok: true, data: gate };
        }

        case 'stake.open': {
          const res = stake(this.stakingContext(user), p.kruneAmount, p.kdexAmount);
          return res.success ? { ok: true, data: res } : { ok: false, error: res.error };
        }

        case 'stake.close': {
          const res = unstake(this.stakingContext(user), p.stakeId, p.forUSDC ?? true);
          return res.success ? { ok: true, data: res } : { ok: false, error: res.error };
        }

        default:
          return { ok: false, error: `unhandled capability ${req.capability}` };
      }
    } catch (e: any) {
      return { ok: false, error: e.message ?? String(e) };
    }
  }
}
