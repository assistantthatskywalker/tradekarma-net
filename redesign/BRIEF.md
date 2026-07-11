# TradeKarma — Redesign Content Brief (shared by both variants)

This file is the **content + asset contract**. Both design variants must present
the same information and use the same assets, so they can be compared fairly and
toggled at runtime. The *design language* is yours to own — this file only fixes
*what* must appear, not *how* it looks.

Brand: **TradeKarma** · tradekarma.net · Basel, Switzerland
Tagline: **"Earn Your Reputation, Never Buy It."**
Voice: confident, plain-spoken, slightly mythic. Crypto that rewards good behavior.

---

## The three tokens (get these exactly right)

| Name | Ticker | Job | How you get it | Accent |
|------|--------|-----|----------------|--------|
| KarmaRune | **$KRUNE** | Reputation. Proof you participated and contributed. | **Earned only** — reviews, good service, referrals. *Can never be bought.* | Gold `#d4af37` |
| KarmaDex | **$KDEX** | Investment & governance. The token you buy if you believe in the project. | Buy on exchanges (Uniswap/Base). Fixed supply. | Teal `#14b8a6` |
| KarmaShard | **$KSHRD** | Yield. What you get when earned reputation meets invested capital. | Stake KRUNE + KDEX together. Redeem for USDC or KDEX. | Violet `#8b5cf6` |

The anti-whale mechanic is the emotional core: a whale with \$10M can buy all the
KDEX they want, but without months of earned KRUNE they can't stake and can't
touch the yield. **You need both halves.**

---

## Required sections (in order)

1. **Hero** — eyebrow "Positive-Reinforcement Commerce"; H1 "Earn Your Reputation, Never Buy It"; one-line subhead; primary CTA **Join Waitlist**, secondary CTA **Read the White Paper**. Uses the hero background image and/or hero video.
2. **The Problem — "E-Commerce Is Broken"** — three cards: *Fake Reviews Everywhere*, *Vendors Are Disposable*, *Communities Own Nothing*.
3. **The Solution — "Three Tokens. One Economy."** — the three token cards (KRUNE, KDEX, KSHRD) using the three rune glyph images. Make the "KRUNE can't be bought" point unmissable.
4. **Earning mechanics — "Not All Actions Are Equal"** — four points: *Logarithmic, not linear*, *Detail multiplies your reward*, *Helpfulness pays retroactively*, *First reviews earn 3×*.
5. **How It Works — "Four Steps to Earned Trust"** — Browse & Buy → Earn $KRUNE → Stake KRUNE + KDEX → Redeem or Recycle.
6. **Roadmap — "From Points to Protocol"** — Phase 1 *MVP Marketplace* (database points, no crypto) → Phase 2 *Tokenize & Stake* ($KRUNE on-chain, $KDEX launches) → Phase 3 *Open Protocol* ($KSHRD yield active).
7. **Trust & Security** — short reassurance band: Basel/Switzerland, FINMA-aware, start centralized and earn the DAO, database-first (prove the model, then launch tokens).
8. **Footer** — brand, waitlist email capture, links (White Paper, X/Twitter, Discord — use `#` placeholders), © 2026 TradeKarma.

Keep all real copy above; you may tighten wording but do not invent token mechanics.

---

## Assets (already generated, sitting in `assets/`)

Reference these by **relative path exactly as written** (the page is served from the `site/` dir):

- `assets/img/hero-bg.webp` — 2752×1536 hero art: three glowing runes in mist + lightning, dark empty space on the LEFT for the headline.
- `assets/video/hero-loop.mp4` — 8s silent hero loop (mist/runes/lightning). Use as an optional autoplay/muted/loop background layer behind the hero; MUST degrade gracefully (poster = hero-bg.webp) and respect `prefers-reduced-motion`.
- `assets/img/rune-krune.webp` — gold rune glyph → use for the $KRUNE card.
- `assets/img/rune-kdex.webp` — teal rune glyph → use for the $KDEX card.
- `assets/img/rune-kshrd.webp` — violet rune glyph → use for the $KSHRD card.
- `assets/img/mist.webp` — mist texture → atmospheric overlay (low opacity, `mix-blend-mode: screen`).
- `assets/img/lightning.webp` — lightning texture → accent overlay / hover flourish.

---

## Hard technical rules (both variants)

- **Single self-contained file.** All CSS in one `<style>` block, all JS in one `<script>` block. Google Fonts via `<link>` is allowed; no other external/build dependencies, no frameworks.
- **Dark theme.** Base near-black `#0a0a0a`. Accents gold/teal/violet as above.
- **Motion is required** (this is the point of the redesign): scroll-reveal via `IntersectionObserver`, at least one `<canvas>` particle/mist/lightning effect, `@keyframes` for ambient glow/float, and tasteful hover states. Everything must honor `@media (prefers-reduced-motion: reduce)` by disabling non-essential motion.
- **Accessible & responsive.** Semantic landmarks (`header/main/section/footer`), one `<h1>`, alt text on images, visible focus states, ≥4.5:1 text contrast, works 360px → 1440px+.
- **Performance.** `loading="lazy"` + `decoding="async"` on non-hero images; the mp4 is `preload="none"` with a poster.
- **Self-identify.** Include exactly one comment near the top: `<!-- variant: gpt -->` or `<!-- variant: opus -->` as assigned.
- **No Lorem ipsum.** Real copy only.
