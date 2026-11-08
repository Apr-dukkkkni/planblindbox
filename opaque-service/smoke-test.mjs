import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import * as opaque from '@serenity-kit/opaque';

await opaque.ready;

const serverSetup = opaque.server.createSetup();
const userIdentifier = crypto.randomUUID();
const identifiers = {
  client: userIdentifier,
  server: 'planblindbox',
};
const password = 'PlanBlindBox-v2-smoke-Password-2026!';

const registrationStart = opaque.client.startRegistration({
  password,
  keyStretching: 'memory-constrained',
});
const registrationResponse = opaque.server.createRegistrationResponse({
  serverSetup,
  userIdentifier,
  registrationRequest: registrationStart.registrationRequest,
});
const registrationFinish = opaque.client.finishRegistration({
  clientRegistrationState: registrationStart.clientRegistrationState,
  registrationResponse: registrationResponse.registrationResponse,
  password,
  identifiers,
});

assert.ok(registrationFinish.registrationRecord);
assert.ok(registrationFinish.exportKey);
assert.ok(registrationFinish.serverStaticPublicKey);

const loginStart = opaque.client.startLogin({
  password,
  keyStretching: 'memory-constrained',
});
const serverLogin = opaque.server.startLogin({
  serverSetup,
  userIdentifier,
  registrationRecord: registrationFinish.registrationRecord,
  startLoginRequest: loginStart.startLoginRequest,
  identifiers,
});
const clientLogin = opaque.client.finishLogin({
  clientLoginState: loginStart.clientLoginState,
  loginResponse: serverLogin.loginResponse,
  password,
  identifiers,
});

assert.ok(clientLogin, 'correct password must authenticate');
assert.equal(clientLogin.exportKey, registrationFinish.exportKey,
  'OPAQUE export key must be stable across registration and login');
const serverFinish = opaque.server.finishLogin({
  finishLoginRequest: clientLogin.finishLoginRequest,
  serverLoginState: serverLogin.serverLoginState,
});
assert.equal(serverFinish.sessionKey, clientLogin.sessionKey,
  'client and server must derive the same OPAQUE session key');

// A wrong password must not produce a successful client login.
const wrongPassword = 'Definitely-not-the-right-password-2026!';
const wrongStart = opaque.client.startLogin({
  password: wrongPassword,
  keyStretching: 'memory-constrained',
});
const wrongServerLogin = opaque.server.startLogin({
  serverSetup,
  userIdentifier,
  registrationRecord: registrationFinish.registrationRecord,
  startLoginRequest: wrongStart.startLoginRequest,
  identifiers,
});
let wrongClientLogin = null;
try {
  wrongClientLogin = opaque.client.finishLogin({
    clientLoginState: wrongStart.clientLoginState,
    loginResponse: wrongServerLogin.loginResponse,
    password: wrongPassword,
    identifiers,
  });
} catch {
  wrongClientLogin = null;
}
assert.equal(wrongClientLogin ?? null, null,
  'wrong password must not authenticate');

console.log('OPAQUE RFC 9807 smoke test passed: registration, login, exportKey stability, session-key agreement, wrong-password rejection.');
