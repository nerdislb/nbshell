// TZ=Europe/Vienna node tests/test-dates.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../Dates.js'), 'utf8').replace(/^\.pragma library\s*/, '');
const context = vm.createContext({ Date, Error });
vm.runInContext(source, context);
assert.equal(context.fromEditor('2026-09-11', '13:45', false), '2026-09-11T13:45:00+02:00');
assert.equal(context.fromEditor('2026-12-11', '13:45', false), '2026-12-11T13:45:00+01:00');
assert.equal(context.fromEditor('2026-09-11', '', true), '2026-09-11');
assert.equal(context.fromEditor('2026-12-31', '', true, true), '2027-01-01');
assert.equal(context.editorParts('2027-01-01', true, true)[0], '2026-12-31');
assert.equal(context.editorParts('2026-09-11T11:45:28Z', false)[1], '13:45');
assert.throws(() => context.fromEditor('2026-02-30', '10:00', false));
assert.throws(() => context.fromEditor('2026-09-11', '24:00', false));
assert.throws(() => context.fromEditor('2026-09-11', '12:60', false));
assert.throws(() => context.fromEditor('2026-03-29', '02:30', false), /clocks change/);
console.log('Date editor: 10 checks passed');
