#!/usr/bin/env python3
"""One JSON request on stdin, one sanitized JSON reply. No shell or mail state."""
import base64
import datetime as dt
import hashlib
import http.server
import json
import logging
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
from urllib.parse import urljoin, urlsplit, urlencode, parse_qs, quote, unquote
import uuid
import xml.etree.ElementTree as ET

UTC = dt.timezone.utc
SCOPES = ['https://www.googleapis.com/auth/calendar.events',
          'https://www.googleapis.com/auth/calendar.calendarlist.readonly']
GOOGLE = 'https://www.googleapis.com/calendar/v3/'
TOKEN = 'https://oauth2.googleapis.com/token'
D = '{DAV:}'
C = '{urn:ietf:params:xml:ns:caldav}'

class Failure(Exception):
    pass


def require(condition, message):
    if not condition:
        raise Failure(message)


def apple_url(url, base=None):
    url = urljoin(base, url) if base else url
    p = urlsplit(url)
    require(p.scheme == 'https' and p.port in (None, 443) and not p.username
            and not p.password and not p.query and not p.fragment
            and (p.hostname == 'caldav.icloud.com' or
                 re.fullmatch(r'p\d+-caldav\.icloud\.com', p.hostname or ''))
            and not re.search(r'[\x00-\x20\\]', url), 'Untrusted iCloud address refused.')
    require(not any(x in ('.', '..') for x in unquote(p.path).split('/')),
            'Unsafe calendar path refused.')
    return url


def member_url(url, calendar):
    url = apple_url(url, calendar)
    p, c = urlsplit(url), urlsplit(calendar)
    require(p.netloc == c.netloc and p.path.startswith(c.path.rstrip('/') + '/')
            and '/' not in unquote(p.path[len(c.path.rstrip('/')) + 1:]),
            'Event address is outside its calendar.')
    return url


def request(method, url, **kwargs):
    import requests
    session = requests.Session()
    session.trust_env = False  # no netrc, ambient credentials, or proxy forwarding
    try:
        response = session.request(method, url, timeout=(10, 40), allow_redirects=False, **kwargs)
    except requests.RequestException:
        raise Failure('Network unavailable or request outcome unknown. Refresh before retrying writes.') from None
    finally:
        session.close()
    require(response.status_code not in (409, 412), 'Conflict: the event changed remotely. Refresh and reopen it.')
    require(response.status_code not in (401, 403), 'Access denied. Reconnect the account or check calendar permissions.')
    require(200 <= response.status_code < 300, 'Provider request failed (HTTP %s). Refresh before retrying.' % response.status_code)
    require(len(response.content) <= 16 * 1024 * 1024, 'Provider response is too large.')
    return response


