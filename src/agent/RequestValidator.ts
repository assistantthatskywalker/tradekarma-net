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

    const p = req.payload;
    if (!p || typeof p !== 'object' || Array.isArray(p)) return { valid: false, reason: 'payload must be an object' };
    if (req.capability === 'write.referral' && p.referredUserId === req.userId) return { valid: false, reason: 'self-referral not allowed' };
    if (req.capability.startsWith('write.') && (typeof p.eventId !== 'string' || !p.eventId || p.eventId.length > 200)) {
      return { valid: false, reason: 'verified eventId required' };
    }
    if (req.capability === 'stake.open' &&
        (![p.kruneAmount, p.kdexAmount].every(n => Number.isSafeInteger(n) && n > 0))) {
      return { valid: false, reason: 'stake requires positive integer KRUNE and KDEX' };
    }
    if (req.capability === 'stake.close' && (typeof p.stakeId !== 'string' || !p.stakeId)) {
      return { valid: false, reason: 'stakeId required' };
    }
    for (const [key, window] of this.rate) if (now - window.windowStart >= this.windowMs) this.rate.delete(key);
    // Rate limiting per (agent, capability).
    const key = `${req.agent.agentId}:${req.capability}`;
    const w = this.rate.get(key);
    if (!w || now - w.windowStart >= this.windowMs) {
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
