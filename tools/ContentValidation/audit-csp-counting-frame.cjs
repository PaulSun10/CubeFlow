// Diagnostic audit, not a replacement community counting convention.
// Fixed corner/edge piece orders are independent of generated CSP references.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const model = require('./square-one-model.cjs');
const shapes = require('./square-one-shapes.cjs');
const cases = require('../../CubeFlow/Resources/Algs/sq1csp.json').cases;

function permutation(state, corners) {
  const result = [];
  for (const ring of [state.top, state.bottom]) {
    for (let i = 0; i < 12; i++) {
      const id = ring[i];
      if (id === ring[(i + 11) % 12] || Boolean(id % 2) !== corners) continue;
      result.push(corners ? (id - 1) / 2 : id / 2);
    }
  }
  assert.deepEqual(result.slice().sort((a, b) => a - b), [0, 1, 2, 3, 4, 5, 6, 7]);
  return result;
}
function sign(p) {
  let result = 0;
  for (let i = 0; i < p.length; i++) for (let j = i + 1; j < p.length; j++) result ^= +(p[i] > p[j]);
  return result;
}
function inspect(item) {
  const state = model.apply(model.steps(item.setup));
  assert.deepEqual(state, item.nativeState);
  assert.equal(shapes.presentation(state), item.csp.shapeID);
  const corners = permutation(state, true), edges = permutation(state, false);
  const parity = sign(corners) ^ sign(edges);
  const result = model.apply(model.steps(item.algorithms[0]?.notation || ''), structuredClone(state));
  assert.deepEqual(result, model.solved());
  const reference = {top: item.csp.referenceTop, bottom: item.csp.referenceBottom};
  return {id: item.id, setup: item.setup, solution: item.algorithms[0]?.notation || '', state,
    shape: shapes.presentation(state), corners, edges,
    cornerSign: sign(corners), edgeSign: sign(edges), fixedPieceOrderParity: parity,
    privateLabel: item.displayName, privateSwapCount: item.csp.swapCount,
    privateReferenceFixedParity: sign(permutation(reference, true)) ^ sign(permutation(reference, false)),
    solutionSlices: model.steps(item.algorithms[0]?.notation || '').filter(s => s === '/').length,
    exactSolvedAfterStoredSolution: true};
}
const entries = cases.map(inspect);
const shield = entries.find(c => c.id === 'csp_010101110111_010101110111_1');
const control = entries.find(c => c.id === 'csp_010101011111_010101110111_0');
assert.deepEqual(shield.corners, [7, 1, 0, 6, 5, 3, 2, 4]);
assert.deepEqual(shield.edges, [0, 6, 1, 7, 2, 4, 3, 5]);
assert.equal(shield.fixedPieceOrderParity, 0);
assert.equal(shield.privateReferenceFixedParity, 1);
assert.equal(control.fixedPieceOrderParity, 0);
assert.equal(control.privateReferenceFixedParity, 0);
const report = {
  status: 'Community counting-frame calibration unresolved; do not relabel from this audit alone.',
  convention: 'Top then bottom, piece starts from sector 0, corners and edges separately, IDs in solved order.',
  warning: 'This fixed-order sign is not a claim about an unspecified Cale/standard-form counting orientation.',
  setupAndSolutionChecks: entries.length, orderedPresentations: new Set(entries.map(e => e.shape)).size,
  privateLabelsDifferingFromFixedPieceOrder: entries.filter(e => e.fixedPieceOrderParity !== +(e.privateLabel === 'Odd')).length,
  shieldShieldOdd: shield, shieldScallopEvenControl: control,
  publicOracle: {
    source: 'https://speedcubedb.com/SQ1/Trace',
    observedShieldSetupAtDefaultPositions: '3 = Odd',
    observedShieldSetupAfterOneTopCountingPositionIncrement: '2 = Even',
    observedControlAtDefaultPositions: '4 = Even',
    significance: 'Same state can receive opposite practical trace labels under different counting origins.'
  }, entries
};
if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({...report, entries: undefined}, null, 2));
