// Check solution parity on arbitrary labelled states, not just setup/inverse pairs.
const assert = require('assert/strict'), m = require('./square-one-model.cjs');
const cases = require('../../CubeFlow/Resources/Algs/sq1csp.json').cases;
const pieces = s => [s.top, s.bottom].flatMap(a => a.filter((v, i) => v !== a[(i + 11) % 12]));
function parity(state, reference) {
  const goal = pieces(reference), permutation = pieces(state).map(v => goal.indexOf(v));
  assert.equal(new Set(permutation).size, 16);
  let sign = 0;
  for (let i = 0; i < 16; i++) for (let j = i + 1; j < 16; j++) sign ^= +(permutation[i] > permutation[j]);
  return sign;
}
let seed = 7919, checked = 0;
const random = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
function shuffled(ids) {
  const result = ids.slice();
  for (let i = result.length - 1; i > 0; i--) { const j = random() % (i + 1); [result[i], result[j]] = [result[j], result[i]]; }
  return result;
}
for (const even of cases.filter(c => c.csp.traceParity === 0)) {
  const odd = cases.find(c => c.csp.shapeID === even.csp.shapeID && c.csp.traceParity === 1);
  for (let trial = 0; trial < 30; trial++) {
    const edges = shuffled([0,2,4,6,8,10,12,14]), corners = shuffled([1,3,5,7,9,11,13,15]);
    const map = id => id % 2 ? corners[(id - 1) / 2] : edges[id / 2];
    const state = {top: even.nativeState.top.map(map), bottom: even.nativeState.bottom.map(map), m: 0};
    const count = parity(state, even.nativeState), selected = count ? odd : even, opposite = count ? even : odd;
    const solvedShape = m.apply(m.steps(selected.algorithms[0]?.notation || ''), structuredClone(state));
    const wrongShape = m.apply(m.steps(opposite.algorithms[0]?.notation || ''), structuredClone(state));
    const types = s => [s.top, s.bottom].map(a => a.map(id => id % 2));
    assert.deepEqual(types(solvedShape), types(m.solved()));
    assert.deepEqual(types(wrongShape), types(m.solved()));
    assert.equal(parity(solvedShape, m.solved()), 0);
    assert.equal(parity(wrongShape, m.solved()), 1);
    checked++;
  }
}
assert.equal(checked, cases.filter(c => c.csp.traceParity === 0).length * 30);
console.log(JSON.stringify({arbitraryLabelledStates: checked, selectedToEvenCubeshape: checked, oppositeToOddCubeshape: checked}));
