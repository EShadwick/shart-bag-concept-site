// Converts `aws dynamodb scan --output json` output into a CSV, newest first.
// Usage: node scripts/feedback-to-csv.mjs feedback.json > feedback.csv
import { readFileSync } from 'node:fs';

const file = process.argv[2];
if (!file) {
  console.error('usage: node scripts/feedback-to-csv.mjs <scan.json>');
  process.exit(2);
}

const columns = ['createdAt', 'name', 'favoriteBag', 'favoriteCharm', 'wouldBuy', 'comments', 'id'];
const scan = JSON.parse(readFileSync(file, 'utf8'));
const plain = (attr) => (attr ? attr.S ?? attr.N ?? '' : '');
const csvCell = (value) => {
  const text = String(value);
  // Neutralize spreadsheet formulas and quote everything.
  const safe = /^[=+\-@]/.test(text) ? `'${text}` : text;
  return `"${safe.replace(/"/g, '""')}"`;
};

const rows = (scan.Items || [])
  .map((item) => Object.fromEntries(columns.map((c) => [c, plain(item[c])])))
  .sort((a, b) => b.createdAt.localeCompare(a.createdAt));

process.stdout.write(columns.join(',') + '\n');
for (const row of rows) process.stdout.write(columns.map((c) => csvCell(row[c])).join(',') + '\n');
