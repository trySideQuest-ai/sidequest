#!/usr/bin/env node

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const API_BASE = 'https://api.trysidequest.ai';
const PLUGIN_DATA = process.env.CLAUDE_PLUGIN_DATA;

if (!PLUGIN_DATA) {
  console.error('Error: CLAUDE_PLUGIN_DATA not set');
  process.exit(1);
}

const state = crypto.randomBytes(16).toString('hex');

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost`);

  if (url.pathname !== '/callback') {
    res.writeHead(404);
    res.end('Not found');
    return;
  }

  const token = url.searchParams.get('token');
  const email = url.searchParams.get('email');
  const returnedState = url.searchParams.get('state');

  if (returnedState !== state) {
    res.writeHead(400);
    res.end('Invalid state parameter. Please try again.');
    server.close();
    process.exit(1);
    return;
  }

  if (!token) {
    res.writeHead(400);
    res.end('No token received. Please try again.');
    server.close();
    process.exit(1);
    return;
  }

  const configPath = path.join(PLUGIN_DATA, 'config.json');
  fs.mkdirSync(PLUGIN_DATA, { recursive: true });
  fs.writeFileSync(configPath, JSON.stringify({ token, enabled: true }, null, 2));

  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(`
    <html><body style="font-family: sans-serif; text-align: center; padding: 50px;">
      <h1>SideQuest authenticated!</h1>
      <p>Logged in as <strong>${email || 'unknown'}</strong>.</p>
      <p>You can close this tab and return to Claude Code.</p>
    </body></html>
  `);

  console.log(`Logged in as ${email || 'unknown'}`);
  server.close();
  process.exit(0);
});

server.listen(0, () => {
  const port = server.address().port;
  const authUrl = `${API_BASE}/auth/google?port=${port}&state=${state}`;

  console.log(`Opening browser for authentication...`);

  const cmd = process.platform === 'darwin' ? 'open'
    : process.platform === 'win32' ? 'start'
    : 'xdg-open';

  exec(`${cmd} "${authUrl}"`, (err) => {
    if (err) {
      console.log(`Could not open browser automatically.`);
      console.log(`Please open this URL manually: ${authUrl}`);
    }
  });

  setTimeout(() => {
    console.error('Login timed out. Please try again.');
    server.close();
    process.exit(1);
  }, 120000);
});
