/** Loopback-only smoke-test server. Never inherits production database credentials. */
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const handler = require('../api/waitlist');
process.env.SUPABASE_URL = '';
process.env.SUPABASE_SECRET_KEY = '';
process.env.SUPABASE_SERVICE_ROLE_KEY = '';
process.env.WAITLIST_ALLOWED_ORIGINS = 'http://127.0.0.1:18546';
const root = path.resolve(__dirname, '../site');
const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.webp': 'image/webp', '.mp4': 'video/mp4', '.ico': 'image/x-icon' };
http.createServer(async (req, res) => {
  if (req.url === '/api/waitlist') {
    const chunks = [];
    for await (const chunk of req) { chunks.push(chunk); if (Buffer.concat(chunks).length > 4096) { res.writeHead(413); res.end(); return; } }
    req.body = Buffer.concat(chunks).toString();
    res.status = code => { res.statusCode = code; return res; };
    res.json = value => { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(value)); };
    return handler(req, res);
  }
  const file = path.resolve(root, '.' + new URL(req.url, 'http://localhost').pathname.replace(/\/$/, '/index.html'));
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
  res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
  const headers = require('../vercel.json').headers[0].headers;
  for (const { key, value } of headers) res.setHeader(key, value);
  fs.createReadStream(file).pipe(res);
}).listen(18546, '127.0.0.1');
