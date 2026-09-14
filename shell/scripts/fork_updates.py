"""Shared, read-only upstream checks and revision-scoped review decisions.

No source checkout is changed. Decisions are a queue for a separately reviewed
integration, never an instruction to run an installer.
"""
import concurrent.futures
import contextlib
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.request

CATALOG = Path(__file__).resolve().parents[1] / 'Catalog/external-sources.json'
STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'nbshell/fork-updates'


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')


def read(path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.snapshot-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextlib.contextmanager
def lock(name, blocking=True):
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE / name).open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        yield


def sources():
    result = []
    for source in read(CATALOG, {})['sources']:
        source = dict(source)
        source['id'] = source.get('id') or re.sub(r'[^a-z0-9]+', '-', source['name'].lower()).strip('-')
        source['repository'] = source.get('upstreamRepository', source['repository']).rstrip('/').removesuffix('.git')
        source['base'] = source.get('upstreamBase', source['reviewedCommit'])
        result.append(source)
    if len({s['id'] for s in result}) != len(result):
        raise ValueError('Duplicate source IDs')
    return result


def identity(source):
    return (source['id'], source['repository'], source['base'])


def token(row):
    return hashlib.sha256(json.dumps([*identity(row), row['head']], separators=(',', ':')).encode()).hexdigest()


def api(repository, suffix):
    match = re.fullmatch(r'https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)', repository)
    if not match:
        raise ValueError('Only official HTTPS GitHub repository URLs are supported')
    request = urllib.request.Request('https://api.github.com/repos/' + match[1] + suffix,
        headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'nbshell-fork-review'})
    with urllib.request.urlopen(request, timeout=12) as response:
        raw = response.read(2_000_001)
        if len(raw) > 2_000_000:
            raise ValueError('Upstream response exceeds size limit')
        return json.loads(raw)


def check(source):
    row = {key: source[key] for key in ('id', 'name', 'repository', 'base')}
    row.update(head='', status='error', error='', changes=[], checkedAt=now(), comparisonUrl='', decision='pending', scope=source.get('scope', 'component'))
    try:
        head = api(row['repository'], '/commits/HEAD')['sha']
        if not re.fullmatch('[0-9a-f]{40}', head):
            raise ValueError('Invalid upstream revision')
        row['head'] = head
        if not re.fullmatch('[0-9a-f]{7,40}', row['base']):
            raise ValueError('Unknown upstream baseline')
        row['comparisonUrl'] = row['repository'] + '/compare/' + row['base'] + '...' + head
        if head.startswith(row['base']):
            row['status'] = 'current'
        else:
            comparison = api(row['repository'], '/compare/' + row['base'] + '...' + head + '?per_page=20')
            row['relation'] = comparison.get('status', 'unknown')
            row['totalCommits'] = comparison.get('total_commits', 0)
            row['changes'] = [str(c.get('commit', {}).get('message', '')).split('\n')[0][:300] for c in comparison.get('commits', [])[:20]]
            row['status'] = 'review' if row['relation'] == 'ahead' else 'diverged'
        row['token'] = token(row)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        row['error'] = 'Upstream check failed: ' + str(exc)[:240]
    return row


def _snapshot():
    catalog = sources()
    stored = read(STATE / 'snapshot.json', {'sources': [], 'checkedAt': ''})
    indexed = {r['id']: r for r in stored['sources']}
    decisions = read(STATE / 'decisions.json', {})
    rows = []
    for source in catalog:
        row = indexed.get(source['id'])
        if not row or identity(row) != identity(source):
            row = {key: source[key] for key in ('id', 'name', 'repository', 'base')}
            row.update(status='unchecked', head='', token='', changes=[], error='', checkedAt='', scope=source.get('scope', 'component'))
        row = dict(row)
        row['scope'] = source.get('scope', 'component')
        decision = decisions.get(row['id'], {})
        row['decision'] = decision.get('decision', 'pending') if decision.get('token') == row.get('token') else 'pending'
        rows.append(row)
    return {'schemaVersion': 1, 'checkedAt': stored.get('checkedAt', ''), 'sources': rows}


def snapshot():
    with lock('state.lock'):
        # Create watchable files before the UI attaches its filesystem watchers.
        if not (STATE / 'snapshot.json').exists():
            write(STATE / 'snapshot.json', {'checkedAt': '', 'sources': []})
        if not (STATE / 'decisions.json').exists():
            write(STATE / 'decisions.json', {})
        return _snapshot()


def refresh(notify=False):
    # Keep manual and timer refreshes from racing; do not hold the decision
    # lock during the network calls, so decisions stay responsive.
    with lock('refresh.lock', blocking=False):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            rows = list(pool.map(check, sources()))
        with lock('state.lock'):
            previous_rows = {r['id']: r for r in read(STATE / 'snapshot.json', {'sources': []})['sources']}
            for index, row in enumerate(rows):
                old = previous_rows.get(row['id'])
                if row['status'] == 'error' and old and identity(old) == identity(row) and old.get('token'):
                    # Preserve the last successfully checked target and its decision
                    # while explicitly disabling new approvals during the outage.
                    rows[index] = dict(old, status='error', error=row['error'], checkedAt=row['checkedAt'],
                                       stale=True, lastSuccessAt=old.get('lastSuccessAt', old['checkedAt']))
                elif row['status'] != 'error':
                    row['stale'] = False
                    row['lastSuccessAt'] = row['checkedAt']
            decisions = read(STATE / 'decisions.json', {})
            valid = {r['id']: r for r in rows}
            # A newer successful check permanently invalidates the old decision;
            # a later force-push back to the old SHA must not revive approval.
            decisions = {key: value for key, value in decisions.items()
                         if key in valid and (valid[key]['status'] == 'error'
                         or value.get('token') == valid[key].get('token'))}
            write(STATE / 'decisions.json', decisions)
            write(STATE / 'snapshot.json', {'checkedAt': now(), 'sources': rows})
            data = _snapshot()
            signals = {r['id']: (r.get('token', '') + ':' + r['status'])
                       for r in data['sources'] if r['status'] == 'error'
                       or (r['status'] in ('review', 'diverged') and r['decision'] == 'pending')}
            previous = read(STATE / 'notified.json', {})
        if notify and signals != previous:
            import subprocess
            names = [r['name'] for r in rows if r['id'] in signals and signals[r['id']] != previous.get(r['id'])]
            if names:
                try:
                    sent = subprocess.run(['notify-send', 'Fork review', 'Open Updates → Fork: ' + ', '.join(names)], check=False).returncode == 0
                except OSError:
                    sent = False
                if sent:
                    write(STATE / 'notified.json', signals)
            else:
                write(STATE / 'notified.json', signals)
        return data


def decide(source_id, expected_token, decision):
    if decision not in ('approved', 'deferred', 'pending'):
        raise ValueError('Unknown decision')
    with lock('state.lock'):
        rows = _snapshot()['sources']
        row = next((r for r in rows if r['id'] == source_id), None)
        if not row or not expected_token or row.get('token') != expected_token:
            raise ValueError('Source changed; refresh and review the new revision first')
        if (row['status'] not in ('review', 'diverged') and decision != 'pending') or row.get('scope') == 'reference':
            raise ValueError('This source is not eligible for an integration decision')
        decisions = read(STATE / 'decisions.json', {})
        decisions[source_id] = {'token': expected_token, 'decision': decision, 'at': now(),
            'base': row['base'], 'head': row['head'], 'repository': row['repository']}
        write(STATE / 'decisions.json', decisions)
        return _snapshot()
