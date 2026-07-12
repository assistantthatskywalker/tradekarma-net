#!/usr/bin/env python3
"""Objective eval for the TradeKarma white paper (the GOAL made executable).
Scores WHITEPAPER.md /100. PASS = score >= 85 AND all CRITICAL substance present.
Prints a full breakdown of what earned/lost points. Exit 0 on PASS, 1 otherwise.
Strict on substance, tolerant on format (case-insensitive, flexible regex)."""
import argparse, re, sys

ap = argparse.ArgumentParser()
ap.add_argument("--file", required=True)
ap.add_argument("--pass-bar", type=int, default=85)
a = ap.parse_args()

try:
    text = open(a.file, encoding="utf-8", errors="replace").read()
except FileNotFoundError:
    print(f"FAIL: {a.file} not found — the writer produced no white paper.")
    sys.exit(1)

low = text.lower()
words = len(re.findall(r"\S+", text))
score = 0.0
lines = []
missing_critical = []

def has(pat):
    return re.search(pat, low, re.S) is not None

# ---------- Structure: 40 pts ----------
SECTIONS = {
    "abstract/summary": r"(abstract|executive summary|## .*summary|tl;dr)",
    "problem": r"(problem|broken|why .*exists|the case for)",
    "solution overview": r"(solution|overview|what .*is|how it works)",
    "three tokens": r"three tokens",
    "earning mechanics": r"(earning|earn .*krune|how .*earn)",
    "staking & yield": r"(staking|stake)",
    "anti-whale": r"(anti-?whale|both halves|can'?t (buy|stake))",
    "tokenomics/supply": r"(tokenomics|supply|distribution|allocation)",
    "phased rollout": r"(phase 1|phase 2|phase 3|roadmap|phased|rollout)",
    "governance/dao": r"(governance|\bdao\b|voting|proposal)",
    "treasury/redemption": r"(treasury|redeem|redemption|usdc)",
    "security/archive": r"(hash259|archive|tamper|audit trail|hash chain)",
    "legal/regulatory": r"(finma|regulat|legal|switzerland|compliance)",
    "risks": r"(risk|threat|attack|mitigation)",
    "roadmap": r"(roadmap|milestone|timeline|20\d\d)",
    "conclusion": r"(conclusion|closing|final word|summary of)",
}
per = 40 / len(SECTIONS)
got = 0
missing_sec = []
for name, pat in SECTIONS.items():
    if has(pat):
        score += per; got += 1
    else:
        missing_sec.append(name)
lines.append(f"Structure: {got}/{len(SECTIONS)} sections  (+{got*per:.1f}/40)")
if missing_sec:
    lines.append("   missing: " + ", ".join(missing_sec))

# ---------- Substance: 35 pts ----------
SUBSTANCE = [
    ("KRUNE earned-only / never bought", r"(krune|karmarune).{0,400}(earn|never (buy|bought)|can'?t be bought|not .*purchas)", 5, True),
    ("KDEX fixed-supply investment/governance", r"(kdex|karmadex).{0,400}(fixed supply|governance|invest|exchange|uniswap|dex)", 4, True),
    ("KSHRD yield from staking both", r"(kshrd|karmashard).{0,400}(yield|stak|redeem)", 4, True),
    ("anti-whale needs both halves", r"(whale|10 ?million|\$10m|both halves|need both).{0,300}(krune|stak|reputation|can'?t)", 5, True),
    ("diminishing/logarithmic earning", r"(logarithm|diminish|quality-?weighted|caps? at|first review)", 4, False),
    ("geometric-mean yield", r"(geometric|sqrt|square root|√)", 3, False),
    ("Base chain + smart wallet", r"(base( chain| network|\b).{0,200}(wallet|coinbase)|coinbase smart wallet|erc-?20 on base)", 3, False),
    ("database-first / prove the model", r"(database.{0,60}(first|point)|prove the model|no wallets|no gas)", 3, False),
    ("hash259 archive", r"hash259", 2, False),
    ("Basel / Switzerland", r"(basel|switzerland|swiss)", 2, False),
]
sub = 0
missing_sub = []
for name, pat, pts, crit in SUBSTANCE:
    if has(pat):
        score += pts; sub += pts
    else:
        missing_sub.append(f"{name}{' [CRITICAL]' if crit else ''}")
        if crit:
            missing_critical.append(name)
lines.append(f"Substance: +{sub}/35")
if missing_sub:
    lines.append("   missing: " + "; ".join(missing_sub))

# ---------- Length: 10 pts ----------
if words >= 3500:
    length_pts = 10
elif words >= 2000:
    length_pts = 10 * (words - 2000) / 1500
else:
    length_pts = 0
score += length_pts
lines.append(f"Length: {words} words  (+{length_pts:.1f}/10)")

# ---------- Hygiene: 15 pts ----------
hy = 0
hy_notes = []
if "tradekarma" in low: hy += 3
else: hy_notes.append("no 'TradeKarma' title")
if re.search(r"earn your reputation.{0,10}never buy", low): hy += 3
else: hy_notes.append("missing tagline")
heads = len(re.findall(r"^#{2,3}\s", text, re.M))
if heads >= 12: hy += 4
else: hy_notes.append(f"only {heads} headings (<12)")
if not re.search(r"(lorem ipsum|todo|tbd|placeholder|xxxx)", low): hy += 3
else: hy_notes.append("contains lorem/TODO/placeholder")
if re.search(r"(not (financial|investment) advice|forward-?looking|no offer|for informational)", low): hy += 2
else: hy_notes.append("no disclaimer")
score += hy
lines.append(f"Hygiene: +{hy}/15" + (("  (" + "; ".join(hy_notes) + ")") if hy_notes else ""))

# ---------- Verdict ----------
score = round(score, 1)
print("=" * 60)
print(f"TradeKarma White Paper Eval — {a.file}")
print("=" * 60)
for l in lines:
    print(l)
print("-" * 60)
print(f"SCORE: {score}/100   (pass bar {a.pass_bar})")
if missing_critical:
    print("CRITICAL items MISSING: " + ", ".join(missing_critical))

passed = score >= a.pass_bar and not missing_critical
print(f"VERDICT: {'PASS' if passed else 'FAIL'}")
sys.exit(0 if passed else 1)
