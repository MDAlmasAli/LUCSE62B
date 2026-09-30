// Run from the repository root:  node worker/section_monitor_test.mjs
//
// Exercises the per-section monitor helpers against the real worker source.
// worker.js is an ES module, so it is copied to a .mjs with the helpers
// exported rather than being re-implemented here.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const src = fs.readFileSync('worker/worker.js', 'utf8');
const tmp = path.join(os.tmpdir(), 'worker_under_test.mjs');
fs.writeFileSync(
  tmp,
  src + '\nexport { monitoredSections, parseSectionSlots, specialAccessRows, DEFAULT_BATCH, DEFAULT_SECTION };\n',
);
const w = await import('file://' + tmp.replace(/\\/g, '/'));

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    console.log('  ok   ' + label);
  } else {
    failures++;
    console.log('  FAIL ' + label + '\n       got      ' + a + '\n       expected ' + e);
  }
}

// A routine day tab shaped like the real sheet: col 1 batch, col 2 section,
// columns 3+ the time slots.
const cell = v => ({ v });
const dayTab = {
  cols: [{ label: '' }, { label: '' }, { label: '' }, { label: '09:00' }, { label: '10:30' }],
  rows: [
    { c: [cell(''), cell('62'), cell('B'), cell('CSE-4116 ABC 501'), cell('BREAK')] },
    { c: [cell(''), cell('62'), cell('C'), cell('CSE-4117 XYZ 402'), cell('')] },
    { c: [cell(''), cell('61'), cell('A'), cell('CSE-3101 QQQ 101'), cell('')] },
  ],
};

console.log('parseSectionSlots');
check('defaults to 62 B',
  w.parseSectionSlots(dayTab, 'SATURDAY').map(s => s.code), ['CSE-4116']);
check('reads another section',
  w.parseSectionSlots(dayTab, 'SATURDAY', '62', 'C').map(s => s.code), ['CSE-4117']);
check('reads another batch',
  w.parseSectionSlots(dayTab, 'SATURDAY', '61', 'A').map(s => s.code), ['CSE-3101']);
check('a section nobody is in yields nothing',
  w.parseSectionSlots(dayTab, 'SATURDAY', '62', 'Z'), []);
check('section match is case insensitive',
  w.parseSectionSlots(dayTab, 'SATURDAY', '62', 'c').map(s => s.code), ['CSE-4117']);
check('room and teacher survive',
  w.parseSectionSlots(dayTab, 'SATURDAY', '62', 'C')[0],
  { day: 'SATURDAY', time: '09:00', code: 'CSE-4117', teacher: 'XYZ', room: '402' });

// ── monitoredSections, with the Special Access tab stubbed ─────────────────
function stubSheet(rows) {
  globalThis.fetch = async () => ({
    ok: true,
    text: async () =>
      'setResponse(' + JSON.stringify({
        table: { rows: rows.map(r => ({ c: r.map(v => ({ v })) })) },
      }) + ');',
  });
}
const env = { MAIN_SHEET_ID: 'sheet' };
const header = ['Name', 'ID', 'Mobile', 'Batch', 'Section'];

console.log('monitoredSections');
stubSheet([header]);
check('with no guests it is just the class',
  await w.monitoredSections(env),
  [{ batch: '62', section: 'B', students: null }]);

stubSheet([header, ['Kolsuma', '0182320012101108', '017', '62', 'C']]);
check('one guest adds their section',
  await w.monitoredSections(env),
  [{ batch: '62', section: 'B', students: null },
   { batch: '62', section: 'C', students: ['0182320012101108'] }]);

stubSheet([header,
  ['A', '0182320012101108', '017', '62', 'C'],
  ['B', '0182320012101109', '017', '62', 'C'],
  ['C', '0182320012101110', '017', '61', 'A']]);
check('two in one section are grouped, a third section is its own',
  await w.monitoredSections(env),
  [{ batch: '62', section: 'B', students: null },
   { batch: '62', section: 'C', students: ['0182320012101108', '0182320012101109'] },
   { batch: '61', section: 'A', students: ['0182320012101110'] }]);

stubSheet([header, ['Someone', '0182320012101111', '017', '62', 'B']]);
check('a guest row that is 62 B does not duplicate the class',
  await w.monitoredSections(env),
  [{ batch: '62', section: 'B', students: null }]);

stubSheet([header, ['Sloppy', '0182320012101112', '017', '62.0', ' c ']]);
check('a sloppy batch/section cell is normalised',
  await w.monitoredSections(env),
  [{ batch: '62', section: 'B', students: null },
   { batch: '62', section: 'C', students: ['0182320012101112'] }]);

// A tab GVIZ cannot find silently returns the FIRST sheet; the header check
// must reject that rather than treat Student Info rows as guests.
stubSheet([['Serial', 'ID', 'Name', 'Phone'], ['1', '0182320012101068', 'Almas', '017']]);
check('a wrong tab (no Batch/Section header) is ignored',
  await w.monitoredSections(env),
  [{ batch: '62', section: 'B', students: null }]);

globalThis.fetch = async () => { throw new Error('offline'); };
check('an unreachable sheet still monitors the class',
  await w.monitoredSections(env),
  [{ batch: '62', section: 'B', students: null }]);

fs.unlinkSync(tmp);
console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
