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

// Detail projection is opt-in and never exposes message bodies, origins or credentials.
const clean = (value, limit = 160) => typeof value === 'string'
    ? value.replace(/[\x00-\x1f\x7f]/g, ' ').trim().slice(0, limit) : '';

export function sessionUrl(key, connection) {
    // Exact canonical routes, not title slugs; never trust a URL from session data.
    if (!/^agent:[a-zA-Z0-9_-]{1,64}:[a-zA-Z0-9_:-]{1,400}$/.test(key)) return '';
    const [, agent, ...parts] = key.split(':');
    if (parts.some(part => !part)) return '';
    const rest = parts.join(':');
    const route = rest === 'main' ? '' : '/' + (parts.length === 1 ? '~key/' : '') + parts.map(encodeURIComponent).join('/');
    const base = connection.uiBasePath || '';
    if (!/^(\/[a-zA-Z0-9_-]+)*$/.test(base)) return '';
    return connection.url.replace('ws:', 'http:') + base + '/chat/' + agent + route;
}

export function sessionDetails(rows, connection) {
    return rows.filter(row => !row.archived && !row.incognito && row.visibility !== 'hidden')
        .map(row => {
            const key = clean(row.key, 480);
            const url = sessionUrl(key, connection);
            const agent = key.split(':')[1] || clean(row.agentId, 64);
            // Only an explicit local execution directory is a project. Never guess
            // a repo from the gateway/agent's default workspace or a remote path.
            const project = row.execNode ? '' : clean(row.execCwd || row.spawnedCwd || row.spawnedWorkspaceDir, 1024);
            return {id: key, name: agent, title: clean(row.label || row.autoLabel || row.displayName) || 'OpenClaw · ' + agent,
                status: row.hasActiveRun ? 'working' : 'idle', project: project.startsWith('/') ? project : '',
                updatedAt: Number.isFinite(row.updatedAt) ? row.updatedAt : 0, backend: 'openclaw', url};
        }).filter(row => row.id && row.url)
        .sort((a, b) => Number(b.status === 'working') - Number(a.status === 'working') || b.updatedAt - a.updatedAt)
        .slice(0, 40);
}

export function progressSummary(card) {
    if (!Array.isArray(card?.steps) || card.steps.length > 50) return '';
    const steps = card.steps;
    const done = steps.filter(step => step.status === 'completed').length;
    const current = steps.find(step => step.status === 'in_progress');
    return steps.length ? `${done}/${steps.length} steps` + (current ? ' · ' + clean(current.step || current.text, 120) : '') : '';
}

export async function readConnection(stateDir, details = false) {
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
    return {url: `ws://127.0.0.1:${port}`, auth: {[mode]: secret},
        ...(details ? {uiBasePath: clean(gateway.controlUi?.basePath, 200).replace(/\/$/, '')} : {})};
}

export function query(connection, {WebSocketClass = WebSocket, timeoutMs = 1800, details = false} = {}) {
    return new Promise(resolve => {
        let ws, finished = false, connecting = false, offset = 0;
        const rows = [];
        let result = null;
        const progressPending = new Map();
        const done = result => {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            try { ws?.close(); } catch {}
            resolve(result);
        };
        const timer = setTimeout(() => done(result || unavailable('OpenClaw status timed out')), timeoutMs);
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
                    } else {
                        result = summarize(rows);
                        if (!details) { done(result); return; }
                        result.items = sessionDetails(rows, connection);
                        result.detailTotal = rows.filter(row => !row.archived && !row.incognito && row.visibility !== 'hidden').length;
                        // At most twelve progress reads, only on the visible Work page.
                        for (const [i, row] of result.items.slice(0, 12).entries()) {
                            const id = 'progress-' + i;
                            progressPending.set(id, row);
                            request(id, 'progressCard.get', {sessionKey: row.id});
                        }
                        if (!progressPending.size) done(result);
                    }
                } else if (msg.type === 'res' && progressPending.has(msg.id)) {
                    const row = progressPending.get(msg.id);
                    row.progress = msg.ok ? progressSummary(msg.payload?.card) : '';
                    progressPending.delete(msg.id);
                    if (!progressPending.size) done(result);
                }
            } catch { done(unavailable('Unsupported OpenClaw status')); }
        };
    });
}

export async function main(details = false) {
    try {
        const stateDir = process.env.OPENCLAW_STATE_DIR || path.join(os.homedir(), '.openclaw');
        const connection = await readConnection(stateDir, details);
        return connection ? await query(connection, {details}) : {installed: false, online: false, working: 0, sessions: 0, agents: [], error: ''};
    } catch { return unavailable('OpenClaw configuration unavailable'); }
}

const isMain = (() => {
    try { return !!process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href; }
    catch { return false; }
})();
if (isMain) {
    console.log(JSON.stringify(await main(process.argv.includes('--details'))));
    // Bound shutdown as well as the request when a peer does not finish closing.
    process.exit(0);
}
