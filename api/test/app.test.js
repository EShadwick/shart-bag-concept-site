import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler, MAX_BODY_BYTES, RETENTION_DAYS } from '../src/app.js';

const fixedNow = new Date('2026-10-09T12:00:00Z');
const quietLog = { error() {} };

function setup(saveImpl) {
  const saved = [];
  const handler = createHandler({
    saveFeedback: saveImpl ?? (async (item) => saved.push(item)),
    now: () => fixedNow,
    newId: () => 'test-id',
    log: quietLog,
  });
  return { handler, saved };
}

const post = (body, extra = {}) => ({
  rawPath: '/api/feedback',
  requestContext: { http: { method: 'POST' } },
  headers: { 'content-type': 'application/json' },
  body: typeof body === 'string' ? body : JSON.stringify(body),
  ...extra,
});

const valid = { name: 'Pat', comments: 'Ship it.', favoriteBag: 'midnight-black', favoriteCharm: 'skid-mark', wouldBuy: 'maybe' };

test('health check answers 200', async () => {
  const { handler } = setup();
  const res = await handler({ rawPath: '/api/health', requestContext: { http: { method: 'GET' } } });
  assert.equal(res.statusCode, 200);
});

test('unknown paths are 404 and GET on feedback is 405', async () => {
  const { handler } = setup();
  assert.equal((await handler({ rawPath: '/api/nope' })).statusCode, 404);
  const res = await handler({ rawPath: '/api/feedback', requestContext: { http: { method: 'GET' } } });
  assert.equal(res.statusCode, 405);
  assert.equal(res.headers.allow, 'POST');
});

test('saves a valid submission with id, timestamp and expiry', async () => {
  const { handler, saved } = setup();
  const res = await handler(post(valid));
  assert.equal(res.statusCode, 201);
  assert.equal(JSON.parse(res.body).id, 'test-id');
  assert.equal(saved.length, 1);
  assert.equal(saved[0].createdAt, fixedNow.toISOString());
  assert.equal(saved[0].expiresAt, fixedNow.getTime() / 1000 + RETENTION_DAYS * 86400);
});

test('decodes base64 bodies from the function URL', async () => {
  const { handler, saved } = setup();
  const b64 = Buffer.from(JSON.stringify(valid)).toString('base64');
  const res = await handler(post(b64, { isBase64Encoded: true }));
  assert.equal(res.statusCode, 201);
  assert.equal(saved.length, 1);
});

test('returns field errors for invalid input', async () => {
  const { handler, saved } = setup();
  const res = await handler(post({ name: '' }));
  assert.equal(res.statusCode, 400);
  assert.ok(JSON.parse(res.body).fields.name);
  assert.equal(saved.length, 0);
});

test('rejects malformed JSON and oversized bodies', async () => {
  const { handler } = setup();
  assert.equal((await handler(post('{not json'))).statusCode, 400);
  assert.equal((await handler(post('x'.repeat(MAX_BODY_BYTES + 1)))).statusCode, 413);
});

test('honeypot submissions get 202 and are not stored', async () => {
  const { handler, saved } = setup();
  const res = await handler(post({ ...valid, website: 'http://spam.example' }));
  assert.equal(res.statusCode, 202);
  assert.equal(saved.length, 0);
});

test('storage failure returns 500 without leaking details', async () => {
  const { handler } = setup(async () => { throw new Error('ProvisionedThroughputExceeded secret detail'); });
  const res = await handler(post(valid));
  assert.equal(res.statusCode, 500);
  assert.doesNotMatch(res.body, /secret detail/);
});
