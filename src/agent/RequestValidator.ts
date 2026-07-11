/**
 * Request Validator — guards the agent surface.
 * Rate limiting, self-dealing prevention, payload sanity. Provider-agnostic:
 * the same rules apply whether the caller is GPT, Opus, or a script.
 */

import { AgentRequest } from './AgentInterface';

export interface ValidationResult {
  valid: boolean;
  reason?: string;
}

interface RateWindow {
  count: number;
  windowStart: number;
}

export class RequestValidator {
  private rate: Map<string, RateWindow> = new Map();

  constructor(
    private maxPerWindow: number = 60,
    private windowMs: number = 60_000
  ) {}

  validate(req: AgentRequest, now: number = Date.now()): ValidationResult {
    if (!req.agent?.agentId) return { valid: false, reason: 'missing agent identity' };
    if (!req.userId) return { valid: false, reason: 'missing userId' };
    if (!req.capability) return { valid: false, reason: 'missing capability' };

    // Self-dealing: an agent cannot refer, review, or ship on behalf of the
    // same subject it targets in a way that credits itself.
    const p = req.payload ?? {};
    if (req.capability === 'write.referral' && p.referredUserId === req.userId) {
      return { valid: false, reason: 'self-referral not allowed' };
    }

    // Payload sanity per capability.
    if (req.capability === 'write.review') {
      if (typeof p.productId !== 'string' || typeof p.orderValue !== 'number' || p.orderValue < 0) {
        return { valid: false, reason: 'invalid review payload' };
      }
    }
    if (req.capability === 'stake.open') {
      if (!(p.kruneAmount > 0) || !(p.kdexAmount > 0)) {
        return { valid: false, reason: 'stake requires positive KRUNE and KDEX' };
      }
    }

    // Rate limiting per (agent, capability).
    const key = `${req.agent.agentId}:${req.capability}`;
    const w = this.rate.get(key);
    if (!w || now - w.windowStart > this.windowMs) {
      this.rate.set(key, { count: 1, windowStart: now });
    } else {
      if (w.count >= this.maxPerWindow) {
        return { valid: false, reason: 'rate limit exceeded' };
      }
      w.count += 1;
    }

    return { valid: true };
  }
}
