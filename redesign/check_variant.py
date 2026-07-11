#!/usr/bin/env python3
"""Structural/substance check for one TradeKarma redesign variant.
Usage: check_variant.py --file <path> --variant <gpt|opus>
Exit 0 = PASS. Any failure prints WHY and exits 1.
Strict on substance (tokens, sections, real motion, a11y), tolerant on format
(case-insensitive, flexible matching)."""
import argparse, re, sys

ap = argparse.ArgumentParser()
ap.add_argument("--file", required=True)
ap.add_argument("--variant", required=True, choices=["gpt", "opus"])
a = ap.parse_args()

fails = []
def need(cond, why):
    if not cond:
        fails.append(why)

try:
    with open(a.file, "r", encoding="utf-8", errors="replace") as f:
        html = f.read()
except FileNotFoundError:
    print(f"FAIL: file not found: {a.file}")
    sys.exit(1)

low = html.lower()
size = len(html.encode("utf-8"))

# --- structure ---
need(size > 15000, f"file too small ({size} bytes) — expected a full page > 15KB")
need("<!doctype html" in low, "missing <!doctype html>")
need("</html>" in low, "missing closing </html>")
need("<style" in low and "</style>" in low, "no inline <style> block (must be self-contained)")
need("<script" in low and "</script>" in low, "no inline <script> block (must be self-contained)")
need(low.count("<h1") == 1, f"expected exactly one <h1>, found {low.count('<h1')}")
need("<main" in low, "no <main> landmark (accessibility)")
need("alt=" in low, "no alt attributes on images (accessibility)")
need(f"<!-- variant: {a.variant} -->" in low, f"missing self-identify comment '<!-- variant: {a.variant} -->'")

# --- assets wired ---
for asset in ["hero-bg", "rune-krune", "rune-kdex", "rune-kshrd", "hero-loop.mp4"]:
    need(asset in low, f"does not reference required asset '{asset}'")
need("mist" in low or "lightning" in low, "does not reference mist/lightning overlay texture")

# --- real motion (this is the point of the redesign) ---
need("@keyframes" in low, "no @keyframes animations")
need("intersectionobserver" in low, "no IntersectionObserver scroll-reveal")
need("<canvas" in low, "no <canvas> effect layer")
need("requestanimationframe" in low, "no requestAnimationFrame render loop")
need("prefers-reduced-motion" in low, "does not honor prefers-reduced-motion")

# --- tokens (substance) ---
for t in ["krune", "kdex", "kshrd"]:
    need(t in low, f"missing token ticker {t.upper()}")
for n in ["karmarune", "karmadex", "karmashard"]:
    need(n in low, f"missing token name {n}")
# anti-whale / earned-only point must be present near KRUNE messaging
need(bool(re.search(r"(never buy|can'?t be bought|cannot be bought|earned only|only.{0,20}earn)", low)),
     "missing the 'KRUNE is earned, never bought' point")

# --- required sections (case-insensitive, flexible) ---
sections = {
    "hero headline": r"earn your reputation",
    "problem section": r"broken",
    "three tokens section": r"three tokens",
    "earning mechanics": r"not all actions",
    "how it works": r"four steps",
    "roadmap": r"from points to protocol",
    "trust section": r"trust",
    "waitlist CTA": r"waitlist",
    "white paper link": r"white ?paper",
}
for label, pat in sections.items():
    need(bool(re.search(pat, low)), f"missing {label} (no match for /{pat}/)")

if fails:
    print(f"FAIL ({a.variant}): {len(fails)} problem(s) in {a.file}")
    for x in fails:
        print(f"  - {x}")
    sys.exit(1)

print(f"PASS ({a.variant}): {a.file} — {size} bytes, all substance + motion + asset checks satisfied")
sys.exit(0)
