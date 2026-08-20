#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from protocol import (  # noqa: E402
    ERROR_UNSUPPORTED_VERSION,
    parse_line,
    redact,
    response,
)


class ProtocolTests(unittest.TestCase):
    def test_parse_line_roundtrip(self):
        self.assertEqual(parse_line('{"command":"ping","id":1,"v":1}')["command"], "ping")
        self.assertIsNone(parse_line(""))
        self.assertIsNone(parse_line("not-json"))

    def test_response_ok_and_error(self):
        ok = response(7, True, {"lifecycle": "ready"})
        self.assertTrue(ok["ok"])
        self.assertEqual(ok["id"], 7)
        self.assertEqual(ok["result"]["lifecycle"], "ready")
        err = response(8, False, code=ERROR_UNSUPPORTED_VERSION, message="nope")
        self.assertFalse(err["ok"])
        self.assertEqual(err["error"]["code"], ERROR_UNSUPPORTED_VERSION)

    def test_redact_cookie_and_authorization(self):
        text = redact("cookie: SID=supersecret authorization: Bearer abc")
        self.assertNotIn("supersecret", text)
        self.assertNotIn("Bearer abc", text)
        self.assertIn("<redacted>", text)


if __name__ == "__main__":
    unittest.main()
