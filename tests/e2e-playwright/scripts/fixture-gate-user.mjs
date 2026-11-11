// Uses a dedicated GATE_STAFF account; prints only its anonymous UUID.
// Never print usernames, passwords, JWTs or full response bodies.
const base = process.env.E2E_BASE_URL;
const username = process.env.E2E_GATE_USERNAME;
const password = process.env.E2E_GATE_PASSWORD;
if (!base || !username || !password) {
  throw new Error('E2E_BASE_URL, E2E_GATE_USERNAME and E2E_GATE_PASSWORD are required');
}
const response = await fetch(new URL('/auth/api/v1/auth/login', base), {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username, password }),
});
if (!response.ok) throw new Error(`Dedicated gate fixture login failed: HTTP ${response.status}`);
const data = await response.json();
if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(data.anonymousId ?? '')) {
  throw new Error('Login did not return a valid anonymous UUID');
}
const jwtBody = data.token?.split('.')[1];
if (!jwtBody) throw new Error('Auth response did not contain JWT');
const payload = JSON.parse(Buffer.from(jwtBody, 'base64url').toString('utf8'));
if (!Array.isArray(payload.permissions) || !payload.permissions.includes('gate:scan')) {
  throw new Error('Dedicated gate account lacks gate:scan permission. Check DEV RBAC setup.');
}
process.stdout.write(`${data.anonymousId}\n`);
