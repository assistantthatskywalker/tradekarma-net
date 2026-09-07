import { marked } from 'marked';
import { readFileSync, writeFileSync } from 'node:fs';
const pages = [ ['WHITEPAPER.md', 'whitepaper.html', 'Whitepaper'], ['docs/BUSINESS-MODEL.md', 'business-model.html', 'Business model'], ['docs/PRIVACY.md', 'privacy.html', 'Privacy'] ];
for (const [source, target, title] of pages) {
  // Only repository-owned Markdown is rendered. No public input reaches this build.
  const content = marked.parse(readFileSync(source, 'utf8'));
  writeFileSync(`site/${target}`, `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>TradeKarma — ${title}</title><link rel="stylesheet" href="/assets/document.css"></head><body><nav><a href="/">← TradeKarma</a><a href="/whitepaper.html">Whitepaper</a><a href="/business-model.html">Business model</a><a href="/privacy.html">Privacy</a></nav><main>${content}</main></body></html>\n`);
}
console.log('Built public whitepaper, business model and privacy pages.');
