import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateFeedback, LIMITS } from '../src/validate.js';

const good = {
  name: '  Pat  ',
  comments: 'Love the pink one.',
  favoriteBag: 'bubblegum-pink',
  favoriteCharm: 'toots-mcgee',
  wouldBuy: 'yes',
};

test('accepts a complete submission and trims text', () => {
  const r = validateFeedback(good);
  assert.equal(r.ok, true);
  assert.equal(r.value.name, 'Pat');
});

test('defaults bag and charm to not-sure when left blank', () => {
  const r = validateFeedback({ ...good, favoriteBag: '', favoriteCharm: undefined });
  assert.equal(r.ok, true);
  assert.equal(r.value.favoriteBag, 'not-sure');
  assert.equal(r.value.favoriteCharm, 'not-sure');
});

test('requires name, comments and wouldBuy', () => {
  const r = validateFeedback({});
  assert.equal(r.ok, false);
  assert.ok(r.errors.name);
  assert.ok(r.errors.comments);
  assert.ok(r.errors.wouldBuy);
});

test('rejects values outside the allowed lists', () => {
  const r = validateFeedback({ ...good, favoriteBag: 'purple', favoriteCharm: 'dog', wouldBuy: 'sure' });
  assert.equal(r.ok, false);
  assert.deepEqual(Object.keys(r.errors).sort(), ['favoriteBag', 'favoriteCharm', 'wouldBuy']);
});

test('enforces length limits', () => {
  const r = validateFeedback({ ...good, name: 'x'.repeat(LIMITS.name + 1), comments: 'y'.repeat(LIMITS.comments + 1) });
  assert.equal(r.ok, false);
  assert.ok(r.errors.name);
  assert.ok(r.errors.comments);
});

test('ignores non-object input', () => {
  assert.equal(validateFeedback(null).ok, false);
  assert.equal(validateFeedback('hello').ok, false);
});
