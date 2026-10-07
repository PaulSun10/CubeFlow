const test = require('node:test');
const assert = require('node:assert/strict');
const {trace, cycles, cardinalities, audit} = require('./bld-reference.cjs');
const model = require('../square-one-model.cjs');

function* permutations(values) {
  if (!values.length) { yield []; return; }
  for (let i = 0; i < values.length; i++) {
    for (const tail of permutations(values.filter((_, j) => i !== j))) yield [values[i], ...tail];
  }
}

test('all 40320 eight-piece permutations agree with independent inversion sign and every start', () => {
  let checked = 0;
  for (const p of permutations([0, 1, 2, 3, 4, 5, 6, 7])) {
    let inversions = 0;
    for (let i = 0; i < 8; i++) for (let j = i + 1; j < 8; j++) inversions += +(p[i] > p[j]);
    const count = cycles(p).count;
    assert.equal(count % 2, inversions % 2);
    for (let start = 0; start < 8; start++) {
      const order = Array.from({length: 8}, (_, i) => (start + i) % 8).reverse();
      assert.equal(cycles(p, order).count, count);
    }
    checked++;
  }
  assert.equal(checked, 40320);
});

test('identity has zero count, including corners wrapping across sector zero', () => {
  const s = model.apply([[1, 2]], model.solved());
  assert.equal(trace(s, s).total, 0);
});

test('explicit piece cycles have sum(length - 1) and corner/edge order independence', () => {
  const r = model.solved(), s = structuredClone(r);
  const remap = {1: 3, 3: 5, 5: 1, 0: 2, 2: 0, 8: 10, 10: 8};
  for (const layer of ['top', 'bottom']) s[layer] = s[layer].map(id => remap[id] ?? id);
  const normal = trace(s, r);
  assert.equal(normal.corners.traceCount, 2);
  assert.equal(normal.edges.traceCount, 2);
  assert.equal(normal.label, 'Even');
  const reversed = trace(s, r, {cornerOrder: [7, 6, 5, 4, 3, 2, 1, 0], edgeOrder: [3, 4, 5, 6, 7, 0, 1, 2]});
  assert.equal(reversed.total, normal.total);
  assert.equal(reversed.edges.traceCount + reversed.corners.traceCount, normal.total);
  assert.equal(trace(r, s).total, normal.total); // Inversion preserves cycle lengths.
});

test('simultaneous color renaming and positional transport preserve exact counts', () => {
  const r = model.solved(), s = structuredClone(r);
  s.top = s.top.map(id => ({1: 3, 3: 1})[id] ?? id);
  const expected = trace(s, r).total;
  function rename(state) {
    return {top: state.top.map(id => (id + 4) % 16), bottom: state.bottom.map(id => (id + 4) % 16)};
  }
  assert.equal(trace(rename(s), rename(r)).total, expected);
  for (let a = 0; a < 12; a++) for (let b = 0; b < 12; b++) {
    assert.equal(trace(model.apply([[a, b]], structuredClone(s)), model.apply([[a, b]], structuredClone(r))).total, expected);
  }
});

test('changing the reference alone by an odd permutation flips the class', () => {
  const data = audit().cyclicOrderAmbiguity;
  assert.equal(data.baseline.total, 0);
  assert.equal(data.shifted.total, 3);
  assert.equal(data.shifted.label, 'Odd');
});

test('invalid pieces, visit orders and unaligned boundaries are rejected rather than guessed', () => {
  const s = model.solved();
  assert.throws(() => trace(s, {...s, top: s.top.map(() => 0)}));
  assert.throws(() => cycles([0, 0]));
  assert.throws(() => cycles([0, 1], [1, 1]));
  assert.throws(() => trace(s, model.apply([[1, 0]], model.solved())));
  const split = structuredClone(s); [split.top[1], split.top[4]] = [split.top[4], split.top[1]];
  assert.throws(() => trace(split, split));
});

test('90 unordered pairs expand to 170 ordered presentations and 340 contexts, without reflection', () => {
  const c = cardinalities();
  assert.equal(c.ordered, 170); assert.equal(c.unordered, 90); assert.equal(c.fixed, 10);
  assert.equal(c.twoElementOrbits, 80); assert.equal(c.contexts, 340);
  assert.deepEqual(c.layerShapesByCornerCount, {2: 5, 3: 10, 4: 10, 5: 3, 6: 1});
});

test('production-anchor private counts are diagnostic only, never fabricated external references', () => {
  const anchors = audit().anchors;
  assert.equal(anchors[0].privateTrace.total, 9);
  assert.equal(anchors[1].privateTrace.total, 0);
  assert.deepEqual(anchors.map(a => a.externalReference), [null, null]);
  assert.deepEqual(anchors.map(a => a.externalTrace), [null, null]);
});
