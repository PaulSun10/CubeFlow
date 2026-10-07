// Product-boundary audit: physical tilings, labels, notation, parity, references, and legacy CS comparison.
const fs = require('fs'), vm = require('vm'), assert = require('assert/strict');
const m = require('./square-one-model.cjs'), sh = require('./square-one-shapes.cjs');
const cases = require('../../CubeFlow/Resources/Algs/sq1csp.json').cases;
const cs = require('../../CubeFlow/Resources/Algs/sq1cs.json').cases;
const universe = sh.universe(), solved = sh.presentation(m.solved());
const byPresentation = new Map();
// Execute the already-bundled packed renderer model as an independent notation/state oracle.
// No external implementation is imported or duplicated into production.
const source = fs.readFileSync('CubeFlow/Resources/DrawScramble/cubes/squareone.js', 'utf8');
const sandbox = {require: () => ({}), module: {exports: {}}};
vm.runInNewContext(source.replace('var ep = [', 'globalThis.packedCubie = SqCubie; var ep = ['), sandbox);
function packed(notation) {
  const cube = new sandbox.packedCubie();
  for (const step of m.steps(notation)) {
    if (step === '/') cube.doMove(0);
    else { if (step[0]) cube.doMove((step[0] + 12) % 12); if (step[1]) cube.doMove(-((step[1] + 12) % 12)); }
  }
  return {top: Array.from({length: 12}, (_, i) => cube.pieceAt(i)),
    bottom: Array.from({length: 12}, (_, i) => cube.pieceAt(i + 12)), m: cube.ml};
}
const inversion = key => key.split('|').reverse().map(b => sh.cycle([...b].reverse().join(''))).join('|');
const swap = key => key.split('|').reverse().join('|');
for (const c of cases) {
  const state = m.apply(m.steps(c.setup)), key = sh.presentation(state);
  assert.deepEqual(state, c.nativeState);
  assert.deepEqual(packed(c.setup), state);
  assert.equal(key, c.csp.shapeID);
  assert.equal(sh.pattern(state.top) + ' / ' + sh.pattern(state.bottom), c.name);
  assert.equal(c.name, c.group);
  assert.equal(c.displayName, c.csp.traceParity ? 'Odd' : 'Even');
  assert.equal(c.algorithmGroups, undefined); // No hidden pose change under the visible diagram.
  const reference = {top: c.csp.referenceTop, bottom: c.csp.referenceBottom, m: 0};
  assert.equal(sh.presentation(reference), key);
  assert.equal(sh.bits(state.top), sh.bits(reference.top));
  assert.equal(sh.bits(state.bottom), sh.bits(reference.bottom));
  assert.equal(sh.parity(state, reference), c.csp.traceParity);
  const result = m.apply(m.steps(c.algorithms[0]?.notation || ''), structuredClone(state));
  assert.deepEqual(result, m.solved());
  const values = byPresentation.get(key) || []; values.push(c); byPresentation.set(key, values);
}
assert.deepEqual(new Set(byPresentation.keys()), universe);
for (const rows of byPresentation.values()) assert.deepEqual(rows.map(c => c.csp.traceParity).sort(), [0,1]);
// Independent labelled physical fixtures: five-corner upper layer / 3-3 lower layer.
// "Five-star" is ambiguous, so cover all three possible five-corner geometries without guessing a nickname.
const threeThree = '010111101111', fiveCorner = ['010101010111', '010101011011', '010101101011'];
const shieldMuffin = '010101110111|010110101111';
const regression = [];
for (const top of fiveCorner) {
  const key = top + '|' + threeThree, rows = byPresentation.get(key);
  assert(rows && rows.length === 2);
  for (const c of rows) {
    const s = packed(c.setup);
    assert.equal(sh.presentation(s), key);
    assert.equal(s.top.filter((v,i) => v !== s.top[(i+11)%12] && v % 2).length, 5);
    assert.equal(s.bottom.filter((v,i) => v !== s.bottom[(i+11)%12] && v % 2).length, 3);
    assert.notEqual(sh.presentation(s), shieldMuffin);
    regression.push({id: c.id, presentation: key, parity: c.csp.traceParity, setup: c.setup});
  }
}
// Both chirality and order survive recognition. Rigid inversion reverses each ring AND swaps layers.
const topBottomEquivalent = [...universe].filter(k => swap(k) === k);
const inversionEquivalent = [...universe].filter(k => inversion(k) === k);
for (const k of universe) { assert(universe.has(inversion(k))); assert(universe.has(swap(k))); }
const csKeys = new Set(), invalidCS = [], duplicateCS = new Map();
for (const c of cs) {
  try {
    const key = sh.presentation(m.apply(m.steps(c.setup || ''))); csKeys.add(key);
    duplicateCS.set(key, [...(duplicateCS.get(key) || []), c.id]);
  } catch (e) { invalidCS.push({id: c.id, reason: e.message}); }
}
const csOnly = [...csKeys].filter(k => !universe.has(k));
const cspOnly = [...universe].filter(k => !csKeys.has(k));
assert.deepEqual(csOnly, []);
const result = {physicalPresentations: universe.size, theoreticalNonSolvedCS: universe.size - 1,
  existingCSRows: cs.length, existingCSSetupPresentations: csKeys.size, intersection: csKeys.size,
  csOnly, cspOnly, existingCSIncludesSolved: csKeys.has(solved), invalidCS,
  duplicateCS: [...duplicateCS].filter(([,ids]) => ids.length > 1).map(([presentation,ids]) => ({presentation,ids})),
  unorderedLayerFamilies: new Set([...universe].map(k => k.split('|').sort().join('|'))).size,
  topBottomEquivalent, inversionEquivalent,
  inversionOrbits: new Set([...universe].map(k => [k,inversion(k)].sort()[0])).size,
  parityContexts: cases.length, solvedContexts: byPresentation.get(solved).length,
  referenceFormulas: cases.flatMap(c => c.algorithms).length,
  identityReferences: cases.filter(c => c.algorithms.length === 0).length,
  independentlyVerifiedPackedSetups: cases.length, fiveCornerThreeThreeFixtures: regression};
