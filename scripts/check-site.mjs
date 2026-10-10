// CI check: every local file referenced by the site's HTML pages must exist,
// and every in-page #anchor must point at a real id. Node built-ins only.
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'site');
const pages = readdirSync(root).filter((f) => f.endsWith('.html'));
const problems = [];

for (const page of pages) {
  const html = readFileSync(join(root, page), 'utf8');
  const ids = new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
  const refs = [...html.matchAll(/\s(?:src|href|poster)="([^"]+)"/g)].map((m) => m[1]);

  for (const ref of refs) {
    if (/^(https?:|mailto:|tel:|data:)/.test(ref)) continue;
    if (ref.startsWith('#')) {
      if (ref.length > 1 && !ids.has(ref.slice(1))) problems.push(`${page}: anchor ${ref} has no matching id`);
      continue;
    }
    const clean = ref.split(/[?#]/)[0];
    if (clean === '' || clean === './' || clean === '/') continue;
    const target = normalize(join(root, clean.replace(/^\//, '')));
    if (!target.startsWith(root) || !existsSync(target)) problems.push(`${page}: missing file ${ref}`);
  }
  console.log(`checked ${page}: ${refs.length} references`);
}

if (problems.length) {
  console.error(problems.join('\n'));
  process.exit(1);
}
console.log('site check passed');
