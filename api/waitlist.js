const { createHmac } = require('node:crypto');

/** Server-only Supabase key. No public table reads, no email/key logging. */
module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  const reply = (status, error) => res.status(status).json(error ? { ok: false, error } : { ok: true });
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return reply(405, 'Method not allowed'); }
  const origins = new Set((process.env.WAITLIST_ALLOWED_ORIGINS || 'https://tradekarmanet.vercel.app,https://tradekarma-net.vercel.app,https://tradekarma.net,https://www.tradekarma.net').split(',').map(x => x.trim()));
  if (process.env.VERCEL_URL) origins.add(`https://${process.env.VERCEL_URL}`);
  if (!origins.has(req.headers.origin)) return reply(403, 'Request origin not allowed');
  if (!String(req.headers['content-type'] || '').startsWith('application/json')) return reply(415, 'JSON required');
  if (Number(req.headers['content-length'] || 0) > 4096) return reply(413, 'Request too large');
  let body;
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    if (JSON.stringify(body).length > 4096) return reply(413, 'Request too large');
  } catch { return reply(400, 'Invalid request'); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return reply(400, 'Invalid request');
  if (body.website) return reply(202); // Honeypot, never write an address submitted by this path.
  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || body.consent !== true) return reply(400, 'A valid email and consent are required');
  const url = process.env.SUPABASE_URL;
  const secret = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  const rateSecret = process.env.WAITLIST_RATE_LIMIT_SECRET;
  if (!url || !secret || !rateSecret) return reply(503, 'Signups are temporarily unavailable. Please try again later.');
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(url)) return reply(503, 'Signup configuration unavailable');
  // Vercel sets x-vercel-forwarded-for; never use a caller-supplied fallback as an identity.
  const ip = String(req.headers['x-vercel-forwarded-for'] || 'unknown').split(',')[0].trim();
  const rateKey = createHmac('sha256', rateSecret).update(`${new Date().toISOString().slice(0, 10)}:${ip}`).digest('hex');
  try {
    const headers = { apikey: secret, 'Content-Type': 'application/json' };
    // New sb_secret keys use apikey; legacy service-role JWTs also use Authorization.
    if (!secret.startsWith('sb_secret_')) headers.Authorization = `Bearer ${secret}`;
    const result = await fetch(`${url.replace(/\/$/, '')}/rest/v1/rpc/join_tradekarma_waitlist`, {
      method: 'POST', headers, body: JSON.stringify({ p_email: email, p_rate_key: rateKey }), signal: AbortSignal.timeout(8000),
    });
    if (!result.ok) return reply(503, 'Signups are temporarily unavailable. Please try again later.');
    if (await result.json() !== true) { res.setHeader('Retry-After', '3600'); return reply(429, 'Please try again later.'); }
    return reply(202); // Identical response for new and previously registered addresses.
  } catch { return reply(503, 'Signups are temporarily unavailable. Please try again later.'); }
};
