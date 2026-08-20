"""Browser-header authentication and yt-dlp cookie export."""

from __future__ import annotations

import hashlib
import os
import shutil
import sqlite3
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

DEFAULT_AUTH_NAME = "browser.json"
LEGACY_AUTH = Path.home() / ".config" / "ytmusicbar" / "browser.json"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "omarchy-ytmusic"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "omarchy-ytmusic"
DEFAULT_AUTH = CONFIG_DIR / DEFAULT_AUTH_NAME

CHROME_KEY_SALT = b"saltysalt"
CHROME_IV = b" " * 16
CHROME_PBKDF2_ROUNDS = 1
CHROME_KEY_LEN = 16
CHROME_HASH_PREFIX_LEN = 32

# Chromium stores the OSCrypt password in libsecret under application=<browser>.
# Omarchy Chromium is launched with --password-store=gnome-libsecret.
BROWSER_ROOTS = (
    ("chromium", "Chromium", Path.home() / ".config" / "chromium"),
    ("chrome", "Chrome", Path.home() / ".config" / "google-chrome"),
    ("brave", "Brave", Path.home() / ".config" / "BraveSoftware" / "Brave-Browser"),
)


class BrowserAuthError(RuntimeError):
    """Could not build ytmusicapi headers from a local browser session."""


@dataclass(frozen=True)
class CookieDatabase:
    keyring: str
    browser: str
    profile: str
    path: Path


def config_dir() -> Path:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_DIR.chmod(0o700)
    return CONFIG_DIR


def cache_dir() -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_DIR.chmod(0o700)
    return CACHE_DIR


def default_auth_path() -> Path:
    return DEFAULT_AUTH


def resolve_auth_path(explicit: str | None = None) -> Path:
    if explicit:
        path = Path(os.path.expanduser(explicit)).expanduser()
        if path.is_file():
            return path
    if DEFAULT_AUTH.is_file() and DEFAULT_AUTH.stat().st_size > 2:
        return DEFAULT_AUTH
    if LEGACY_AUTH.is_file() and LEGACY_AUTH.stat().st_size > 2:
        return LEGACY_AUTH
    return DEFAULT_AUTH


def auth_available(path: Path | None = None) -> bool:
    target = path or resolve_auth_path()
    return target.is_file() and target.stat().st_size > 2


def save_headers(headers_raw: str, dest: Path | None = None) -> Path:
    from ytmusicapi import setup

    target = dest or default_auth_path()
    config_dir()
    target.parent.mkdir(parents=True, exist_ok=True)
    setup(filepath=str(target), headers_raw=headers_raw)
    _ensure_browser_authorization(target)
    target.chmod(0o600)
    return target


def load_headers(path: Path) -> dict:
    import json

    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("browser.json must be a JSON object")
    return data


def cookie_header(headers: dict) -> str:
    for key, value in headers.items():
        if str(key).lower() == "cookie":
            return str(value or "")
    return ""


def parse_cookie_header(header: str) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    for part in str(header or "").split(";"):
        item = part.strip()
        if not item or "=" not in item:
            continue
        name, value = item.split("=", 1)
        name = name.strip()
        if name:
            pairs.append((name, value.strip()))
    return pairs


def headers_raw_from_cookies(
    pairs: list[tuple[str, str]], authuser: str = "0"
) -> str:
    header = "; ".join(f"{name}={value}" for name, value in pairs)
    origin = "https://music.youtube.com"
    authorization = sapisidhash(header, origin)
    lines = [
        f"cookie: {header}",
        f"x-goog-authuser: {authuser}",
        f"origin: {origin}",
        f"x-origin: {origin}",
    ]
    if authorization:
        lines.append(f"authorization: {authorization}")
    return "\n".join(lines) + "\n"


def sapisid_value(header: str) -> str:
    for name, value in parse_cookie_header(header):
        if name == "__Secure-3PAPISID":
            return value
    return ""


def sapisidhash(header: str, origin: str = "https://music.youtube.com") -> str:
    sapisid = sapisid_value(header)
    if not sapisid:
        return ""
    unix = str(int(time.time()))
    digest = hashlib.sha1(f"{unix} {sapisid} {origin}".encode("utf-8")).hexdigest()
    return f"SAPISIDHASH {unix}_{digest}"


def _ensure_browser_authorization(path: Path) -> None:
    import json

    headers = load_headers(path)
    existing = ""
    for key, value in headers.items():
        if str(key).lower() == "authorization":
            existing = str(value or "")
            break
    if "SAPISIDHASH" in existing:
        return
    header = cookie_header(headers)
    origin = str(headers.get("origin") or headers.get("x-origin") or "https://music.youtube.com")
    authorization = sapisidhash(header, origin)
    if not authorization:
        return
    headers["origin"] = origin
    headers["x-origin"] = headers.get("x-origin") or origin
    headers["authorization"] = authorization
    path.write_text(json.dumps(headers, indent=4, sort_keys=True, ensure_ascii=True), encoding="utf-8")
    path.chmod(0o600)


