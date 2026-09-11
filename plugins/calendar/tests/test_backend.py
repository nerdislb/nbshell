import datetime as dt
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

spec = importlib.util.spec_from_file_location('backend', Path(__file__).parents[1] / 'backend/calendar_backend.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
ICS = '''BEGIN:VCALENDAR\r
VERSION:2.0\r
BEGIN:VEVENT\r
UID:fixture\r
DTSTART:20260911T100000Z\r
DTEND:20260911T110000Z\r
SUMMARY:Example\r
DESCRIPTION:Keep this\r
X-PRIVATE-FIELD:retain\r
END:VEVENT\r
END:VCALENDAR\r
'''
class Response:
    def __init__(self, body='', data=None, etag='"one"'):
        self.content = body.encode()
        self.headers = {'ETag': etag}
        self.data = data
    def json(self): return self.data

class Tests(unittest.TestCase):
    def test_origins_and_collection_boundaries(self):
        for url in ['http://caldav.icloud.com/', 'https://caldav.icloud.com.evil.test/', 'https://evil.icloud.com/',
                    'https://user:password@caldav.icloud.com/', 'https://p01-caldav.icloud.com:444/',
                    'https://caldav.icloud.com/?x=secret', 'https://caldav.icloud.com/a/%2e%2e/b', 'https://127.0.0.1/']:
            with self.subTest(url=url), self.assertRaises(b.Failure): b.apple_url(url)
        base = 'https://p01-caldav.icloud.com/123/cal/'
        self.assertEqual(b.member_url('event.ics', base), base + 'event.ics')
        for href in ['../other/event.ics', '/123/cal-other/event.ics', 'https://p02-caldav.icloud.com/123/cal/event.ics', 'a%2fb.ics']:
            with self.assertRaises(b.Failure): b.member_url(href, base)

    def test_recurrence_exclusions_overrides_and_all_day(self):
        raw = ICS.replace('SUMMARY:Example', 'RRULE:FREQ=DAILY;COUNT=3\r\nEXDATE:20260912T100000Z\r\nSUMMARY:Example')
        start, end = dt.datetime(2026, 9, 1, tzinfo=b.UTC), dt.datetime(2026, 10, 1, tzinfo=b.UTC)
        events = b.expand_ics(raw, 'x', '"one"', start, end)
        self.assertEqual(len(events), 2)
        self.assertTrue(all(e['blocked'] for e in events))
        override = 'BEGIN:VEVENT\r\nUID:fixture\r\nRECURRENCE-ID:20260913T100000Z\r\nDTSTART:20260913T120000Z\r\nDTEND:20260913T130000Z\r\nSUMMARY:Moved\r\nEND:VEVENT\r\n'
        events = b.expand_ics(raw.replace('END:VCALENDAR', override + 'END:VCALENDAR'), 'x', '"one"', start, end)
        self.assertEqual(events[-1]['title'], 'Moved')
        self.assertIn('12:00', events[-1]['start'])
        raw = ICS.replace('DTSTART:20260911T100000Z', 'DTSTART;VALUE=DATE:20260911').replace('DTEND:20260911T110000Z', 'DTEND;VALUE=DATE:20260913')
        event = b.expand_ics(raw, 'x', '"one"', start, end)[0]
        self.assertTrue(event['allDay'])
        self.assertEqual(event['end'], '2026-09-13')

    def test_dst(self):
        raw = ICS.replace('DTSTART:20260911T100000Z', 'DTSTART;TZID=Europe/Vienna:20261024T100000').replace('DTEND:20260911T110000Z', 'DTEND;TZID=Europe/Vienna:20261024T110000').replace('SUMMARY:Example','RRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:Example')
        events = b.expand_ics(raw, 'x', '"one"', dt.datetime(2026,10,23,tzinfo=b.UTC), dt.datetime(2026,10,28,tzinfo=b.UTC))
        self.assertEqual([e['start'][11:16] for e in events], ['08:00','09:00','09:00'])

    def test_patch_preserves_unknown_and_uses_etag(self):
        apple = b.Apple({'username':'synthetic'}, {'password':'synthetic'})
        calls=[]
        def call(method, url, body=None, headers=None):
            calls.append((method,url,body,headers))
            return Response(ICS)
        apple.call=call
        draft={'title':'Changed','start':'2026-09-11T12:00:00+02:00','end':'2026-09-11T13:00:00+02:00'}
        apple.write({'id':'https://caldav.icloud.com/cal/'}, 'edit', {'id':'https://caldav.icloud.com/cal/x.ics','etag':'"one"'}, draft)
        self.assertIn(b'X-PRIVATE-FIELD:retain',calls[-1][2])
        self.assertIn(b'DESCRIPTION:Keep this',calls[-1][2])
        self.assertEqual(calls[-1][3]['If-Match'],'"one"')
        with self.assertRaises(b.Failure): apple.write({'id':'https://caldav.icloud.com/cal/'},'delete',{'id':'https://caldav.icloud.com/cal/x.ics','etag':'"old"'}, {})
        self.assertEqual(calls[-1][0], 'GET')

    def test_reject_series_and_scheduling_writes(self):
        for prop in ['RRULE:FREQ=DAILY', 'ATTENDEE:mailto:person@example.test', 'ORGANIZER:mailto:person@example.test']:
            apple=b.Apple({'username':'synthetic'},{'password':'synthetic'})
            apple.call=lambda *args, **kwargs: Response(ICS.replace('SUMMARY:Example', prop+'\r\nSUMMARY:Example'))
            with self.assertRaises(b.Failure): apple.write({'id':'https://caldav.icloud.com/cal/'},'delete',{'id':'https://caldav.icloud.com/cal/x.ics','etag':'"one"'}, {})

    def test_drafts_require_offsets_and_positive_duration(self):
        for draft in [{'start':'2026-09-11T12:00','end':'2026-09-11T13:00'}, {'allDay':True,'start':'2026-09-11','end':'2026-09-11'}]:
            with self.assertRaises(b.Failure): b.validate_draft(dict(draft,title='Title'))

    def test_google_patch_and_recurring_rejection(self):
        google=object.__new__(b.Google)
        calls=[]
        raw={'id':'e','etag':'"one"','start':{'date':'2026-09-11'},'end':{'date':'2026-09-12'}}
        def call(*args, **kwargs):
            calls.append((args,kwargs))
            return Response(data=raw)
        google.call=call
        google.write({'id':'cal@example.test'}, 'edit', {'id':'e','etag':'"one"'}, {'title':'New','allDay':True,'start':'2026-09-11','end':'2026-09-13'})
        self.assertEqual(calls[-1][0][0],'PATCH')
        self.assertEqual(calls[-1][1]['headers']['If-Match'],'"one"')
        self.assertNotIn('description',calls[-1][1]['json'])
        raw['recurringEventId']='series'
        with self.assertRaises(b.Failure): google.write({'id':'cal'},'delete',{'id':'e','etag':'"one"'}, {})

    def test_secret_stdin_and_sanitized_errors(self):
        with patch.object(b.subprocess,'run') as run:
            run.return_value.returncode=0
            run.return_value.stdout=''
            b.Keyring().put('account', {'password':'do-not-log'})
            self.assertNotIn('do-not-log',str(run.call_args.args))
            self.assertIn('do-not-log',run.call_args.kwargs['input'])
        self.assertNotIn('do-not-log',b.safe_error(ValueError('do-not-log')))
        with self.assertRaises(b.Failure): b.google_login('', '', lambda _: None)

    def test_discovery_privileges(self):
        apple=b.Apple({'username':'synthetic'},{'password':'synthetic'})
        docs=['<d:multistatus xmlns:d="DAV:"><d:current-user-principal><d:href>/p/</d:href></d:current-user-principal></d:multistatus>',
              '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><c:calendar-home-set><d:href>https://p01-caldav.icloud.com/home/</d:href></c:calendar-home-set></d:multistatus>',
              '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/home/cal/</d:href><d:propstat><d:status>HTTP/1.1 200 OK</d:status><d:prop><d:resourcetype><c:calendar/></d:resourcetype><d:displayname>Read only</d:displayname></d:prop></d:propstat></d:response></d:multistatus>']
        apple.prop=lambda *args: b.xml(docs.pop(0).encode())
        self.assertFalse(apple.discover()[0]['writable'])

    def test_google_pkce_callback_state_and_scopes(self):
        import threading
        import urllib.request
        from urllib.parse import urlsplit, parse_qs, urlencode
        seen = {}
        workers = []
        def emit(message):
            query = parse_qs(urlsplit(message['authorizationUrl']).query)
            seen.update(query)
            def callback():
                for state in ['wrong-state', query['state'][0]]:
                    url = query['redirect_uri'][0] + '?' + urlencode({'state': state, 'code': 'synthetic-code'})
                    try:
                        with urllib.request.urlopen(url, timeout=5) as response:
                            self.assertEqual(response.status, 200)
                    except urllib.error.HTTPError as error:
                        self.assertEqual(error.code, 400)
                        error.close()
            worker = threading.Thread(target=callback)
            workers.append(worker)
            worker.start()
        def token(method, url, data):
            self.assertEqual(url, b.TOKEN)
            self.assertEqual(data['code'], 'synthetic-code')
            challenge = b.base64.urlsafe_b64encode(b.hashlib.sha256(data['code_verifier'].encode()).digest()).decode().rstrip('=')
            self.assertEqual(challenge, seen['code_challenge'][0])
            self.assertEqual(set(seen['scope'][0].split()), set(b.SCOPES))
            self.assertNotIn('gmail', seen['scope'][0])
            return Response(data={'refresh_token': 'synthetic-refresh', 'scope': ' '.join(b.SCOPES)})
        with patch.object(b, 'request', side_effect=token):
            result = b.google_login('synthetic.apps.googleusercontent.com', 'synthetic-client', emit)
        for worker in workers: worker.join()
        self.assertEqual(result['refreshToken'], 'synthetic-refresh')

    def test_google_refresh_rotation_and_pagination(self):
        class Ring:
            saved = None
            def put(self, account, secret): self.saved = dict(secret)
        ring = Ring()
        with patch.object(b, 'request', return_value=Response(data={'access_token':'synthetic-access','refresh_token':'rotated'})) as request:
            google = b.Google({'id':'a','clientId':'desktop'}, {'clientSecret':'synthetic','refreshToken':'old'}, ring)
            self.assertEqual(request.call_args.kwargs['data']['grant_type'], 'refresh_token')
        self.assertEqual(ring.saved['refreshToken'], 'rotated')
        with patch.object(google, 'call', side_effect=[Response(data={'items':[1],'nextPageToken':'p'}),Response(data={'items':[2]})]):
            self.assertEqual(google.pages('users/me/calendarList'), [1,2])

    def test_transport_never_follows_redirect_or_ambient_auth(self):
        import requests
        with patch.object(requests, 'Session') as factory:
            session = factory.return_value
            response = session.request.return_value
            response.status_code = 302
            response.content = b''
            with self.assertRaises(b.Failure): b.request('GET', 'https://caldav.icloud.com/')
            self.assertFalse(session.trust_env)
            self.assertFalse(session.request.call_args.kwargs['allow_redirects'])

    def test_readonly_guard_and_store_no_secrets(self):
        with tempfile.TemporaryDirectory(prefix="calendar-backend-") as folder:
            store=b.Store(folder)
            store.data['accounts']=[{'id':'a','provider':'icloud','name':'Test'}]
            store.save()
            backend=b.Backend(store)
            class ReadOnly:
                def discover(self): return [{'id':'cal','writable':False}]
                def write(self,*args): raise AssertionError('remote write')
            backend.provider=lambda account: ReadOnly()
            with self.assertRaises(b.Failure): backend.run({'op':'delete','confirmed':True,'account':'a','calendar':'cal'})
            self.assertEqual(store.file.stat().st_mode & 0o777,0o600)

    def test_mocked_connect_disconnect_and_visibility(self):
        with tempfile.TemporaryDirectory(prefix="calendar-backend-") as folder:
            store = b.Store(folder)
            ring = Mock()
            backend = b.Backend(store, ring)
            with patch.object(b, 'Apple') as apple:
                apple.return_value.discover.return_value = []
                backend.run({'op':'connect', 'provider':'icloud', 'username':'synthetic@example.test', 'password':'synthetic', 'name':'Test'})
                apple.return_value.discover.assert_called_once()
            account = store.data['accounts'][0]
            ring.put.assert_called_once_with(account['id'], {'password':'synthetic'})
            self.assertNotIn('synthetic', store.file.read_text().replace('synthetic@example.test', ''))
            key = account['id'] + ':cal'
            for visible in (False, False, True):
                backend.run({'op':'visibility', 'calendar':key, 'visible':visible})
                self.assertEqual(key in b.Store(folder).data['hidden'], not visible)
            with self.assertRaises(b.Failure): backend.run({'op':'disconnect', 'account':account['id']})
            ring.delete.assert_not_called()
            backend.run({'op':'disconnect', 'account':account['id'], 'confirmed':True})
            ring.delete.assert_called_once_with(account['id'])
            self.assertEqual(b.Store(folder).data['accounts'], [])

    def test_failed_connections_and_disconnect_preserve_store(self):
        with tempfile.TemporaryDirectory(prefix="calendar-backend-") as folder:
            store = b.Store(folder)
            ring = Mock()
            backend = b.Backend(store, ring)
            with patch.object(b, 'Apple') as apple:
                apple.return_value.discover.side_effect = b.Failure('Synthetic discovery failure')
                with self.assertRaises(b.Failure): backend.run({'op':'connect','provider':'icloud','username':'test','password':'synthetic'})
            ring.put.assert_not_called()
            self.assertEqual(store.data['accounts'], [])
            with patch.object(b, 'google_login', return_value={'refreshToken':'synthetic'}) as login:
                backend.run({'op':'connect','provider':'google','clientId':'desktop','clientSecret':'synthetic'})
                login.assert_called_once()
            account = store.data['accounts'][0]
            ring.delete.side_effect = b.Failure('Synthetic locked keyring')
            with self.assertRaises(b.Failure): backend.run({'op':'disconnect','account':account['id'],'confirmed':True})
            self.assertEqual(b.Store(folder).data['accounts'], [account])

if __name__ == '__main__': unittest.main()