class Keyring:
    def run(self, action, account, value=None):
        command = ['secret-tool', action]
        if action == 'store':
            command += ['--label=nbshell Calendar account']
        command += ['application', 'io.github.nbshell.calendar', 'account', account]
        try:
            result = subprocess.run(command, input=value, text=True, capture_output=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            raise Failure('Desktop Secret Service is unavailable. Install secret-tool and unlock your keyring.') from None
        require(result.returncode == 0, 'Desktop Secret Service could not access this account. Unlock the keyring or reconnect.')
        return result.stdout

    def get(self, account):
        return json.loads(self.run('lookup', account))

    def put(self, account, value):
        self.run('store', account, json.dumps(value))

    def delete(self, account):
        self.run('clear', account)


class Store:
    def __init__(self, path):
        self.path = Path(path)
        self.path.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.file = self.path / 'accounts.json'
        self.data = json.loads(self.file.read_text()) if self.file.exists() else {'version': 1, 'accounts': [], 'hidden': []}
        require(self.data.get('version') == 1, 'Unsupported account store version.')

    def save(self):
        temp = self.path / ('accounts-' + uuid.uuid4().hex + '.tmp')
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            json.dump(self.data, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, self.file)


def xml(body):
    require(b'<!DOCTYPE' not in body.upper() and b'<!ENTITY' not in body.upper(), 'Unsafe XML refused.')
    return ET.fromstring(body)


def properties(response):
    for propstat in response.findall(D + 'propstat'):
        if ' 200 ' in propstat.findtext(D + 'status', ''):
            yield propstat.find(D + 'prop')


class Apple:
    def __init__(self, account, secret):
        self.account = account
        self.auth = (account['username'], secret['password'])

    def call(self, method, url, body=None, headers=None):
        return request(method, apple_url(url), auth=self.auth, data=body,
                       headers=headers or {'Content-Type': 'application/xml; charset=utf-8', 'Depth': '0'})

    def prop(self, url, tags, depth='0'):
        body = ('<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>'
                + tags + '</d:prop></d:propfind>').encode()
        return xml(self.call('PROPFIND', url, body, {'Depth': depth, 'Content-Type': 'application/xml'}).content)

    def discover(self):
        start = 'https://caldav.icloud.com/'
        principal = self.prop(start, '<d:current-user-principal/>').find('.//' + D + 'current-user-principal/' + D + 'href')
        require(principal is not None, 'iCloud did not return a calendar principal.')
        principal_url = apple_url(principal.text, start)
        home = self.prop(principal_url, '<c:calendar-home-set/>').find('.//' + C + 'calendar-home-set/' + D + 'href')
        require(home is not None, 'iCloud did not return a calendar home.')
        home_url = apple_url(home.text, principal_url)
        tree = self.prop(home_url, '<d:resourcetype/><d:displayname/><d:current-user-privilege-set/><c:supported-calendar-component-set/>', '1')
        result = []
        for response in tree.findall(D + 'response'):
            for prop in properties(response):
                if prop.find('.//' + C + 'calendar') is None:
                    continue
                components = prop.findall('.//' + C + 'comp')
                if components and not any(c.get('name') == 'VEVENT' for c in components):
                    continue
                url = apple_url(response.findtext(D + 'href', ''), home_url)
                privileges = prop.find(D + 'current-user-privilege-set')
                names = {child.tag for child in privileges.iter()} if privileges is not None else set()
                result.append({'id': url, 'name': prop.findtext(D + 'displayname', 'Calendar'),
                               'writable': D + 'write' in names or D + 'all' in names or
                               all(D + p in names for p in ['write-content', 'bind', 'unbind'])})
        return result

    def events(self, calendar, start, end):
        body = ('<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
                '<d:prop><d:getetag/><c:calendar-data/></d:prop><c:filter><c:comp-filter name="VCALENDAR">'
                '<c:comp-filter name="VEVENT"><c:time-range start="%s" end="%s"/>'
                '</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>' %
                (start.strftime('%Y%m%dT%H%M%SZ'), end.strftime('%Y%m%dT%H%M%SZ'))).encode()
        tree = xml(self.call('REPORT', calendar['id'], body, {'Depth': '1', 'Content-Type': 'application/xml'}).content)
        events = []
        for response in tree.findall(D + 'response'):
            href = member_url(response.findtext(D + 'href', ''), calendar['id'])
            for prop in properties(response):
                raw = prop.findtext(C + 'calendar-data')
                if raw:
                    events += expand_ics(raw, href, prop.findtext(D + 'getetag', ''), start, end)
        return events

    def write(self, calendar, operation, event, draft):
        import icalendar
        if operation == 'create':
            target = member_url(uuid.uuid4().hex + '.ics', calendar['id'].rstrip('/') + '/')
            doc = icalendar.Calendar()
            doc.add('version', '2.0')
            doc.add('prodid', '-//nbshell//Calendar//EN')
            component = icalendar.Event()
            component.add('uid', str(uuid.uuid4()))
            component.add('dtstamp', dt.datetime.now(UTC))
            doc.add_component(component)
            headers = {'If-None-Match': '*'}
        else:
            target = member_url(event['id'], calendar['id'])
            require(str(event.get('etag', '')).startswith('"'), 'A strong ETag is required. Refresh first.')
            current = self.call('GET', target)
            require(current.headers.get('ETag') == event['etag'], 'Conflict: refresh and reopen this event.')
            doc = icalendar.Calendar.from_ical(current.content)
            components = doc.walk('VEVENT')
            require(len(components) == 1 and not unsafe_ics(components[0]), 'Recurring or scheduled meetings must be changed in the provider app.')
            component = components[0]
            headers = {'If-Match': event['etag']}
        if operation == 'delete':
            self.call('DELETE', target, headers=headers)
            return
        values = validate_draft(draft)
        for key, value in [('summary', values['title']), ('dtstart', values['start']), ('dtend', values['end'])]:
            if key in component:
                del component[key]
            component.add(key, value)
        if 'duration' in component:
            del component['duration']
        component['SEQUENCE'] = int(component.get('SEQUENCE', 0)) + 1
        component['DTSTAMP'] = icalendar.vDDDTypes(dt.datetime.now(UTC))
        headers['Content-Type'] = 'text/calendar; charset=utf-8'
        self.call('PUT', target, doc.to_ical(), headers)


def unsafe_ics(event):
    return any(key in event for key in ['RRULE', 'RDATE', 'EXDATE', 'RECURRENCE-ID', 'ORGANIZER', 'ATTENDEE'])


def expand_ics(raw, href, etag, start, end):
    # khal owns recurrence, exclusions, overrides, DST and THISANDFUTURE handling.
    import icalendar
    import pytz
    from khal.khalendar.backend import SQLiteDb
    from khal.khalendar.event import Event
    locale = {'local_timezone': pytz.UTC, 'default_timezone': pytz.UTC}
    doc = icalendar.Calendar.from_ical(raw)
    components = doc.walk('VEVENT')
    blocked = len(components) != 1 or any(unsafe_ics(e) for e in components)
    db = SQLiteDb(['calendar'], ':memory:', locale)
    try:
        db.update(raw, href, etag, 'calendar')
        rows = list(db.get_localized(start, end)) + list(db.get_floating(start.replace(tzinfo=None), end.replace(tzinfo=None)))
    finally:
        db.conn.close()
    result = []
    for source, ident, begin, finish, ref, tag, cal in rows:
        item = Event.fromString(source, ref=ref, start=begin, end=finish, locale=locale)
        all_day = item.allday
        result.append({'id': ident, 'etag': tag, 'title': item.summary,
                       'start': begin.date().isoformat() if all_day and isinstance(begin, dt.datetime) else begin.isoformat(),
                       'end': finish.date().isoformat() if all_day and isinstance(finish, dt.datetime) else finish.isoformat(),
                       'allDay': all_day, 'blocked': blocked, 'timezone': 'UTC' if not all_day else ''})
    return result


def validate_draft(draft):
    title = str(draft.get('title', '')).strip()
    require(title and len(title) <= 1024, 'Enter a title of at most 1024 characters.')
    try:
        if draft.get('allDay'):
            start, end = dt.date.fromisoformat(draft['start']), dt.date.fromisoformat(draft['end'])
        else:
            start, end = dt.datetime.fromisoformat(draft['start']), dt.datetime.fromisoformat(draft['end'])
            require(start.tzinfo is not None and end.tzinfo is not None, 'Include a UTC offset in timed events, for example +02:00.')
        require(end > start, 'End must be after start. All-day end dates are exclusive.')
        if not draft.get('allDay'):
            start, end = start.astimezone(UTC), end.astimezone(UTC)
    except (ValueError, KeyError, TypeError):
        raise Failure('Use ISO dates or date-times with a UTC offset.') from None
    return {'title': title, 'start': start, 'end': end}


def google_event(raw):
    start, end = raw.get('start', {}), raw.get('end', {})
    return {'id': raw['id'], 'etag': raw.get('etag', ''), 'title': raw.get('summary', '(Untitled)'),
            'start': start.get('date', start.get('dateTime', '')), 'end': end.get('date', end.get('dateTime', '')),
            'allDay': 'date' in start, 'timezone': start.get('timeZone', ''),
            'blocked': bool(raw.get('recurringEventId') or raw.get('recurrence') or raw.get('attendees')
                            or raw.get('eventType', 'default') != 'default')}


class Google:
    def __init__(self, account, secret, keyring):
        self.account, self.secret, self.keyring = account, secret, keyring
        token = request('POST', TOKEN, data={'client_id': account['clientId'], 'client_secret': secret['clientSecret'],
                         'refresh_token': secret['refreshToken'], 'grant_type': 'refresh_token'}).json()
        require(token.get('access_token'), 'Google refresh failed. Reconnect this account.')
        self.token = token['access_token']
        if token.get('refresh_token'):
            secret['refreshToken'] = token['refresh_token']
            keyring.put(account['id'], secret)

    def call(self, method, path, **kwargs):
        headers = kwargs.pop('headers', {})
        headers['Authorization'] = 'Bearer ' + self.token
        return request(method, GOOGLE + path, headers=headers, **kwargs)

    def pages(self, path, params=None):
        params = dict(params or {})
        result, seen = [], set()
        for _ in range(100):
            payload = self.call('GET', path, params=params).json()
            result += payload.get('items', [])
            token = payload.get('nextPageToken')
            if not token:
                return result
            require(token not in seen, 'Provider pagination repeated.')
            seen.add(token)
            params['pageToken'] = token
        raise Failure('Calendar result exceeds the supported page limit.')

    def discover(self):
        return [{'id': item['id'], 'name': item.get('summary', item['id']),
                 'writable': item.get('accessRole') in ('owner', 'writer')}
                for item in self.pages('users/me/calendarList')]

    def events(self, calendar, start, end):
        return [google_event(item) for item in self.pages('calendars/' + quote(calendar['id'], safe='') + '/events',
                {'singleEvents': 'true', 'timeMin': start.isoformat(), 'timeMax': end.isoformat(), 'maxResults': 250})
                if item.get('status') != 'cancelled']

    def write(self, calendar, operation, event, draft):
        path = 'calendars/' + quote(calendar['id'], safe='') + '/events'
        headers = {}
        if operation != 'create':
            path += '/' + quote(event['id'], safe='')
            require(str(event.get('etag', '')).startswith('"'), 'An ETag is required. Refresh first.')
            current = self.call('GET', path).json()
            require(current.get('etag') == event['etag'], 'Conflict: refresh and reopen this event.')
            require(not google_event(current)['blocked'], 'Recurring or scheduled meetings must be changed in the provider app.')
            headers['If-Match'] = event['etag']
        if operation == 'delete':
            self.call('DELETE', path, headers=headers, params={'sendUpdates': 'none'})
            return
        values = validate_draft(draft)
        key = 'date' if draft.get('allDay') else 'dateTime'
        patch = {'summary': values['title'], 'start': {key: values['start'].isoformat()}, 'end': {key: values['end'].isoformat()}}
        # PATCH preserves unsupported provider fields; nested time fields replace the time representation.
        if operation != 'create':
            oldkey = 'dateTime' if key == 'date' else 'date'
            patch['start'][oldkey] = None
            patch['end'][oldkey] = None
            patch['start']['timeZone'] = None
            patch['end']['timeZone'] = None
        self.call('POST' if operation == 'create' else 'PATCH', path, json=patch, headers=headers, params={'sendUpdates': 'none'})


def google_login(client_id, client_secret, emit):
    require(re.fullmatch(r'[A-Za-z0-9._-]+\.apps\.googleusercontent\.com', client_id or '') and client_secret,
            'Configure a Google Desktop OAuth client ID and secret. No client is bundled.')
    state, verifier = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
    result = {}
    class Callback(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_GET(self):
            parsed = urlsplit(self.path)
            query = parse_qs(parsed.query)
            valid = (parsed.path == '/oauth2callback' and not parsed.netloc and
                     self.headers.get('Host') == '127.0.0.1:%s' % self.server.server_port and
                     len(query.get('state', [])) == 1 and secrets.compare_digest(query['state'][0], state))
            self.send_response(200 if valid else 400)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()
            self.wfile.write(b'Return to Calendar.' if valid else b'Invalid callback.')
            if valid:
                result.update(query)
    class Server(http.server.HTTPServer):
        def get_request(self):
            connection, address = super().get_request()
            connection.settimeout(3)
            return connection, address
        def handle_error(self, *args):
            pass
    with Server(('127.0.0.1', 0), Callback) as server:
        server.timeout = 1
        redirect = 'http://127.0.0.1:%s/oauth2callback' % server.server_port
        url = 'https://accounts.google.com/o/oauth2/v2/auth?' + urlencode({
            'client_id': client_id, 'redirect_uri': redirect, 'response_type': 'code',
            'scope': ' '.join(SCOPES), 'code_challenge': challenge, 'code_challenge_method': 'S256',
            'state': state, 'access_type': 'offline', 'prompt': 'consent'})
        emit({'authorizationUrl': url})
        deadline = time.monotonic() + 180
        while not result and time.monotonic() < deadline:
            server.handle_request()
    require('error' not in result and len(result.get('code', [])) == 1, 'Google sign-in cancelled or timed out.')
    token = request('POST', TOKEN, data={'client_id': client_id, 'client_secret': client_secret,
                    'code': result['code'][0], 'code_verifier': verifier, 'redirect_uri': redirect,
                    'grant_type': 'authorization_code'}).json()
    require(set(SCOPES).issubset(set(token.get('scope', '').split())) and token.get('refresh_token'),
            'Google did not grant all Calendar permissions and offline access. Reconnect and accept both permissions.')
    return {'refreshToken': token['refresh_token'], 'clientSecret': client_secret}


class Backend:
    def __init__(self, store, keyring=None):
        self.store, self.keyring = store, keyring or Keyring()

    def provider(self, account):
        secret = self.keyring.get(account['id'])
        return Apple(account, secret) if account['provider'] == 'icloud' else Google(account, secret, self.keyring)

    def run(self, req, emit=lambda value: None):
        op = req.get('op', 'load')
        data = self.store.data
        if op == 'connect':
            ident = uuid.uuid4().hex
            require(req.get('provider') in ('icloud', 'google'), 'Choose iCloud or Google.')
            account = {'id': ident, 'provider': req['provider'], 'name': str(req.get('name', '')).strip() or req['provider']}
            if account['provider'] == 'icloud':
                account['username'] = str(req.get('username', '')).strip()
                secret = {'password': req.get('password', '')}
                require(account['username'] and secret['password'], 'Enter your Apple account and app-specific password.')
                Apple(account, secret).discover()  # verify before persisting
            else:
                account['clientId'] = req.get('clientId', '')
                secret = google_login(account['clientId'], req.get('clientSecret', ''), emit)
            self.keyring.put(ident, secret)
            data['accounts'].append(account)
            self.store.save()
        elif op == 'disconnect':
            require(req.get('confirmed') is True, 'Confirm removing this local account.')
            account = next(a for a in data['accounts'] if a['id'] == req['account'])
            self.keyring.delete(account['id'])
            data['accounts'].remove(account)
            self.store.save()
        elif op == 'visibility':
            hidden = set(data['hidden'])
            if req.get('visible'):
                hidden.discard(req['calendar'])
            else:
                hidden.add(req['calendar'])
            data['hidden'] = sorted(hidden)
            self.store.save()
        elif op in ('create', 'edit', 'delete'):
            require(req.get('confirmed') is True, 'Confirm the destination and event change.')
            account = next(a for a in data['accounts'] if a['id'] == req['account'])
            provider = self.provider(account)
            calendar = next((c for c in provider.discover() if c['id'] == req['calendar']), None)
            require(calendar and calendar['writable'], 'Choose an explicitly writable calendar.')
            require(not req.get('event', {}).get('blocked'), 'Recurring or scheduled meetings must be changed in the provider app.')
            provider.write(calendar, op, req.get('event', {}), req.get('draft', {}))
        elif op not in ('load', 'refresh'):
            raise Failure('Unknown Calendar operation.')
        if op not in ('load', 'refresh'):
            return {'ok': True, 'changed': True}
        start = dt.datetime.fromisoformat(req['start']).astimezone(UTC)
        end = dt.datetime.fromisoformat(req['end']).astimezone(UTC)
        require(dt.timedelta(0) < end - start <= dt.timedelta(days=100), 'Choose a window of at most 100 days.')
        result = {'ok': True, 'accounts': data['accounts'], 'calendars': [], 'events': [], 'errors': [], 'stale': False}
        for account in data['accounts']:
            try:
                provider = self.provider(account)
                calendars = provider.discover()
                events = []
                for calendar in calendars:
                    calendar['account'] = account['id']
                    calendar['key'] = account['id'] + ':' + calendar['id']
                    calendar['visible'] = calendar['key'] not in data['hidden']
                    for event in provider.events(calendar, start, end):
                        event['account'], event['calendar'], event['calendarKey'] = account['id'], calendar['id'], calendar['key']
                        event['writable'] = calendar['writable']
                        events.append(event)
                result['calendars'] += calendars
                result['events'] += events
            except Exception as exc:
                result['errors'].append(account['name'] + ': ' + safe_error(exc))
                result['stale'] = True
        result['loadedAt'] = dt.datetime.now(UTC).isoformat()
        return result


def safe_error(exc):
    if isinstance(exc, Failure):
        return str(exc)
    if isinstance(exc, ImportError):
        return 'Missing Python dependency. Install requests, icalendar, khal and pytz; see README.'
    return 'Calendar operation failed. Check setup and refresh; no provider details were logged.'


def main():
    logging.disable(logging.CRITICAL)  # libraries must not print remote event bodies
    os.umask(0o077)
    emit = lambda value: print(json.dumps(value), flush=True)
    try:
        req = json.loads(sys.stdin.readline(1024 * 1024))
        path = os.environ.get('NBSHELL_CALENDAR_STATE') or str(Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'nbshell-calendar')
        import fcntl
        store = Store(path)
        with (store.path / 'lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            store = Store(path)
            emit(Backend(store).run(req, emit))
    except Exception as exc:
        emit({'ok': False, 'error': safe_error(exc)})

if __name__ == '__main__':
    main()
