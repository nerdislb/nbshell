import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {summarize, readConnection, query} from '../shell/scripts/openclaw-monitor.mjs';

test('symlinked entry point emits status without configured OpenClaw', () => {
    const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'openclaw-symlink-'));
    try {
        const link = path.join(folder, 'monitor.mjs');
        fs.symlinkSync(fileURLToPath(new URL('../shell/scripts/openclaw-monitor.mjs', import.meta.url)), link);
        const result = spawnSync(process.execPath, [link], {
            env: {...process.env, OPENCLAW_STATE_DIR: folder}, encoding: 'utf8', timeout: 3000,
        });
        assert.equal(result.status, 0);
        assert.equal(JSON.parse(result.stdout).installed, false);
    } finally { fs.rmSync(folder, {recursive: true, force: true}); }
});

test('live run flags take precedence over stale persisted status and private fields are discarded', () => {
    const result = summarize([
        {agentId: 'main', hasActiveRun: false, status: 'running', title: 'PRIVATE', model: 'PRIVATE'},
        {agentId: 'worker', hasActiveRun: true, status: 'done', lastMessage: 'PRIVATE'},
        {agentId: 'worker', hasActiveRun: true},
    ]);
    assert.equal(result.working, 2);
    assert.equal(result.sessions, 3);
    assert.deepEqual(result.agents, ['main', 'worker']);
    assert.ok(!JSON.stringify(result).includes('PRIVATE'));
    assert.throws(() => summarize([{status: 'running'}]));
    assert.equal(summarize([]).working, 0);
});

test('only a local configured credential is resolved, including the built-in SecretRef store', async () => {
    const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'nbshell-openclaw-'));
    const config = value => fs.writeFileSync(path.join(folder, 'openclaw.json'), JSON.stringify(value));
    try {
        assert.equal(await readConnection(folder), null);
        config({gateway: {mode: 'remote', auth: {token: 'fixture'}}});
        await assert.rejects(readConnection(folder));
        config({gateway: {tls: {enabled: true}, auth: {token: 'fixture'}}});
        await assert.rejects(readConnection(folder));
        config({gateway: {auth: {token: '${PRIVATE_TOKEN}'}}});
        await assert.rejects(readConnection(folder));
        config({gateway: {port: 12345, auth: {token: 'fixture'}}});
        assert.deepEqual(await readConnection(folder), {url: 'ws://127.0.0.1:12345', auth: {token: 'fixture'}});
        config({gateway: {auth: {token: {source: 'exec', provider: 'default', id: 'anything'}}}});
        await assert.rejects(readConnection(folder));
        const {DatabaseSync} = await import('node:sqlite');
        fs.mkdirSync(path.join(folder, 'state'));
        const db = new DatabaseSync(path.join(folder, 'state/openclaw.sqlite'));
        db.exec("CREATE TABLE secret_store_entries (scope_kind, scope_id, name, value, kind, deleted_at_ms)");
        db.prepare('INSERT INTO secret_store_entries VALUES (?, ?, ?, ?, ?, ?)').run('team', '', 'TEST_TOKEN', 'fixture', 'secret', null);
        db.close();
        config({gateway: {auth: {token: {source: 'store', provider: 'default', id: 'TEST_TOKEN'}}}});
        assert.deepEqual((await readConnection(folder)).auth, {token: 'fixture'});
    } finally { fs.rmSync(folder, {recursive: true, force: true}); }
});

function peer(responses, inspect = () => {}) {
    return class {
        constructor(url) {
            assert.equal(url, 'ws://127.0.0.1:18789');
            queueMicrotask(() => this.onmessage({data: JSON.stringify({event: 'connect.challenge'})}));
        }
        send(data) {
            const request = JSON.parse(data);
            inspect(request);
            const response = responses.shift();
            if (response) queueMicrotask(() => this.onmessage({data: JSON.stringify({type: 'res', id: request.id, ...response})}));
        }
        close() { this.onclose?.(); }
    };
}
const connection = {url: 'ws://127.0.0.1:18789', auth: {token: 'fixture'}};

test('read-only protocol handshake and paginated sessions', async () => {
    const requests = [];
    const result = await query(connection, {WebSocketClass: peer([
        {ok: true},
        {ok: true, payload: {sessions: [{agentId: 'main', hasActiveRun: true}], hasMore: true, nextOffset: 1}},
        {ok: true, payload: {sessions: [{agentId: 'main', hasActiveRun: false}], hasMore: false}},
    ], r => requests.push(r))});
    assert.equal(result.working, 1);
    assert.equal(result.sessions, 2);
    assert.deepEqual(requests.map(r => r.method), ['connect', 'sessions.list', 'sessions.list']);
    assert.deepEqual(requests[0].params.scopes, ['operator.read']);
    assert.equal(requests[1].params.includeLastMessage, false);
    assert.equal(requests[2].params.offset, 1);
});

test('auth failure, malformed data, stalled peer and invalid pagination never report idle success', async () => {
    for (const responses of [
        [{ok: false, error: {message: 'PRIVATE'}}],
        [{ok: true}, {ok: true, payload: {sessions: [{status: 'running'}]}}],
        [{ok: true}, {ok: true, payload: {sessions: [{hasActiveRun: false}]}}],
        [{ok: true}, {ok: true, payload: {sessions: [], hasMore: true, nextOffset: 0}}],
        [],
    ]) {
        const result = await query(connection, {WebSocketClass: peer(responses), timeoutMs: 15});
        assert.equal(result.online, false);
        assert.equal(result.working, 0);
        assert.ok(!JSON.stringify(result).includes('PRIVATE'));
    }
});
