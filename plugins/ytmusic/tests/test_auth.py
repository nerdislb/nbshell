#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from auth import (  # noqa: E402
    BrowserAuthError,
    CookieDatabase,
    aes_cbc_decrypt,
    derive_os_crypt_key,
    decrypt_chrome_value,
    extract_youtube_cookies,
    headers_raw_from_cookies,
    parse_cookie_header,
    unpad_pkcs7,
    write_netscape_cookies,
)


def _pad_pkcs7(data: bytes) -> bytes:
    pad = 16 - (len(data) % 16)
    return data + bytes([pad]) * pad


def _aes_cbc_encrypt(plaintext: bytes, key: bytes, iv: bytes) -> bytes:
    padded = _pad_pkcs7(plaintext)
    proc = subprocess.run(
        [
            "openssl",
            "enc",
            "-aes-128-cbc",
            "-e",
            "-nopad",
            "-K",
            key.hex(),
            "-iv",
            iv.hex(),
        ],
        input=padded,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace"))
    return proc.stdout


def _v11_cookie(value: str, key: bytes) -> bytes:
    payload = value.encode("utf-8")
    hashed = hashlib.sha256(payload).digest() + payload
    return b"v11" + _aes_cbc_encrypt(hashed, key, b" " * 16)


class AuthTests(unittest.TestCase):
    def test_parse_cookie_header(self):
        pairs = parse_cookie_header("SID=abc; HSID=xyz;  ; broken")
        self.assertEqual(pairs, [("SID", "abc"), ("HSID", "xyz")])

    def test_netscape_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "cookies.txt"
            write_netscape_cookies("SID=secret; __Secure-1PSID=tok", dest)
            text = dest.read_text(encoding="utf-8")
            self.assertIn("SID\tsecret", text)
            self.assertIn("__Secure-1PSID\ttok", text)
            self.assertIn(".youtube.com", text)
            self.assertEqual(dest.stat().st_mode & 0o777, 0o600)

    def test_headers_raw_from_cookies(self):
        raw = headers_raw_from_cookies(
            [("SID", "abc"), ("__Secure-3PAPISID", "tok")]
        )
        self.assertIn("cookie: SID=abc; __Secure-3PAPISID=tok", raw)
        self.assertIn("x-goog-authuser: 0", raw)
        self.assertIn("authorization: SAPISIDHASH ", raw)
        self.assertIn("origin: https://music.youtube.com", raw)

    def test_unpad_pkcs7(self):
        self.assertEqual(unpad_pkcs7(b"hello" + bytes([11]) * 11), b"hello")
        with self.assertRaises(ValueError):
            unpad_pkcs7(b"hello")

    def test_decrypt_chrome_value_v11_hash_prefix(self):
        password = b"test-os-crypt-password"
        key = derive_os_crypt_key(password)
        encrypted = _v11_cookie("SAPISID-value", key)
        self.assertEqual(decrypt_chrome_value(encrypted, key), "SAPISID-value")
        roundtrip = aes_cbc_decrypt(encrypted[3:], key, b" " * 16)
        self.assertTrue(roundtrip)

    def test_extract_youtube_cookies_from_sqlite(self):
        password = b"unit-test-key"
        key = derive_os_crypt_key(password)
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "Cookies"
            connection = sqlite3.connect(str(db_path))
            connection.execute(
                "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB)"
            )
            rows = [
                (".youtube.com", "__Secure-3PAPISID", "", _v11_cookie("papisid", key)),
                (".youtube.com", "SID", "", _v11_cookie("sid-value", key)),
                (".google.com", "SID", "", _v11_cookie("google-sid", key)),
                (".youtube.com", "PREF", "plain", b""),
            ]
            connection.executemany(
                "INSERT INTO cookies VALUES (?, ?, ?, ?)", rows
            )
            connection.commit()
            connection.close()

            database = CookieDatabase(
                keyring="chromium",
                browser="Chromium",
                profile="Default",
                path=db_path,
            )
            pairs, source = extract_youtube_cookies(
                databases=[database],
                password_for={"chromium": password},
            )
            self.assertEqual(source.path, db_path)
            cookies = dict(pairs)
            self.assertEqual(cookies["__Secure-3PAPISID"], "papisid")
            self.assertEqual(cookies["SID"], "sid-value")
            self.assertEqual(cookies["PREF"], "plain")
            self.assertNotIn("google-sid", cookies.values())

    def test_extract_requires_cookie_database(self):
        with self.assertRaises(BrowserAuthError):
            extract_youtube_cookies(databases=[])


if __name__ == "__main__":
    unittest.main()
