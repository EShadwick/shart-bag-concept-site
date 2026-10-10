// Request handling for the feedback API, written against the Lambda function URL
// event shape (payload format 2.0). Storage is injected so tests never touch AWS.

import { randomUUID } from 'node:crypto';
import { validateFeedback } from './validate.js';

export const MAX_BODY_BYTES = 10 * 1024;
export const RETENTION_DAYS = 180;

const json = (statusCode, body, extraHeaders = {}) => ({
  statusCode,
  headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...extraHeaders },
  body: JSON.stringify(body),
});

function readBody(event) {
  if (!event.body) return '';
  return event.isBase64Encoded ? Buffer.from(event.body, 'base64').toString('utf8') : event.body;
}

export function createHandler({ saveFeedback, now = () => new Date(), newId = randomUUID, log = console }) {
  if (typeof saveFeedback !== 'function') throw new Error('saveFeedback is required');

  return async function handler(event = {}) {
    const method = event.requestContext?.http?.method ?? 'GET';
    const path = event.rawPath ?? '/';

    if (path.endsWith('/health')) return json(200, { status: 'ok' });
    if (!path.endsWith('/feedback')) return json(404, { error: 'Not found' });
    if (method !== 'POST') return json(405, { error: 'Use POST' }, { allow: 'POST' });

    const raw = readBody(event);
    if (Buffer.byteLength(raw, 'utf8') > MAX_BODY_BYTES) return json(413, { error: 'Feedback is too large' });

    let payload;
    try {
      payload = JSON.parse(raw || '{}');
    } catch {
      return json(400, { error: 'Body must be JSON' });
    }

    // Honeypot: real people never fill the hidden "website" field. Pretend success, store nothing.
    if (payload && typeof payload.website === 'string' && payload.website.trim() !== '') {
      return json(202, { status: 'received' });
    }

    const result = validateFeedback(payload);
    if (!result.ok) return json(400, { error: 'Please fix the highlighted fields', fields: result.errors });

    const createdAt = now();
    const item = {
      id: newId(),
      createdAt: createdAt.toISOString(),
      expiresAt: Math.floor(createdAt.getTime() / 1000) + RETENTION_DAYS * 24 * 60 * 60,
      ...result.value,
    };

    try {
      await saveFeedback(item);
    } catch (err) {
      log.error('saveFeedback failed', { message: err?.message });
      return json(500, { error: 'Could not save feedback. Try again in a minute.' });
    }

    return json(201, { status: 'saved', id: item.id });
  };
}
