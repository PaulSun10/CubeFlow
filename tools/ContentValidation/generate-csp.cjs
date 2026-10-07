// Independently generated references; external algorithm collections are not imported.
const fs = require('fs'), assert = require('assert/strict'), m = require('./square-one-model.cjs');
const sh = require('./square-one-shapes.cjs');
const file = 'CubeFlow/Resources/Algs/sq1csp.json';
const previous = JSON.parse(fs.readFileSync(file)).cases;
const queue = sh.graph(), physical = sh.universe(), shapes = new Map(), counts = new Map();
for (const node of queue) {
  const key = sh.presentation(node.state);
  counts.set(key, (counts.get(key) || 0) + 1);
  if (!shapes.has(key)) shapes.set(key, node);
}
assert.deepEqual(new Set(shapes.keys()), physical); // Geometric tilings and legal transitions agree.
const rows = []; let retained = 0;
for (const [shape, candidate] of [...shapes].sort(([a], [b]) => a.localeCompare(b))) {
  // Retain an existing reference only under its actual ordered physical presentation.
  const old = previous.filter(c => sh.presentation(c.nativeState) === shape);
  const even = old.find(c => c.csp.traceParity === 0);
  const first = even ? {state: even.nativeState, sequence: m.steps(even.setup)} : candidate;
  const same = queue.find(n => sh.bits(n.state.top) === sh.bits(first.state.top)
    && sh.bits(n.state.bottom) === sh.bits(first.state.bottom) && sh.parity(n.state, first.state) === 1);
  assert(same);
  const title = sh.pattern(first.state.top) + ' / ' + sh.pattern(first.state.bottom);
  for (const [parity, generated] of [[0, first], [1, same]]) {
    const existing = old.find(c => c.csp.traceParity === parity
      && sh.bits(c.nativeState.top) === sh.bits(first.state.top)
      && sh.bits(c.nativeState.bottom) === sh.bits(first.state.bottom)
      && sh.parity(c.nativeState, first.state) === parity);
    const node = existing ? {state: existing.nativeState, sequence: m.steps(existing.setup)} : generated;
    const solution = m.inverse(node.sequence), setup = m.format(node.sequence);
    assert.deepEqual(m.apply(m.steps(setup)), node.state);
    assert.deepEqual(m.apply(solution, structuredClone(node.state)), m.solved());
    assert.equal(sh.parity(node.state, first.state), parity);
    if (existing) retained++;
    const id = existing?.id || 'csp_present_' + shape.replace('|', '_') + '_' + parity;
    const count = (() => { const goal = sh.pieces(first.state), p = sh.pieces(node.state).map(v => goal.indexOf(v));
      let visited = new Set(), swaps = 0;
      for (let i = 0; i < 16; i++) { if (visited.has(i)) continue; let j = i, n = 0;
        do { visited.add(j); n++; j = p[j]; } while (!visited.has(j)); swaps += n - 1; }
      return swaps; })();
    rows.push({id, name: title, displayName: parity ? 'Odd' : 'Even', group: title, subgroup: parity ? 'Odd' : 'Even',
      imageKey: existing?.imageKey || 'sq1csp_' + id, recognition: '',
      notes: 'Top / bottom are ordered physical presentations; C = corner, E = edge in sector order. Count against this presentation\u2019s even reference, top then bottom from sector 0, following piece cycles. Layer alignment is part of the counting frame. Not the Cale color-count convention. Generated mathematical reference, not a curated speed algorithm.',
      setup: existing?.setup ?? setup,
      algorithms: existing?.algorithms ?? (node.sequence.length ? [{id: id + '-reference', notation: m.format(solution),
        isPrimary: true, source: 'CubeFlow independent ordered shape/parity BFS', tags: ['reference', 'inverse-setup', parity ? 'odd' : 'even']}] : []),
      nativeState: node.state,
      csp: {shapeID: shape, traceParity: parity, swapCount: count, countingTop: 0, countingBottom: 0,
        convention: 'cubeflow-piece-cycles-v1', referenceTop: first.state.top, referenceBottom: first.state.bottom},
      probability: counts.get(shape) / queue.length / 2,
      probabilityExact: {numerator: counts.get(shape), denominator: queue.length * 2},
      probabilityBasis: 'Uniform slice-aligned boundary/parity states, conditioned on counting frame. Not WCA scramble or empirical solve frequency.'});
  }
}
fs.writeFileSync(file, JSON.stringify({puzzle: 'SQ1', set: 'SQ1CSP', version: 1,
  source: `CubeFlow independent enumeration: ${shapes.size} ordered physical presentations, two deterministic reference-count parities each; ${queue.length} aligned shape/parity states. No layer sorting, no nested inverted cases. Curated speed algorithms remain permission-gated.`, cases: rows}, null, 2) + '\n');
const result = {physicalPresentations: shapes.size, parityContexts: rows.length, retainedNormalContexts: retained,
  addedContexts: rows.length - retained, referenceFormulas: rows.flatMap(c => c.algorithms).length,
  distinctReferenceExecutionsIncludingIdentity: new Set(rows.map(c => c.algorithms[0]?.notation || '')).size,
  alignedShapeParityStates: queue.length, probabilitySum: rows.reduce((n, c) => n + c.probability, 0)};
console.log(JSON.stringify(result));
