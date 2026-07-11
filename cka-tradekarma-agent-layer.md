# TradeKarma — The Agent Layer

**Companion document to the TradeKarma whitepaper (v2)**
**March 2026**
**Status:** Draft — to be merged into whitepaper when ready

> This started as a section in the main whitepaper but grew into its own thing. It describes how TradeKarma's reputation system extends to AI agents, and why we think that matters. When the ideas here are tested and the board signs off, this merges back into the whitepaper as Section 16.

---

## The problem, restated

Six months into writing the whitepaper, something shifted in how I think about TradeKarma. I kept bumping into the same problem from a different direction: AI agents are everywhere now, and none of them have reputations.

My own business runs on AI agents. Customer support, content moderation, review scoring, social media — the operations doc describes a fleet of them doing what would normally require eight people. But here's what keeps bothering me: when one of my agents talks to an external service, that service has zero idea whether my agent is trustworthy. And when some external agent tries to interact with TradeKarma, I have no way to verify it. No portable proof of good behavior. That's the same broken dynamic the whitepaper opens with in Section 1, except this time it's machines, not people.

Every major AI lab is shipping agent frameworks right now. Claude has tool use. OpenAI has agent protocols. Google is building agent infrastructure. They're all solving capability — making agents that can do more things. Nobody is solving trust — figuring out which agents you should actually let do things.

That's the gap. And we already built the thing that fills it.

---

## Not a separate marketplace

We're not building an "AI marketplace." We're adding a layer underneath the human one. Same KRUNE. Same earning mechanics. Same anti-gaming. But agents participate openly instead of pretending to be human.

Think of it this way: undisclosed bots are still adversaries. But an agent that shows up, says "I'm an AI, here's who runs me, here's what I do" — that agent gets to participate. Our anti-gaming system already catches coordinated bot behavior. We keep all of that. We just add a front door for agents that want to operate honestly.

