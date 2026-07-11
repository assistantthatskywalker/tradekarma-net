# TradeKarma Agent API (LLM-Agnostic)

The platform exposes ONE typed contract that any agent — OpenAI, Anthropic, a
local model, or a plain script — drives without vendor lock-in. Routing is by
**capability**, never by which model is calling. The `provider` field is
free-form metadata and is never used for logic. Swap GPT for Opus for a local
model and nothing else changes.

## Identity

```ts
interface AgentIdentity {
  agentId: string;          // unique per agent instance
  provider: string;         // "openai" | "anthropic" | "local" | "script" — metadata only
  capabilities: AgentCapability[];  // what this agent is allowed to invoke
}
```

## Capabilities

| Capability | Effect |
|------------|--------|
| `read.reputation` | Get a user's KRUNE balance |
| `read.transactions` | List a user's transactions |
| `write.review` | Award KRUNE for a review (quality-weighted) |
| `write.help` | Award KRUNE for a helpful answer (+5, retroactive) |
| `write.referral` | Award KRUNE for a successful referral (+30) |
| `write.shipment` | Award KRUNE for on-time shipping (scaled by order value) |
| `stake.quote` | Check the anti-whale gate for a user |
| `stake.open` | Open a stake (requires KRUNE + KDEX) |
| `stake.close` | Close a mature stake, redeem KSHRD |

## Request / Response

```ts
interface AgentRequest {
  agent: AgentIdentity;
  capability: AgentCapability;
  userId: string;
  payload: Record<string, any>;
}

interface AgentResponse {
  ok: boolean;
  data?: any;
  error?: string;
}
```

## Example

```ts
import { AgentInterface } from './src/agent/AgentInterface';
import { RequestValidator } from './src/agent/RequestValidator';

const validator = new RequestValidator();     // rate limit + self-dealing guard
const api = new AgentInterface(platformState);

const req = {
  agent: { agentId: 'a1', provider: 'anthropic', capabilities: ['write.review'] },
  capability: 'write.review',
  userId: 'alice',
  payload: { productId: 'p1', orderValue: 100, hasPhotos: true, textLength: 250, isDetailed: true },
};

if (validator.validate(req).valid) {
  const res = api.handle(req);   // { ok: true, data: { amountKRUNE, ... } }
}
```

## Guarantees

- **Provider-agnostic:** identical inputs → identical outputs regardless of
  `provider`. Verified by `src/__tests__/agent.test.ts` (mock GPT, Opus, and
  local agents all get the same KRUNE award).
- **Capability-gated:** an agent can only invoke capabilities it declared.
- **Guarded:** `RequestValidator` enforces rate limits, blocks self-referral,
  and validates payloads before anything mutates state.
- **No lock-in:** no OpenAI/Anthropic-specific type or concept appears in the
  contract. A new model integrates by sending the same JSON.