def write_netscape_cookies(header: str, dest: Path | None = None) -> Path:
    target = dest or (cache_dir() / "cookies.txt")
    cache_dir()
    pairs = parse_cookie_header(header)
    lines = [
        "# Netscape HTTP Cookie File",
        "# Generated by Omarchy YouTube Music. Do not share this file.",
    ]
    for name, value in pairs:
        secure = "TRUE" if name.startswith("__Secure-") or name.startswith("__Host-") else "FALSE"
        domain = ".youtube.com"
        lines.append(f"{domain}\tTRUE\t/\t{secure}\t0\t{name}\t{value}")
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    target.chmod(0o600)
    return target


def export_cookies(auth_path: Path) -> Path | None:
    if not auth_available(auth_path):
        return None
    try:
        header = cookie_header(load_headers(auth_path))
    except Exception:
        return None
    if not header:
        return None
    return write_netscape_cookies(header)


def clear_auth(path: Path | None = None) -> None:
    target = path or default_auth_path()
    if target.is_file():
        target.unlink()
    cookies = cache_dir() / "cookies.txt"
    if cookies.is_file():
        cookies.unlink()


def iter_cookie_databases(
    roots: tuple[tuple[str, str, Path], ...] | None = None,
) -> list[CookieDatabase]:
    found: list[CookieDatabase] = []
    for keyring, label, root in roots or BROWSER_ROOTS:
        if not root.is_dir():
            continue
        profiles = _profile_dirs(root)
        for profile in profiles:
            for relative in ("Network/Cookies", "Cookies"):
                path = profile / relative
                if path.is_file():
                    found.append(CookieDatabase(
                        keyring=keyring,
                        browser=label,
                        profile=profile.name,
                        path=path,
                    ))
                    break
    return found


def import_from_browser(
    dest: Path | None = None,
    *,
    databases: list[CookieDatabase] | None = None,
    password_for: dict[str, bytes] | None = None,
) -> Path:
    pairs, _source = extract_youtube_cookies(
        databases=databases, password_for=password_for
    )
    names = {name for name, _ in pairs}
    if "__Secure-3PAPISID" not in names:
        raise BrowserAuthError(
            "Chromium is not signed in to YouTube Music. "
            "Open music.youtube.com, sign in, then try again."
        )
    path = save_headers(headers_raw_from_cookies(pairs), dest)
    return path


def extract_youtube_cookies(
    *,
    databases: list[CookieDatabase] | None = None,
    password_for: dict[str, bytes] | None = None,
) -> tuple[list[tuple[str, str]], CookieDatabase]:
    candidates = databases if databases is not None else iter_cookie_databases()
    if not candidates:
        raise BrowserAuthError(
            "No Chromium cookie database was found on this computer."
        )

    best: tuple[tuple[int, int, int, int], list[tuple[str, str]], CookieDatabase] | None = None
    last_error = ""
    passwords: dict[str, bytes] = dict(password_for or {})

    for database in candidates:
        try:
            if database.keyring not in passwords:
                passwords[database.keyring] = os_crypt_password(database.keyring)
            pairs = read_youtube_cookies(database.path, passwords[database.keyring])
        except BrowserAuthError as exc:
            last_error = str(exc)
            continue
        except Exception as exc:
            last_error = str(exc)
            continue
        names = {name for name, _ in pairs}
        rank = (
            1 if "__Secure-3PAPISID" in names else 0,
            _browser_rank(database.keyring),
            1 if database.profile == "Default" else 0,
            len(pairs),
        )
        if best is None or rank > best[0]:
            best = (rank, pairs, database)

    if best is None:
        raise BrowserAuthError(
            last_error
            or "Could not read Chromium cookies. Unlock the login keyring and try again."
        )
    return best[1], best[2]


def read_youtube_cookies(db_path: Path, password: bytes) -> list[tuple[str, str]]:
    key = derive_os_crypt_key(password)
    by_name: dict[str, tuple[int, str]] = {}
    with tempfile.TemporaryDirectory(prefix="omarchy-ytmusic-cookies-") as tmp:
        copied = _copy_sqlite(db_path, Path(tmp))
        connection = sqlite3.connect(str(copied))
        try:
            rows = connection.execute(
                "SELECT host_key, name, value, encrypted_value FROM cookies"
            ).fetchall()
        finally:
            connection.close()

    for host, name, value, encrypted in rows:
        host_text = str(host or "")
        if "youtube.com" not in host_text:
            continue
        name_text = str(name or "").strip()
        if not name_text:
            continue
        decoded = str(value or "")
        blob = encrypted if isinstance(encrypted, (bytes, bytearray)) else b""
        if blob:
            try:
                decoded = decrypt_chrome_value(bytes(blob), key)
            except Exception:
                if not decoded:
                    continue
        if decoded == "":
            continue
        preference = _host_preference(host_text)
        previous = by_name.get(name_text)
        if previous is None or preference >= previous[0]:
            by_name[name_text] = (preference, decoded)
    return [(name, value) for name, (_pref, value) in by_name.items()]


