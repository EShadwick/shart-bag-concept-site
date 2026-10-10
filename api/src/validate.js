// Input rules for a feedback submission from the concept preview.
// Pure function, no AWS dependencies, so it is easy to unit test.

export const BAGS = ['midnight-black', 'bubblegum-pink', 'emergency-shart-kit', 'not-sure'];
export const CHARMS = ['steven-sharts', 'skid-mark', 'toots-mcgee', 'not-sure'];
export const WOULD_BUY = ['yes', 'maybe', 'no'];

export const LIMITS = { name: 80, comments: 2000 };

const clean = (value) => (typeof value === 'string' ? value.trim() : '');

export function validateFeedback(input) {
  const errors = {};
  const src = input && typeof input === 'object' ? input : {};

  const name = clean(src.name);
  const comments = clean(src.comments);
  const favoriteBag = clean(src.favoriteBag) || 'not-sure';
  const favoriteCharm = clean(src.favoriteCharm) || 'not-sure';
  const wouldBuy = clean(src.wouldBuy);

  if (!name) errors.name = 'Name is required.';
  else if (name.length > LIMITS.name) errors.name = `Name must be ${LIMITS.name} characters or fewer.`;

  if (!comments) errors.comments = 'Comments are required.';
  else if (comments.length > LIMITS.comments) errors.comments = `Comments must be ${LIMITS.comments} characters or fewer.`;

  if (!BAGS.includes(favoriteBag)) errors.favoriteBag = 'Pick one of the listed bags.';
  if (!CHARMS.includes(favoriteCharm)) errors.favoriteCharm = 'Pick one of the listed charms.';
  if (!WOULD_BUY.includes(wouldBuy)) errors.wouldBuy = 'Answer yes, maybe or no.';

  const ok = Object.keys(errors).length === 0;
  return ok
    ? { ok, value: { name, comments, favoriteBag, favoriteCharm, wouldBuy } }
    : { ok, errors };
}
