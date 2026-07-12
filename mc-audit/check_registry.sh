#!/usr/bin/env bash
# MC Projects/Websites registry audit — executable finish condition.
# PASS = every rule below holds. Strict on substance, no HTTP/auth needed:
# reads MC's real data source (loadApps) directly via bun.
set -u
FAIL=0
say() { echo "$@"; }
bad() { echo "FAIL: $@"; FAIL=1; }

WS=/home/skywalker/ai-workspace
MC=$WS/agent-os/mission-control

# --- Rule 1: no tradekarma entry in curated webapps.json (auto-scan owns it)
if grep -qi "tradekarma" "$MC/config/webapps.json"; then
  bad "webapps.json still contains a tradekarma entry (duplicate source)"
else
  say "OK: webapps.json has no tradekarma entry"
fi

# --- Rule 2: stray .well-known removed from tradekarma project (nothing in MC reads it)
if [ -e "$WS/projects/tradekarma_net/.well-known" ]; then
  bad "projects/tradekarma_net/.well-known still exists (unused invention — remove)"
else
  say "OK: no stray .well-known in tradekarma_net"
fi

# --- Rule 3..7: card set rules, evaluated against loadApps() (MC's real source)
cd "$MC" || { bad "mission-control dir missing"; exit 1; }
bun -e '
import { loadApps } from "./src/web/registry/load.ts";
import { readdirSync, existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
const WS = "'"$WS"'";
const apps = await loadApps();
let fail = 0;
const bad = (m) => { console.log("FAIL: " + m); fail = 1; };
const ok  = (m) => console.log("OK: " + m);

// Rule 3: exactly one TradeKarma card, with URL + Vercel + right folder
const tk = apps.filter(a => (a.name||"").toLowerCase().includes("tradekarma") || (a.projectPath||"").includes("tradekarma"));
if (tk.length !== 1) bad(`expected exactly 1 tradekarma card, got ${tk.length}`);
else {
  const t = tk[0];
  if (t.url !== "https://tradekarmanet.vercel.app") bad(`tradekarma card url is "${t.url||""}" not https://tradekarmanet.vercel.app`);
  else if ((t.platform||"") !== "Vercel") bad(`tradekarma platform "${t.platform}" != Vercel`);
  else ok("tradekarma: single card, correct url + platform (preview/online can render)");
}

// Rule 4: every top-level projects/ folder surfaces >= 1 card; tony root exempt
const projRoot = join(WS, "projects");
const folders = readdirSync(projRoot).filter(f => {
  if (f.startsWith(".")) return false;
  try { return statSync(join(projRoot, f)).isDirectory(); } catch { return false; }
});
const cardsUnder = (folder) => apps.filter(a => (a.projectPath||"").startsWith(join(projRoot, folder) + "/") || (a.projectPath||"") === join(projRoot, folder));
for (const f of folders) {
  if (f === "tony") continue; // member workspace — existing logic, untouched
  const n = cardsUnder(f).length;
  if (n === 0) bad(`projects/${f} has NO card (silently dropped)`);
}
ok("all non-workspace project folders surface at least one card");

// Rule 5: tony root itself must NOT be a card; its tnt-projects children may be
const tonyRoot = apps.filter(a => (a.projectPath||"") === join(projRoot, "tony"));
if (tonyRoot.length) bad("tony workspace root is surfaced as a card (workspace logic broken)");
else ok("tony workspace root not carded (logic intact)");

// Rule 6: one project one card — unless project.json declares subprojects, or tony/tnt-projects
for (const f of folders) {
  if (f === "tony") continue;
  const n = cardsUnder(f).length;
  let allowed = 1;
  const pj = join(projRoot, f, "project.json");
  if (existsSync(pj)) {
    try { const j = JSON.parse(readFileSync(pj, "utf8")); if (Array.isArray(j.subprojects)) allowed = j.subprojects.length; } catch {}
  }
  if (n > allowed) bad(`projects/${f}: ${n} cards but only ${allowed} allowed (duplicate cards)`);
}
ok("one card per project (subprojects honored)");

// Rule 7: every webapps/ folder surfaces exactly one card
const webRoot = join(WS, "webapps");
if (existsSync(webRoot)) {
  for (const f of readdirSync(webRoot).filter(f => { try { return statSync(join(webRoot,f)).isDirectory(); } catch { return false; } })) {
    const n = apps.filter(a => (a.projectPath||"").startsWith(join(webRoot, f))).length;
    if (n !== 1) bad(`webapps/${f}: ${n} cards (want exactly 1)`);
  }
  ok("webapps folders map 1:1 to cards");
}
process.exit(fail);
' || FAIL=1

# --- Rule 8: websites page — every site folder has website.json; jaynetix.ch present
for d in "$WS"/websites/*/; do
  n=$(basename "$d")
  [ -f "$d/website.json" ] || bad "websites/$n missing website.json (no card on websites page)"
done
grep -q '"url"' "$WS/websites/jaynetix.ch/website.json" 2>/dev/null \
  && say "OK: jaynetix.ch has website.json with url (websites page card)" \
  || bad "jaynetix.ch website.json missing or lacks url"

echo "------------------------------------------"
if [ "$FAIL" -eq 0 ]; then echo "VERDICT: PASS"; exit 0; else echo "VERDICT: FAIL"; exit 1; fi