def os_crypt_password(application: str) -> bytes:
    lookups = (
        ["secret-tool", "lookup", "application", application],
        ["secret-tool", "lookup", "xdg:schema",
         f"{application}_libsecret_os_crypt_password_v2"],
        ["secret-tool", "lookup", "xdg:schema",
         "chrome_libsecret_os_crypt_password_v2"],
        ["secret-tool", "lookup", "xdg:schema",
         "chromium_libsecret_os_crypt_password_v2"],
    )
    if shutil.which("secret-tool") is None:
        raise BrowserAuthError(
            "secret-tool is missing. Install libsecret to read Chromium cookies, "
            "or paste request headers instead."
        )
    for command in lookups:
        try:
            proc = subprocess.run(
                command, capture_output=True, text=True, timeout=8, check=False
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if proc.returncode == 0 and proc.stdout:
            return proc.stdout.encode("utf-8")
    raise BrowserAuthError(
        "Could not unlock the Chromium cookie key. "
        "Sign in to Chromium once, then try again."
    )


def derive_os_crypt_key(password: bytes) -> bytes:
    return hashlib.pbkdf2_hmac(
        "sha1", password, CHROME_KEY_SALT, CHROME_PBKDF2_ROUNDS, CHROME_KEY_LEN
    )


def decrypt_chrome_value(encrypted: bytes, key: bytes) -> str:
    if not encrypted:
        return ""
    prefix = encrypted[:3]
    payload = encrypted[3:] if prefix in (b"v10", b"v11") else encrypted
    if len(payload) < 16 or len(payload) % 16 != 0:
        raise ValueError("unsupported Chromium cookie ciphertext")
    plain = unpad_pkcs7(aes_cbc_decrypt(payload, key, CHROME_IV))
    if len(plain) > CHROME_HASH_PREFIX_LEN:
        digest, rest = plain[:CHROME_HASH_PREFIX_LEN], plain[CHROME_HASH_PREFIX_LEN:]
        if hashlib.sha256(rest).digest() == digest:
            return rest.decode("utf-8")
        try:
            return rest.decode("utf-8")
        except UnicodeDecodeError:
            pass
    return plain.decode("utf-8")


def aes_cbc_decrypt(ciphertext: bytes, key: bytes, iv: bytes) -> bytes:
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

        decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
        return decryptor.update(ciphertext) + decryptor.finalize()
    except ImportError:
        pass
    try:
        from yt_dlp.aes import aes_cbc_decrypt_bytes

        return aes_cbc_decrypt_bytes(ciphertext, key, iv)
    except ImportError:
        pass
    if shutil.which("openssl") is None:
        raise BrowserAuthError(
            "Need openssl, yt-dlp, or the cryptography package to read Chromium cookies."
        )
    proc = subprocess.run(
        [
            "openssl",
            "enc",
            "-aes-128-cbc",
            "-d",
            "-nopad",
            "-K",
            key.hex(),
            "-iv",
            iv.hex(),
        ],
        input=ciphertext,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        detail = proc.stderr.decode("utf-8", "replace").strip()
        raise BrowserAuthError(detail or "openssl could not decrypt Chromium cookies")
    return proc.stdout


def unpad_pkcs7(data: bytes) -> bytes:
    if not data:
        raise ValueError("empty PKCS7 payload")
    pad = data[-1]
    if pad < 1 or pad > 16 or data[-pad:] != bytes([pad]) * pad:
        raise ValueError("invalid PKCS7 padding")
    return data[:-pad]


def _copy_sqlite(src: Path, directory: Path) -> Path:
    dest = directory / "Cookies"
    shutil.copy2(src, dest)
    for suffix in ("-wal", "-shm", "-journal"):
        extra = Path(str(src) + suffix)
        if extra.is_file():
            shutil.copy2(extra, Path(str(dest) + suffix))
    return dest


def _profile_dirs(root: Path) -> list[Path]:
    profiles: list[Path] = []
    default = root / "Default"
    if default.is_dir():
        profiles.append(default)
    extras = []
    for child in root.iterdir():
        if not child.is_dir() or child.name == "Default":
            continue
        if (child / "Cookies").is_file() or (child / "Network" / "Cookies").is_file():
            extras.append(child)
    extras.sort(key=lambda item: item.name)
    profiles.extend(extras)
    return profiles


def _browser_rank(keyring: str) -> int:
    order = {"chromium": 3, "chrome": 2, "brave": 1}
    return order.get(keyring, 0)


def _host_preference(host: str) -> int:
    if host.endswith("music.youtube.com"):
        return 3
    if host in {".youtube.com", "youtube.com"}:
        return 2
    if "youtube.com" in host:
        return 1
    return 0
