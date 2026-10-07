// Public facts only; no third-party implementation or algorithm collection is copied.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const [sha, exportDate, output] = process.argv.slice(2);
assert.match(sha ?? '', /^[0-9a-f]{40}$/);
assert.match(exportDate ?? '', /^\d{4}-\d{2}-\d{2}$/);
assert.ok(output);
const base = `https://raw.githubusercontent.com/robiningelbrecht/wca-rest-api/${sha}/`;
async function page(number) {
  const response = await fetch(base + (number === 1 ? 'competitions.json' : `competitions-page-${number}.json`));
  assert.ok(response.ok, `Page ${number}: HTTP ${response.status}`);
  const value = await response.json();
  assert.equal(value.pagination.page, number);
  return value;
}
const first = await page(1);
const all = [...first.items];
for (let number = 2; number <= Math.ceil(first.total / first.pagination.size); number++) {
  const value = await page(number);
  assert.equal(value.total, first.total, 'Inconsistent export pages');
  all.push(...value.items);
  console.log(`Page ${number}: ${all.length}/${first.total}`);
}
assert.equal(all.length, first.total);
assert.equal(new Set(all.map(x => x.id)).size, all.length, 'Duplicate competitions');
// Future announcements and cancelled competitions do not count as history.
const past = all.filter(x => !x.isCanceled && x.date.till < exportDate);
assert.ok(past.length > 10000);
const valid = past.filter(x => Number.isFinite(x.venue?.coordinates?.latitude) &&
  Number.isFinite(x.venue?.coordinates?.longitude) && Math.abs(x.venue.coordinates.latitude) <= 90 &&
  Math.abs(x.venue.coordinates.longitude) <= 180 &&
  (x.venue.coordinates.latitude !== 0 || x.venue.coordinates.longitude !== 0));
const compact = x => ({id:x.id, name:x.name, city:x.city, country:x.country,
  start:x.date.from, end:x.date.till, latitude:x.venue?.coordinates?.latitude ?? null,
  longitude:x.venue?.coordinates?.longitude ?? null, events:x.events});
const north = Math.max(...valid.map(x=>x.venue.coordinates.latitude));
const south = Math.min(...valid.map(x=>x.venue.coordinates.latitude));
const counts = values => Object.entries(values.reduce((a,x)=>(a[x]=(a[x]??0)+1,a),{}))
  .map(([id,count])=>({id,count})).sort((a,b)=>b.count-a.count||a.id.localeCompare(b.id));
const byYear = counts(past.map(x=>x.date.from.slice(0,4))).sort((a,b)=>b.id.localeCompare(a.id));
const earliest = past.reduce((a,b)=>a.date.from < b.date.from ? a : b);
const mostEvents = Math.max(...past.map(x=>x.events.length));
const summary = {exportDate, sourceCommit:sha, sourceURL:'https://wca-rest-api.robiningelbrecht.be/',
  inputCount:all.length, completedCount:past.length, locatedCount:valid.length,
  countries:counts(past.map(x=>x.country)), years:byYear, events:counts(past.flatMap(x=>x.events)),
  northernmost:valid.filter(x=>x.venue.coordinates.latitude===north).map(compact),
  southernmost:valid.filter(x=>x.venue.coordinates.latitude===south).map(compact),
  earliest:[compact(earliest)], eventRich:past.filter(x=>x.events.length===mostEvents).map(compact)};
await fs.writeFile(output, JSON.stringify(summary, null, 2)+'\n');
console.log(`Verified ${all.length} distinct rows; ${past.length} completed; ${valid.length} located`);
console.log(`Latitude bounds: ${south} … ${north}`);
