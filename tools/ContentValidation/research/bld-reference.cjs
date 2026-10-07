// Research only. An explicit, aligned reference is mandatory; no reference oracle.
const fs = require('node:fs');
const model = require('../square-one-model.cjs');
const shapes = require('../square-one-shapes.cjs');

function validateState(state) {
  if (!state || ![state.top, state.bottom].every(a => Array.isArray(a) && a.length === 12
      && a.every(id => Number.isInteger(id) && id >= 0 && id < 16))) {
    throw Error('Expected top/bottom arrays of twelve sectors with IDs 0...15');
  }
  for (let id = 0; id < 16; id++) {
    let sectors = 0, starts = 0;
    for (const ring of [state.top, state.bottom]) {
      sectors += ring.filter(v => v === id).length;
      starts += ring.filter((v, i) => v === id && v !== ring[(i + 11) % 12]).length;
    }
    if (sectors !== (id % 2 ? 2 : 1) || starts !== 1) {
      throw Error('Each edge must occupy one sector and each corner two adjacent cyclic sectors');
    }
  }
}

function cycles(permutation, visitOrder = permutation.map((_, i) => i)) {
  const expected = permutation.map((_, i) => i);
  if (JSON.stringify([...permutation].sort((a, b) => a - b)) !== JSON.stringify(expected)
      || JSON.stringify([...visitOrder].sort((a, b) => a - b)) !== JSON.stringify(expected)) {
    throw Error('Expected a permutation and a complete visit order');
  }
  const seen = new Set(), result = [];
  for (const start of visitOrder) {
    if (seen.has(start)) continue;
    const cycle = [];
    for (let i = start; !seen.has(i); i = permutation[i]) {
      seen.add(i); cycle.push(i);
    }
    result.push(cycle);
  }
  return {cycles: result, count: result.reduce((n, c) => n + c.length - 1, 0)};
}

function trace(actual, reference, options = {}) {
  validateState(actual); validateState(reference);
  // No automatic rotation/reflection: sector anchors belong to the supplied convention.
  if (shapes.bits(actual.top) !== shapes.bits(reference.top)
      || shapes.bits(actual.bottom) !== shapes.bits(reference.bottom)) {
    throw Error('Reference must have identical aligned piece boundaries, not just the same shape name');
  }
  function part(corners) {
    const positions = [];
    for (const layer of ['top', 'bottom']) {
      actual[layer].forEach((id, sector) => {
        if (id !== actual[layer][(sector + 11) % 12] && Boolean(id % 2) === corners) {
          positions.push({layer, sector, actualID: id, referenceID: reference[layer][sector]});
        }
      });
    }
    const ids = positions.map(p => p.actualID), goal = positions.map(p => p.referenceID);
    const permutation = ids.map(id => goal.indexOf(id));
    const result = cycles(permutation, corners ? options.cornerOrder : options.edgeOrder);
    return {positions, permutation, cycles: result.cycles,
      pieceCycles: result.cycles.map(c => c.map(i => ids[i])), traceCount: result.count};
  }
  const corners = part(true), edges = part(false);
  const total = corners.traceCount + edges.traceCount;
  return {corners, edges, total, parity: total % 2, label: total % 2 ? 'Odd' : 'Even',
    caveat: 'Relative to the supplied reference only; this does not authenticate its recognition convention.'};
}

function cardinalities() {
  const ordered = [...shapes.universe()];
  const unordered = new Set(ordered.map(s => s.split('|').sort().join('|')));
  const fixed = ordered.filter(s => { const [a, b] = s.split('|'); return a === b; });
  const layers = [...new Set(ordered.flatMap(s => s.split('|')))];
  const byCorners = {};
  for (const layer of layers) {
    const corners = [...layer].filter(c => c === '0').length;
    byCorners[corners] = (byCorners[corners] || 0) + 1;
  }
  return {ordered: ordered.length, unordered: unordered.size, fixed: fixed.length,
    twoElementOrbits: (ordered.length - fixed.length) / 2, contexts: ordered.length * 2,
    distinctLayerShapes: layers.length, layerShapesByCornerCount: byCorners,
    quotient: 'Independent cyclic layer alignment, then top/bottom exchange. No reflection quotient.'};
}

function audit() {
  const cases = require('../../../CubeFlow/Resources/Algs/sq1csp.json').cases;
  const anchors = ['csp_010101110111_010101110111_1', 'csp_010101011111_010101110111_0'].map(id => {
    const item = cases.find(c => c.id === id);
    const actual = model.apply(model.steps(item.setup));
    const privateReference = {top: item.csp.referenceTop, bottom: item.csp.referenceBottom};
    return {id, actual, privateReference, privateTrace: trace(actual, privateReference),
      userRecordedTotal: id.endsWith('_1') ? 8 : 10,
      externalReference: null, externalTrace: null,
      status: 'Exact Japanese/user reference not independently recovered; no external reproduction claimed.'};
  });
  const baseline = model.solved();
  const phased = structuredClone(baseline);
  phased.top = phased.top.map(id => id % 2 ? ({1: 3, 3: 5, 5: 7, 7: 1})[id] : id);
  return {scope: 'Isolated research, no production writes', cardinalities: cardinalities(), anchors,
    cyclicOrderAmbiguity: {description: 'One top corner phase shift preserves its cyclic order but is a four-cycle.',
      baseline: trace(baseline, baseline), shiftedReference: phased, shifted: trace(baseline, phased)}};
}

module.exports = {validateState, cycles, trace, cardinalities, audit};
if (require.main === module) {
  const input = process.argv[2] && JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  console.log(JSON.stringify(input ? trace(input.actual, input.reference, input.options) : audit(), null, 2));
}
