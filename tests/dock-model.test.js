const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const model = {};
vm.createContext(model);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../shell/Dock/DockModel.js'), 'utf8'), model);
const entries = [
    {id: 'com.mitchellh.ghostty', name: 'Terminal', startupClass: 'ghostty'},
    {id: 'org.example.Editor', name: 'Editor', startupClass: ''},
    {id: 'webapp-one', name: 'One', startupClass: 'chrome-one-Default'},
    {id: 'webapp-two', name: 'Two', startupClass: 'chrome-two-Default'}
];
assert.equal(model.entryFor('ORG.EXAMPLE.EDITOR.desktop', entries), entries[1]);
assert.equal(model.entryFor('ghostty', entries), entries[0]);
assert.equal(model.entryFor('chrome-two-Default', entries), entries[3]);
assert.equal(model.entryFor('', entries), null);
assert.equal(model.entryFor('editor', entries.concat({id: 'net.other.Editor'})), null);
const windows = [
    {id: 1, app_id: 'ghostty'}, {id: 2, app_id: 'com.mitchellh.ghostty'},
    {id: 3, app_id: 'unknown'}, {id: 4, app_id: ''}, {id: 5, app_id: ''}
];
const groups = model.groups(entries, windows, ['org.example.Editor', 'org.example.Editor', 'missing']);
assert.equal(groups.length, 5);
assert.equal(groups[0].pinned, true);
assert.equal(groups[0].windows.length, 0);
assert.equal(groups[1].windows.length, 2);
assert.equal(groups[2].entry, null);
assert.notEqual(groups[3].key, groups[4].key);
assert.equal(model.groups(entries, [], null).length, 0);
console.log('Dock identity, ambiguous matching, pins, grouping and unknown windows: OK');
