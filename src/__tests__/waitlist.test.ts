const handler = jest.requireActual('../../api/waitlist.js');
const originalEnv = { ...process.env };
function request(body: unknown = { email: 'Test@Example.com', consent: true }, overrides = {}) {
  return { method: 'POST', body, headers: { origin: 'https://tradekarmanet.vercel.app', 'content-type': 'application/json', 'x-vercel-forwarded-for': '192.0.2.1' }, ...overrides };
}
function response() {
  const res = { statusCode: 0, body: {} as { ok?: boolean; error?: string }, setHeader: jest.fn(), status: (s: number) => { res.statusCode = s; return res; }, json: (b: object) => { res.body = b; return res; } };
  return res;
}
beforeEach(() => {
  process.env.SUPABASE_URL = 'https://example.supabase.co';
  process.env.SUPABASE_SECRET_KEY = 'sb_secret_unit_test';
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  process.env.WAITLIST_RATE_LIMIT_SECRET = 'unit-test-rate-secret';
  jest.spyOn(global, 'fetch').mockResolvedValue({ ok: true, json: async () => true } as Response);
});
afterEach(() => { process.env = { ...originalEnv }; jest.restoreAllMocks(); });
it('normalizes addresses and stores through the private server RPC', async () => {
  const res = response(); await handler(request(), res);
  expect(res.statusCode).toBe(202);
  const [url, init] = (global.fetch as jest.Mock).mock.calls[0];
  expect(url).toContain('/rpc/join_tradekarma_waitlist');
  expect(JSON.parse(init.body).p_email).toBe('test@example.com');
  expect(JSON.parse(init.body).p_rate_key).toMatch(/^[0-9a-f]{64}$/);
  expect(init.body).not.toContain('192.0.2.1');
  expect(JSON.stringify(res.body)).not.toContain('sb_secret');
});
it.each([{ email: 'not-an-email', consent: true }, { email: 'a@b.com', consent: false }, null, [], { email: 'a'.repeat(255) + '@b.com', consent: true }])('rejects invalid input without a database call', async body => {
  const res = response(); await handler(request(body), res); expect(res.statusCode).toBe(400); expect(global.fetch).not.toHaveBeenCalled();
});
it('never returns success when the database or configuration is unavailable', async () => {
  delete process.env.SUPABASE_SECRET_KEY; const missing = response(); await handler(request(), missing); expect(missing.statusCode).toBe(503);
  process.env.SUPABASE_SECRET_KEY = 'sb_secret_unit_test';
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  (global.fetch as jest.Mock).mockResolvedValue({ ok: false }); const failed = response(); await handler(request(), failed); expect(failed.statusCode).toBe(503);
});
it('rejects cross-origin requests and GET, and honors shared database rate limits', async () => {
  const cross = response(); await handler(request(undefined, { headers: { origin: 'https://attacker.invalid' } }), cross); expect(cross.statusCode).toBe(403);
  const get = response(); await handler(request(undefined, { method: 'GET' }), get); expect(get.statusCode).toBe(405);
  (global.fetch as jest.Mock).mockResolvedValue({ ok: true, json: async () => false });
  const limited = response(); await handler(request(), limited); expect(limited.statusCode).toBe(429);
});
