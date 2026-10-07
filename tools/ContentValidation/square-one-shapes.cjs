// Physical presentation identity: independent cyclic layer alignment, never layer sorting or reflection.
const m = require('./square-one-model.cjs');
const bits = a => a.map((v, i) => +(v !== a[(i + 11) % 12])).join('');
const cycle = b => Array.from({length: 12}, (_, r) => b.slice(r) + b.slice(0, r)).sort()[0];
const presentation = s => cycle(bits(s.top)) + '|' + cycle(bits(s.bottom));
const pieces = s => [s.top, s.bottom].flatMap(a => a.filter((v, i) => v !== a[(i + 11) % 12]));
function parity(s, ref = m.solved()) {
  const goal = pieces(ref), p = pieces(s).map(v => goal.indexOf(v));
  let n = 0;
  for (let i = 0; i < p.length; i++) for (let j = i + 1; j < p.length; j++) n ^= +(p[i] > p[j]);
  return n;
}
const pattern = a => a.filter((v, i) => v !== a[(i + 11) % 12]).map(v => v % 2 ? 'C' : 'E').join('');
function universe() {
  const rings = [];
  for (let n = 0; n < 4096; n++) {
    const b = n.toString(2).padStart(12, '0');
    if (!(b + b[0]).includes('00')) rings.push(b);
  }
  const result = new Set();
  for (const a of rings) for (const b of rings) {
    if ([...a + b].filter(x => x === '0').length === 8) result.add(cycle(a) + '|' + cycle(b));
  }
  return result;
}
function graph() {
  const key = s => bits(s.top) + '|' + bits(s.bottom) + '|' + parity(s);
  const queue = [{state: m.solved(), sequence: []}], seen = new Set([key(m.solved())]);
  for (let i = 0; i < queue.length; i++) {
    const {state, sequence} = queue[i];
    for (let a = -5; a <= 6; a++) for (let b = -5; b <= 6; b++) {
      let next;
      try { next = m.apply([[a, b], '/'], structuredClone(state)); } catch { continue; }
      const id = key(next); if (seen.has(id)) continue;
      seen.add(id); queue.push({state: next, sequence: sequence.concat([[a, b], '/'])});
    }
  }
  return queue;
}
module.exports = {bits, cycle, presentation, pieces, parity, pattern, universe, graph};