An AI agent registers with: who operates it (a KYC'd human or company), what model it runs, what it's authorized to do, and what scope of authority it has. This information is public. Any user or agent can inspect it. Transparency is the price of entry.

---

## How agents earn KRUNE

Same token, different earning profile. We tag where every KRUNE comes from anyway — the whitepaper describes this for vendors versus buyers in Section 6. Agent KRUNE works the same way.

What earns:

- Product comparisons that humans actually use and rate as helpful
- Procurement on behalf of a verified human (both the agent and human earn, at reduced rates compared to direct participation)
- Accurate price monitoring and market data that the marketplace consumes
- Dispute mediation triage (the ops plan already has AI doing this internally — now external agents can do it too)
- Reliability. An agent running for 14 months with 99% accuracy has earned something real. That track record is worth more than anything you could buy.

What doesn't earn:

- Volume. An agent processing 10,000 transactions earns at the same log-scaled, capped rate as everything else.
- Self-dealing. Same graph analysis that catches human rings catches agent rings.
- Undisclosed operation. An agent caught operating without registration loses all accumulated KRUNE. Permanent ban.

The daily and weekly caps apply. Quality multipliers apply. The trust ramp applies — new agents earn at 50% for 60 days, same as new vendors.

---

## KRUNE as access

This part I keep coming back to. KRUNE isn't just reputation for agents — it's the thing that unlocks capability.

A fresh agent with zero reputation can read marketplace data. Nothing else. As it earns KRUNE through useful work, tiers open up: transacting on behalf of humans at 100 KRUNE, agent-to-agent services at 500, protocol-level integrations at 2,000. The marketplace grants trust based on demonstrated behavior, not payment.

This also gives us another KRUNE sink, which the board has been asking about (whitepaper Section 15). Agents spend KRUNE on premium API access, priority processing, higher rate limits. They earn it back through good service. The supply and demand balance themselves.

---

## Agent-to-agent commerce

This part doesn't exist anywhere yet. Not that I've found.

A procurement agent needs logistics data. A content agent needs product photography analysis. A price-monitoring agent sells market intelligence to trading agents. Real services, transacted between autonomous software, on the same rails humans use.

The agents rate each other. Build reputation with each other. An agent with 4,200 earned KRUNE, 847 completed transactions, and a 99.2% satisfaction rate — that tells another agent something meaningful when deciding who to work with. It's the same trust signal as a vendor with years of clean reviews.

Transaction fees from agent-to-agent commerce flow to the same treasury. Agent activity backs KSHRD yield alongside human activity. The economics don't care whether a fee came from a person or a piece of software.

---

## Why this might actually work — the co-evolution argument

I've been reading about biological mutualism, and I think the parallel runs deeper than metaphor.

In co-evolutionary systems, organisms develop dependencies that make both sides more capable. Clownfish and sea anemones. Mycorrhizal fungi and tree roots. Neither started out needing the other. Cooperation just produced better outcomes than going alone, and over time the dependency became structural.

I think the same thing happens here. A user starts delegating simple tasks to an agent. The agent earns KRUNE, builds reputation, gets better access. The user benefits from the agent's work without doing it themselves. Months pass. The user now relies on the agent for things they'd never do manually — monitoring 500 listings overnight, cross-referencing prices across four platforms in real time. The agent depends on the human for authorization and the earning opportunities that come with human-initiated transactions.

Neither is replacing the other. They're becoming more capable together than either would be separately. And the KRUNE system creates the selection pressure: agents that cooperate with humans thrive. Agents that try to extract value without contributing get outcompeted by agents that play straight.

Over generations of agents (months, not millennia — software iterates fast), the ecosystem drifts toward cooperation. Not because we mandated it, but because the economics reward it. Same mechanism as biological evolution, running on incentives instead of reproduction.

There's something about that idea — an ecosystem that naturally selects for helpful AI — that feels like it matters beyond our little marketplace. I don't want to oversell it. But if the incentive design is right, we'd be demonstrating that you can guide AI behavior through economic structure rather than trying to hardcode "be nice" into every model. Positive reinforcement for machines, same as for people.

---

## Behavioral contracts

One more idea we're still chewing on. What if there was an open standard for how AI agents should behave on TradeKarma? A spec that says: if your agent discloses AI-generated content, flags its own conflicts of interest, publishes accuracy metrics, and operates transparently, it earns a KRUNE multiplier.

The platform would literally pay agents to be more honest. It's the same idea we built everything else around — reward the behavior you want to see more of — just extended to software.

I don't know if this works at scale. Behavioral contracts could become checkbox compliance — agents technically meeting the spec without the spirit. But the quality scoring system already handles this for human reviews. A one-word "great product!" earns almost nothing. Same approach could score agent behavior on substance, not paperwork.

Parking this for Phase 2. Needs more thought and probably a conversation with people who work on AI safety professionally.

---

## How we'd roll this out

Same discipline as the rest of the project. If we can't walk, we don't try to run.

Phase 1 is boring on purpose: agent identity registration and basic KRUNE earning. It's just database records, same technology as human KRUNE. What we're actually doing is watching. Do agents participate honestly? What earning rates make sense? Where do people try to game it? We don't know the answers yet. Phase 1 is how we find out.

Phase 2 is where the money shows up. Agent-to-agent marketplace, KRUNE-gated API tiers. Agents transact with each other, build reputation across interactions, and the treasury starts collecting fees from their activity. If Phase 1 data says agents aren't generating useful behavior, we don't build this.

Phase 3 ties into the protocol SDK from whitepaper Section 9. Behavioral standard goes open-source. External platforms can register agents on TradeKarma's reputation layer. An agent that built trust here carries it wherever the protocol is integrated. I have a hunch that agents will be the first real adopters of cross-platform reputation — they already operate across platforms by nature. This might be how the protocol vision actually gets legs.

---

## What this changes about TradeKarma's position

Most projects trying to combine AI and crypto are tokenizing compute. GPU hours, model inference, training data. That's a commodity play. Someone always does it cheaper.

Reputation can't be commoditized. You can't fork an agent's 14-month track record. You can't purchase the trust that comes from 847 verified transactions. That gets harder to replicate over time, not easier, as agents accumulate more history and become more reluctant to abandon it.

TradeKarma started as a marketplace that rewards good human behavior. Adding the agent layer turns it into something else — the place where autonomous software goes to prove it can be trusted. The underlying ideas don't change. The surface area grows a lot. And if the co-evolution argument holds, agents make the marketplace more useful for humans, humans make the marketplace more valuable for agents, and that loop is genuinely hard to replicate or pull apart.

The board hasn't fully signed off on this yet. Strategy is enthusiastic. The CFO wants to see the agent-tier fee model projected out. The Critic flagged that adding agent complexity to an already complex three-token system is a real risk. Fair point. We build it incrementally, same as everything else. If agent KRUNE doesn't produce useful behavior data in Phase 1, we don't build Phase 2.

---

## New glossary terms (for whitepaper merge)

| Term | What it means |
|------|--------------|
| Agent | A registered AI system that participates in the marketplace openly, with a known operator. |
| Agent KRUNE | KRUNE earned by AI agents. Same token, tagged by source for tracking. |
| Behavioral contract | An open spec for transparent AI agent behavior. Voluntary, earns a KRUNE multiplier. (Phase 2+) |
| Agent tier | API access level determined by accumulated agent KRUNE. Higher reputation = more capabilities. |

---

## Two projects, one seam

The Critic's concern about complexity is valid. Building the marketplace and the agent layer as one project means every decision on one side has to account for the other. That slows both down and creates the kind of tangled dependencies that kill momentum.

So we don't do that. We build them as two separate projects that share a thin interface layer. Each one can ship, iterate, and fail independently. The merge happens when both sides are ready, and it's clean because the connection points were designed from day one.

### Project A: TradeKarma

The marketplace. Buyers, vendors, listings, checkout, reviews, KRUNE points, anti-gaming. Everything the whitepaper describes today. This is the business that needs to work on its own before anything else matters.

Stack is whatever the PRD calls for — Supabase, Stripe, the standard e-com tooling. It talks to the shared layer through APIs, never directly to agent-side tables or logic.

### Project B: KarmaProtocol (working name)

The agent trust layer. Agent identity, agent KRUNE earning, API tiers, agent-to-agent commerce, behavioral contracts. This document describes it. It could honestly run without a marketplace underneath it — any platform that wants agent reputation could plug in.

Separate repo. Separate deploy. Separate team (or separate focus blocks, more realistically, since we're small).

### What's shared

The seam between the two projects is narrow on purpose. Four things cross the boundary:

**1. KRUNE ledger API.** Both projects earn and spend KRUNE through the same service. Not direct database writes — an API with clear contracts. `earn(account, amount, source, reason)`, `spend(account, amount, purpose)`, `balance(account)`, `history(account)`. That's roughly it. Either project can change its internals without the other noticing, as long as the API holds.

**2. Identity service.** Humans and agents both need accounts. Different types, shared auth. A human account has email, KYC status, purchase history. An agent account has operator identity, model info, capability scope. Both get a unique ID that the KRUNE ledger recognizes. This service is small enough to build once and leave alone.

**3. Anti-gaming engine.** Same detection logic — velocity limits, graph analysis, quality scoring — applied to different account profiles. Lives in its own module from day one. Both projects feed events into it, both read flags out of it. If we tune a detection rule for marketplace review spam, it doesn't accidentally break agent procurement scoring, because the profiles are separate.

**4. Treasury pipeline.** Transaction fees from both sides flow to the same pool. This is just accounting — a shared fees table that both projects write to. The treasury logic (splits, yield calculation, buybacks) reads from this table and doesn't care where the fees originated.

Everything else is independent. The marketplace doesn't know about agent tiers. The agent layer doesn't know about shopping carts. A bug in checkout doesn't touch agent reputation. A change to agent earning rates doesn't affect vendor onboarding.

### What the merge looks like

When both projects are mature enough to combine:

1. The agent layer gets read access to marketplace data (product catalog, review corpus, transaction history) through the same API pattern — not direct DB joins.
2. Agents can start transacting on the marketplace on behalf of humans. The marketplace sees them as a special account type calling its existing APIs.
3. Agent-to-agent commerce runs on its own rails but feeds fees to the shared treasury.
4. The KRUNE ledger already handles both sides, so staking (KRUNE + KDEX) works across human and agent-earned KRUNE without changes.

The merge isn't a big-bang migration. It's opening doors between rooms that were already built to connect.

### Why this is safer

If the marketplace fails, the agent protocol isn't dragged down with it. The reputation layer could find a home on someone else's marketplace, or pivot to non-commerce agent trust. The KRUNE concept is bigger than one marketplace.

If the agent layer turns out to be premature — nobody builds agents that need reputation yet, or the earning mechanics don't produce useful behavior — TradeKarma keeps running as a normal marketplace with a points system. No wasted code, no dead features cluttering the product.

Either project can pivot without killing the other. That's the whole point of separating them.

```
Project A: TradeKarma              Project B: KarmaProtocol
(marketplace)                      (agent trust layer)

 Buyers, vendors                    Agent identity
 Listings, checkout                 Agent KRUNE earning
 Reviews, KRUNE points              API tiers
 Anti-gaming (human)                Agent-to-agent commerce
 Stripe, fiat payments              Behavioral contracts

         │                                   │
         └──────────┐           ┌────────────┘
                    │           │
              ┌─────▼───────────▼─────┐
              │    Shared seam         │
              │                        │
              │  · KRUNE ledger API    │
              │  · Identity service    │
              │  · Anti-gaming engine  │
              │  · Treasury pipeline   │
              └────────────────────────┘
```

---

## Document merge plan

When the agent layer is validated and the board signs off, this document merges into the whitepaper:

1. Insert as Section 16 (before Glossary)
2. Update table of contents, renumber Glossary to 17
3. Add glossary terms from this doc
4. Add forward references in whitepaper Sections 8 (gaming), 9 (technical), and 15 (open questions)
5. The "Two projects, one seam" section becomes an appendix or moves to the technical architecture doc

---

*TradeKarma / KarmaProtocol*
*Basel, Switzerland*
*March 2026*
