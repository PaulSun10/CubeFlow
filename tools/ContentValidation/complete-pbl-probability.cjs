const fs = require('fs'), assert = require('assert/strict'), m = require('./square-one-model.cjs');
const root = 'CubeFlow/Resources/Algs/';
const pbl = JSON.parse(fs.readFileSync(root + 'sq1pbl.json'));
function multiplicity(arr, solved) {
  const seen = new Set();
  for (let a = 0; a < 4; a++) for (let b = 0; b < 4; b++) {
    const map = {};
    for (let i = 0; i < 12; i++) map[solved[i]] = solved[(i + a * 3) % 12];
    seen.add(arr.slice(b * 3).concat(arr.slice(0, b * 3)).map(v => map[v]).join(','));
  }
  return seen.size;
}
const weights = new Map();
for (const c of pbl.cases) weights.set(c.name.split(' / ')[0], multiplicity(c.nativeState.top, m.solved().top));
assert.equal([...weights.values()].reduce((a, b) => a + b, 0), 576);
assert.equal(weights.get('-'), 4);
const denominator = 576 * 576 - 4 * 4;
let count = 0;
for (const name of ['sq1pbl', 'sq1pblparity']) {
  const file = root + name + '.json', data = JSON.parse(fs.readFileSync(file));
  for (const c of data.cases) {
    const [a, b] = c.name.split(' / '), numerator = weights.get(a) * weights.get(b);
    assert(Math.abs(c.probability - numerator / denominator) < 1e-14);
    c.probabilityExact = {numerator, denominator}; count++;
  }
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
}
console.log(JSON.stringify({pblExactProbabilities: count, denominator}));
