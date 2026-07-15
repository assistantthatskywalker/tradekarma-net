/**
 * Agent-Agnostic Interface
 *
 * A single, LLM-neutral API surface any agent (OpenAI, Anthropic, local model,
 * or a plain script) can drive without vendor lock-in. Agents speak in typed
 * requests; the platform validates and executes. No provider-specific concepts
 * leak into this contract — only capabilities and typed payloads.
 */

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
export class AgentInterface {
  constructor(private state: PlatformState) {}

  private requireUser(userId: string): User {
    let user = this.state.users.get(userId);
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

  handle(req: AgentRequest): AgentResponse {
    // Capability gate — the agent must have declared the capability it invokes.
    if (!req.agent.capabilities.includes(req.capability)) {
      return { ok: false, error: `agent lacks capability ${req.capability}` };
    }

    try {
      const user = this.requireUser(req.userId);
      const ctx = { userId: req.userId, user, transactionLog: this.state.transactionLog };
      const p = req.payload;

      // Every KRUNE award is mirrored into the ledger (Phase 1 dual bookkeeping).
      const award = (tx: Transaction): AgentResponse => {
        this.state.kruneLedger.add(req.userId, tx.amountKRUNE);
        return { ok: true, data: tx };
      };

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
