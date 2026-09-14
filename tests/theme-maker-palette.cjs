// Pure color math used by the native editor; keep hue round trips stable.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const palette = {};
vm.createContext(palette);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../shell/ThemeMaker/Palette.js'), 'utf8').replace('.pragma library', ''), palette);
for (const color of ['#000000', '#ffffff', '#ff0000', '#11aacc', '#777777', '#aabbcc']) {
    assert.equal(palette.fromHsl(...palette.hsl(color)), color);
}
assert.equal(palette.fromHsl(360, 100, 50), '#ff0000');
assert.equal(palette.mix('#000000', '#ffffff', 0.5), '#808080');
assert.equal(palette.localUrl('/tmp/a #b.png'), 'file:///tmp/a%20%23b.png');
console.log('Theme Maker color math: OK');

// Execute the production exporter with observable sinks: a desktop preview
// must never write files or schedule external hooks, even when export is on.
const exporter = fs.readFileSync(path.join(__dirname, '../shell/Services/ThemeExport.qml'), 'utf8');
const exportBody = exporter.match(/function exportNow\(\) \{([\s\S]*?)\n    \}/)[1];
const effects = [];
const sink = {setText: () => effects.push('write'), restart: () => effects.push('timer')};
const context = {
    Theme: {desktopPreview: true, sourceEnabled: true, c: {a:1,b:2,c:3,d:4,e:5}},
    Object, enabled: true, Config: {theme: 'saved'}, root: {hookPath: '/unused'}, hook: {},
    umbrielMotionFile: sink, umbrielReloadTimer: sink, umbrielOverviewFile: sink,
    ghostty: sink, umbriel: sink, palette: sink, reloadTimer: sink,
    umbrielMotion: () => '', umbrielOverview: () => '', ghosttyTheme: () => '',
    umbrielColors: () => '', paletteShell: () => ''
};
vm.createContext(context);
vm.runInContext('function exportNow() {' + exportBody + '\n}', context);
context.exportNow();
assert.deepEqual(effects, []);
context.Theme.desktopPreview = false;
context.Theme.sourceEnabled = false;
context.exportNow();
assert.deepEqual(effects, []);
context.Theme.sourceEnabled = true;
context.exportNow();
assert.ok(effects.includes('write') && effects.includes('timer'));
console.log('Theme Maker export isolation: OK');