const artwork = require('./square-one-legacy-artwork.json');
const crypto = require('crypto');
result.legacyArtworkPresentations = new Set(artwork.map(a => a.shapeID)).size;
const artworkKeys = new Set(artwork.map(a => a.shapeID));
result.legacyArtworkSetupIntersection = [...artworkKeys].filter(k => csKeys.has(k)).length;
result.artworkOnlyVersusSetups = [...artworkKeys].filter(k => !csKeys.has(k));
result.setupsOnlyVersusArtwork = [...csKeys].filter(k => !artworkKeys.has(k));
result.cspOnlyVersusArtwork = [...universe].filter(k => !artworkKeys.has(k));
result.legacyArtworkSetupDiscrepancies = [];
for (const a of artwork) {
  const item = cs.find(c => c.id === a.id);
  assert(item);
  const asset = fs.readFileSync('CubeFlow/Resources/Algs/SQ1CSImages/' + item.imageKey + '.png');
  assert.equal(crypto.createHash('sha256').update(asset).digest('hex'), a.assetSHA256, 'Re-audit changed artwork');
  try {
    const actual = sh.presentation(m.apply(m.steps(item.setup || '')));
    if (actual !== a.shapeID) result.legacyArtworkSetupDiscrepancies.push({...a, actualSetupShape: actual});
  } catch (e) { result.legacyArtworkSetupDiscrepancies.push({...a, error: e.message}); }
}
if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify({...result, duplicateCS: result.duplicateCS.length,
  cspOnly: result.cspOnly.length, topBottomEquivalent: result.topBottomEquivalent.length,
  inversionEquivalent: result.inversionEquivalent.length, fiveCornerThreeThreeFixtures: regression.length,
  legacyArtworkSetupDiscrepancies: result.legacyArtworkSetupDiscrepancies.length}));
