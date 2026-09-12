// Read-only local OpenClaw protocol v4 monitor. No SDK, daemon or transcript reads.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { pathToFileURL } from 'node:url';

const unavailable = (message) => ({installed: true, online: false, working: 0, sessions: 0, agents: [], error: message});

export function summarize(sessions) {
    if (!Array.isArray(sessions) || sessions.some(s => !s || typeof s.hasActiveRun !== 'boolean'))
        throw new Error('Unsupported OpenClaw session status');
    const agents = new Set();
    for (const row of sessions) {
        if (typeof row.agentId === 'string' && /^[a-zA-Z0-9_-]{1,64}$/.test(row.agentId)) agents.add(row.agentId);
    }
    return {installed: true, online: true, working: sessions.filter(s => s.hasActiveRun).length,
        sessions: sessions.length, agents: [...agents].sort().slice(0, 8), error: ''};
}

export async function readConnection(stateDir) {
    const file = path.join(stateDir, 'openclaw.json');
    if (!fs.existsSync(file)) return null;
    if (fs.statSync(file).size > 1024 * 1024) throw new Error('OpenClaw config too large');
    const config = JSON.parse(fs.readFileSync(file, 'utf8'));
    const gateway = config.gateway ?? {};
    if (gateway.mode && gateway.mode !== 'local') throw new Error('Only local OpenClaw is supported');
    if (gateway.tls?.enabled) throw new Error('OpenClaw TLS is not supported by this local monitor');
    const port = gateway.port ?? 18789;
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid OpenClaw port');
    const mode = gateway.auth?.mode ?? 'token';
    if (!['token', 'password'].includes(mode)) throw new Error('Unsupported OpenClaw authentication');
    let secret = gateway.auth?.[mode];
    if (secret && typeof secret === 'object') {
        // Only the built-in team store is read. Never execute arbitrary SecretRefs.
        if (secret.source !== 'store' || secret.provider !== 'default' || typeof secret.id !== 'string')
            throw new Error('Unsupported OpenClaw secret reference');
        const { DatabaseSync } = await import('node:sqlite');
        const db = new DatabaseSync(path.join(stateDir, 'state', 'openclaw.sqlite'), {readOnly: true});
        try {
            secret = db.prepare("SELECT value FROM secret_store_entries WHERE scope_kind='team' AND scope_id='' AND name=? AND kind='secret' AND deleted_at_ms IS NULL").get(secret.id)?.value;
        } finally { db.close(); }
    }
    if (typeof secret !== 'string' || !secret || secret.length > 16384)
        throw new Error('OpenClaw authentication unavailable');
    if (secret.includes('${')) throw new Error('Unsupported OpenClaw secret placeholder');
    // Never use remote URLs or configurable hosts for a local credential.
    return {url: `ws://127.0.0.1:${port}`, auth: {[mode]: secret}};
}

export function query(connection, {WebSocketClass = WebSocket, timeoutMs = 1800} = {}) {
    return new Promise(resolve => {
        let ws, finished = false, connecting = false, offset = 0;
        const rows = [];
        const done = result => {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            try { ws?.close(); } catch {}
            resolve(result);
        };
        const timer = setTimeout(() => done(unavailable('OpenClaw status timed out')), timeoutMs);
        const request = (id, method, params) => ws.send(JSON.stringify({type: 'req', id, method, params}));
        const list = () => request('sessions', 'sessions.list', {includeDerivedTitles: false,
            includeLastMessage: false, limit: 100, offset});
        try { ws = new WebSocketClass(connection.url); }
        catch { done(unavailable('OpenClaw is offline')); return; }
        ws.onerror = () => done(unavailable('OpenClaw is offline'));
        ws.onclose = () => done(unavailable('OpenClaw connection closed'));
        ws.onmessage = ({data}) => {
            if (finished) return;
            try {
                if (typeof data !== 'string') throw new Error();
                // Ignore oversized unsolicited events; an oversized response times out.
                if (data.length > 2 * 1024 * 1024) return;
                const msg = JSON.parse(data);
                if (msg.event === 'connect.challenge' && !connecting) {
                    connecting = true;
                    request('connect', 'connect', {minProtocol: 4, maxProtocol: 4,
                        client: {id: 'cli', displayName: 'nbshell monitor', version: '1', platform: 'linux', mode: 'cli'},
                        role: 'operator', scopes: ['operator.read'], auth: connection.auth});
                } else if (msg.type === 'res' && msg.id === 'connect') {
                    if (!msg.ok) { done(unavailable('OpenClaw connection unavailable')); return; }
                    list();
                } else if (msg.type === 'res' && msg.id === 'sessions') {
                    if (!msg.ok || !Array.isArray(msg.payload?.sessions) || typeof msg.payload.hasMore !== 'boolean') throw new Error();
                    rows.push(...msg.payload.sessions);
                    if (rows.length > 1000) throw new Error();
                    if (msg.payload.hasMore === true) {
                        const next = msg.payload.nextOffset;
                        if (!Number.isInteger(next) || next <= offset || next > 1000) throw new Error();
                        offset = next;
                        list();
                    } else done(summarize(rows));
                }
            } catch { done(unavailable('Unsupported OpenClaw status')); }
        };
    });
}

export async function main() {
    try {
        const stateDir = process.env.OPENCLAW_STATE_DIR || path.join(os.homedir(), '.openclaw');
        const connection = await readConnection(stateDir);
        return connection ? await query(connection) : {installed: false, online: false, working: 0, sessions: 0, agents: [], error: ''};
    } catch { return unavailable('OpenClaw configuration unavailable'); }
}

const isMain = (() => {
    try { return !!process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href; }
    catch { return false; }
})();
if (isMain) {
    console.log(JSON.stringify(await main()));
    // Bound shutdown as well as the request when a peer does not finish closing.
    process.exit(0);
}
