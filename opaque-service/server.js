import crypto from 'node:crypto';
import express from 'express';
import * as opaque from '@serenity-kit/opaque';

const port = Number(process.env.OPAQUE_SERVICE_PORT || 8092);
const bindHost = process.env.OPAQUE_BIND_HOST || '127.0.0.1';
const internalSecret = process.env.OPAQUE_INTERNAL_SECRET || '';
const serverSetup = process.env.OPAQUE_SERVER_SETUP || '';
const serverIdentifier = 'planblindbox';
const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '128kb', strict: true }));
const pendingLogins = new Map();
const MAX_PENDING_LOGINS = 2000;
const MAX_PENDING_PER_IDENTIFIER = 5;
const decoySecret = crypto.randomBytes(32).toString('base64url');
let decoyRegistrationRecord = null;

function safeEqual(a, b) {
  const left = Buffer.from(String(a || ''), 'utf8');
  const right = Buffer.from(String(b || ''), 'utf8');
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}
function internal(req, res, next) {
  if (!internalSecret || !safeEqual(req.get('x-pbb-internal-secret'), internalSecret)) {
    return res.status(404).json({ message: 'Not found' });
  }
  next();
}
function requiredString(value, max = 200000) {
  return typeof value === 'string' && value.length > 0 && value.length <= max;
}
function setupReady() {
  if (!serverSetup) throw new Error('OPAQUE_SERVER_SETUP is not configured');
}

app.get('/health', (_req, res) => res.json({ status: 'ok', protocol: 'OPAQUE-RFC9807' }));
app.use('/internal', internal);

app.get('/internal/public-key', async (_req, res) => {
  try {
    setupReady();
    await opaque.ready;
    res.json({ serverStaticPublicKey: opaque.server.getPublicKey(serverSetup) });
  } catch (error) {
    res.status(503).json({ message: String(error.message || error) });
  }
});

app.get('/internal/decoy-record', (_req, res) => {
  if (!decoyRegistrationRecord) return res.status(503).json({ message: 'OPAQUE decoy not ready' });
  res.json({ registrationRecord: decoyRegistrationRecord });
});

app.post('/internal/registration/start', async (req, res) => {
  try {
    setupReady();
    await opaque.ready;
    const { userIdentifier, registrationRequest } = req.body || {};
    if (!requiredString(userIdentifier, 320) || !requiredString(registrationRequest)) {
      return res.status(400).json({ message: 'Invalid registration request' });
    }
    const result = opaque.server.createRegistrationResponse({
      serverSetup,
      userIdentifier,
      registrationRequest,
    });
    res.json({ registrationResponse: result.registrationResponse,
      serverStaticPublicKey: opaque.server.getPublicKey(serverSetup) });
  } catch (_error) {
    // Do not return protocol internals to callers.
    res.status(400).json({ message: 'Invalid OPAQUE registration request' });
  }
});

app.post('/internal/login/start', async (req, res) => {
  try {
    setupReady();
    await opaque.ready;
    const { userIdentifier, registrationRecord, startLoginRequest } = req.body || {};
    if (!requiredString(userIdentifier, 320) || !requiredString(registrationRecord) ||
        !requiredString(startLoginRequest)) {
      return res.status(400).json({ message: 'Invalid login request' });
    }
    if (pendingLogins.size >= MAX_PENDING_LOGINS) {
      return res.status(429).json({ message: 'Too many pending OPAQUE sessions' });
    }
    let pendingForIdentifier = 0;
    for (const item of pendingLogins.values()) {
      if (item.userIdentifier === userIdentifier) pendingForIdentifier++;
    }
    if (pendingForIdentifier >= MAX_PENDING_PER_IDENTIFIER) {
      return res.status(429).json({ message: 'Too many pending OPAQUE sessions' });
    }
    const result = opaque.server.startLogin({
      serverSetup,
      userIdentifier,
      registrationRecord,
      startLoginRequest,
      identifiers: { client: userIdentifier, server: serverIdentifier },
    });
    const challengeId = crypto.randomUUID();
    pendingLogins.set(challengeId, {
      state: result.serverLoginState,
      userIdentifier,
      createdAt: Date.now(),
    });
    res.json({ challengeId, loginResponse: result.loginResponse,
      serverStaticPublicKey: opaque.server.getPublicKey(serverSetup) });
  } catch (_error) {
    res.status(401).json({ message: '邮箱或密码错误' });
  }
});

app.post('/internal/login/finish', async (req, res) => {
  try {
    await opaque.ready;
    const { challengeId, finishLoginRequest } = req.body || {};
    if (!requiredString(challengeId, 64) || !requiredString(finishLoginRequest)) {
      return res.status(400).json({ message: 'Invalid login finalization' });
    }
    const pending = pendingLogins.get(challengeId);
    pendingLogins.delete(challengeId); // one-shot even when verification fails
    if (!pending || Date.now() - pending.createdAt > 120000) {
      return res.status(401).json({ message: '邮箱或密码错误' });
    }
    opaque.server.finishLogin({
      finishLoginRequest,
      serverLoginState: pending.state,
    });
    res.json({ authenticated: true });
  } catch (_error) {
    res.status(401).json({ message: '邮箱或密码错误' });
  }
});

setInterval(() => {
  const cutoff = Date.now() - 120000;
  for (const [id, item] of pendingLogins) {
    if (item.createdAt < cutoff) pendingLogins.delete(id);
  }
}, 30000).unref();

if (!serverSetup || Buffer.byteLength(internalSecret, 'utf8') < 32) {
  throw new Error('OPAQUE_SERVER_SETUP and a 32-byte OPAQUE_INTERNAL_SECRET are required');
}
await opaque.ready;
opaque.server.getPublicKey(serverSetup); // fail fast on invalid server setup
{
  const clientIdentifier = '00000000000000000000000000000000';
  const decoyPassword = `${decoySecret}:${clientIdentifier}`;
  const clientStart = opaque.client.startRegistration({
    password: decoyPassword,
    keyStretching: 'memory-constrained',
  });
  const serverResponse = opaque.server.createRegistrationResponse({
    serverSetup,
    userIdentifier: clientIdentifier,
    registrationRequest: clientStart.registrationRequest,
  });
  const clientFinish = opaque.client.finishRegistration({
    clientRegistrationState: clientStart.clientRegistrationState,
    registrationResponse: serverResponse.registrationResponse,
    password: decoyPassword,
    identifiers: { client: clientIdentifier, server: serverIdentifier },
  });
  decoyRegistrationRecord = clientFinish.registrationRecord;
}
app.listen(port, bindHost, () => {
  console.log(`PlanBlindBox OPAQUE service listening on ${bindHost}:${port}`);
});
