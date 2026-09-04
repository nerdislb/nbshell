#!/usr/bin/env python3
"""Small TLS/Unix-socket broker for biometric nbOS approvals."""

from __future__ import annotations

import argparse
import base64
import grp
import hashlib
import http.server
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import socket
import socketserver
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import parse_qs, urlencode, urlparse
import uuid


PROTOCOL = "nbshell-auth-v1"
DEFAULT_STATE = Path("/var/lib/nbshell-auth")
DEFAULT_SOCKET = Path("/run/nbshell-auth/control.sock")
MAX_BODY = 64 * 1024


def canonical(request: dict) -> bytes:
    fields = (
        PROTOCOL,
        request["id"],
        request["nonce"],
        request["service"],
        request["user"],
        str(request["expires_at"]),
    )
    return "\n".join(fields).encode("utf-8")


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()


class Store:
    def __init__(self, root: Path):
        self.root = root
        self.devices_path = root / "devices.json"
        self.lock = threading.RLock()
        self.devices: dict[str, dict] = {}
        self.pair_tokens: dict[str, float] = {}
        self.requests: dict[str, dict] = {}
        self.grants: list[dict] = []

    def load(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        os.chmod(self.root, 0o700)
        try:
            value = json.loads(self.devices_path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                self.devices = value
        except (OSError, ValueError):
            self.devices = {}

    def save_devices(self) -> None:
        temporary = self.devices_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.devices, indent=2) + "\n", encoding="utf-8")
        os.chmod(temporary, 0o600)
        os.replace(temporary, self.devices_path)

    def cleanup(self) -> None:
        now = time.time()
        self.pair_tokens = {key: expiry for key, expiry in self.pair_tokens.items() if expiry > now}
        self.requests = {
            key: value for key, value in self.requests.items()
            if value["expires_at"] + 30 > now and not value.get("consumed")
        }
        self.grants = [grant for grant in self.grants if grant["expires_at"] > now]

    def start_pairing(self, ttl: int = 180) -> str:
        with self.lock:
            self.cleanup()
            token = secrets.token_urlsafe(32)
            self.pair_tokens[token_hash(token)] = time.time() + ttl
            return token

    def pair(self, token: str, payload: dict) -> dict:
        with self.lock:
            self.cleanup()
            hashed = token_hash(token)
            expiry = self.pair_tokens.get(hashed, 0)
            if expiry <= time.time():
                raise ValueError("invalid or expired pairing token")
            device_id = str(payload.get("device_id") or "")
            public_key = str(payload.get("public_key_pem") or "")
            if not device_id or len(device_id) > 128 or "BEGIN PUBLIC KEY" not in public_key:
                raise ValueError("invalid device identity")
            self.pair_tokens.pop(hashed, None)
            bearer = secrets.token_urlsafe(48)
            self.devices[device_id] = {
                "name": str(payload.get("name") or "nbOS")[:80],
                "public_key_pem": public_key,
                "bearer_hash": token_hash(bearer),
                "paired_at": int(time.time()),
            }
            self.save_devices()
            return {"device_id": device_id, "bearer_token": bearer}

    def authenticate_device(self, device_id: str, bearer: str) -> dict:
        device = self.devices.get(device_id)
        if not device or not secrets.compare_digest(device["bearer_hash"], token_hash(bearer)):
            raise PermissionError("unknown device")
        return device

    def create_request(self, service: str, user: str, ttl: int) -> dict:
        with self.lock:
            self.cleanup()
            request_id = str(uuid.uuid4())
            request = {
                "id": request_id,
                "nonce": secrets.token_urlsafe(32),
                "service": service[:64],
                "user": user[:64],
                "created_at": int(time.time()),
                "expires_at": int(time.time()) + max(5, min(ttl, 60)),
                "approved": False,
                "consumed": False,
            }
            self.requests[request_id] = request
            return dict(request)

    def pending(self) -> list[dict]:
        with self.lock:
            self.cleanup()
            return [
                {key: value[key] for key in ("id", "nonce", "service", "user", "created_at", "expires_at")}
                for value in self.requests.values() if not value["approved"]
            ]

    def approve(self, request_id: str, device_id: str, signature: bytes) -> None:
        with self.lock:
            self.cleanup()
            request = self.requests.get(request_id)
            device = self.devices.get(device_id)
            if not request or request["expires_at"] < time.time() or request["approved"]:
                raise ValueError("request is no longer pending")
            if not device:
                raise PermissionError("unknown device")
            with tempfile.TemporaryDirectory(prefix="nbshell-auth-verify-") as folder:
                root = Path(folder)
                key_path = root / "device.pem"
                data_path = root / "challenge"
                signature_path = root / "signature.der"
                key_path.write_text(device["public_key_pem"], encoding="utf-8")
                data_path.write_bytes(canonical(request))
                signature_path.write_bytes(signature)
                result = subprocess.run(
                    ["openssl", "dgst", "-sha256", "-verify", str(key_path),
                     "-signature", str(signature_path), str(data_path)],
                    capture_output=True, timeout=5, check=False,
                )
            if result.returncode != 0:
                raise PermissionError("invalid signature")
            request["approved"] = True
            request["approved_by"] = device_id

    def consume_when_approved(self, request_id: str, timeout: int) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            with self.lock:
                request = self.requests.get(request_id)
                if not request or request["expires_at"] < time.time():
                    return False
                if request["approved"] and not request["consumed"]:
                    request["consumed"] = True
                    return True
            time.sleep(0.15)
        return False

    def add_grant(self, user: str, scope: str, ttl: int) -> dict:
        with self.lock:
            self.cleanup()
            grant = {
                "id": str(uuid.uuid4()),
                "user": user[:64],
                "scope": scope,
                "expires_at": int(time.time()) + max(5, min(ttl, 60)),
            }
            self.grants.append(grant)
            return dict(grant)

    def consume_grant(self, service: str, user: str) -> bool:
        with self.lock:
            self.cleanup()
            accepted_scopes = {"system", service}
            for index, grant in enumerate(self.grants):
                if grant["user"] == user and grant["scope"] in accepted_scopes:
                    self.grants.pop(index)
                    return True
            return False


class AuthHTTPHandler(http.server.BaseHTTPRequestHandler):
    server_version = "nbshell-auth/1"

    def json_body(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        if length < 0 or length > MAX_BODY:
            raise ValueError("invalid body size")
        value = json.loads(self.rfile.read(length) or b"{}")
        if not isinstance(value, dict):
            raise ValueError("JSON object required")
        return value

    def reply(self, status: int, value: dict) -> None:
        body = json.dumps(value, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def device(self, device_id: str) -> dict:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            raise PermissionError("missing bearer token")
        return self.server.store.authenticate_device(device_id, header[7:])

    def do_GET(self) -> None:
        try:
            parsed = urlparse(self.path)
            if parsed.path != "/v1/requests":
                self.reply(404, {"error": "not found"})
                return
            device_id = parse_qs(parsed.query).get("device_id", [""])[0]
            self.device(device_id)
            self.reply(200, {"requests": self.server.store.pending()})
        except PermissionError as error:
            self.reply(401, {"error": str(error)})
        except Exception as error:
            self.reply(400, {"error": str(error)})

    def do_POST(self) -> None:
        try:
            parsed = urlparse(self.path)
            payload = self.json_body()
            if parsed.path == "/v1/pair":
                result = self.server.store.pair(str(payload.get("pairing_token") or ""), payload)
                self.reply(201, result)
                return
            if parsed.path.startswith("/v1/requests/") and parsed.path.endswith("/approve"):
                request_id = parsed.path.split("/")[3]
                device_id = str(payload.get("device_id") or "")
                self.device(device_id)
                signature = base64.b64decode(str(payload.get("signature") or ""), validate=True)
                self.server.store.approve(request_id, device_id, signature)
                self.reply(200, {"approved": True})
                return
            self.reply(404, {"error": "not found"})
        except PermissionError as error:
            self.reply(401, {"error": str(error)})
        except Exception as error:
            self.reply(400, {"error": str(error)})

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"nbshell-auth: {self.address_string()} {fmt % args}")


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


class UnixHandler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        try:
            _pid, peer_uid, _gid = struct.unpack(
                "3i", self.request.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            )
            payload = json.loads(self.rfile.readline(MAX_BODY))
            operation = payload.get("operation")
            if operation == "pair":
                token = self.server.store.start_pairing()
                self.wfile.write((json.dumps({"ok": True, "pairing_token": token}) + "\n").encode())
                return
            if operation == "authenticate":
                timeout = max(5, min(int(payload.get("timeout", 15)), 60))
                request = self.server.store.create_request(
                    str(payload.get("service") or "unknown"), str(payload.get("user") or "unknown"), timeout
                )
                approved = self.server.store.consume_when_approved(request["id"], timeout)
                self.wfile.write((json.dumps({
                    "ok": approved, "request_id": request["id"], "source": "phone",
                }) + "\n").encode())
                return
            if operation == "authorize_next":
                timeout = max(5, min(int(payload.get("timeout", 30)), 60))
                grant_ttl = max(5, min(int(payload.get("grant_ttl", 30)), 60))
                peer_user = pwd.getpwuid(peer_uid).pw_name
                requested_user = str(payload.get("user") or peer_user)
                user = requested_user if peer_uid == 0 else peer_user
                scope = str(payload.get("scope") or "system")
                if scope not in {"system", "sudo", "polkit-1"}:
                    raise ValueError("invalid authorization scope")
                request = self.server.store.create_request(f"authorize-next:{scope}", user, timeout)
                approved = self.server.store.consume_when_approved(request["id"], timeout)
                grant = self.server.store.add_grant(user, scope, grant_ttl) if approved else None
                self.wfile.write((json.dumps({
                    "ok": approved, "request_id": request["id"], "grant": grant,
                }) + "\n").encode())
                return
            if operation == "consume_grant":
                if peer_uid != 0:
                    raise PermissionError("only PAM/root may consume grants")
                service = str(payload.get("service") or "unknown")
                user = str(payload.get("user") or "unknown")
                consumed = self.server.store.consume_grant(service, user)
                self.wfile.write((json.dumps({"ok": consumed, "consumed": consumed}) + "\n").encode())
                return
            self.wfile.write(b'{"ok":false,"error":"unknown operation"}\n')
        except Exception as error:
            try:
                self.wfile.write((json.dumps({"ok": False, "error": str(error)}) + "\n").encode())
            except (BrokenPipeError, ConnectionResetError):
                pass


class ThreadingUnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def ensure_certificate(state: Path) -> tuple[Path, Path]:
    certificate = state / "server.crt"
    key = state / "server.key"
    if not certificate.exists() or not key.exists():
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "ec",
            "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
            "-days", "3650", "-subj", "/CN=nbshell-phone-auth",
            "-keyout", str(key), "-out", str(certificate),
        ], check=True, capture_output=True)
        os.chmod(key, 0o600)
        os.chmod(certificate, 0o644)
    return certificate, key


def certificate_fingerprint(certificate: Path) -> str:
    result = subprocess.run(
        ["openssl", "x509", "-in", str(certificate), "-outform", "DER"],
        capture_output=True, check=True, timeout=5,
    )
    return hashlib.sha256(result.stdout).hexdigest()


def default_remote_host() -> str:
    try:
        result = subprocess.run(
            ["tailscale", "ip", "-4"], capture_output=True, text=True, check=True, timeout=3,
        )
        address = result.stdout.strip().splitlines()[0]
        if address:
            return address
    except (OSError, subprocess.SubprocessError, IndexError):
        pass
    return "127.0.0.1"


def serve(args: argparse.Namespace) -> int:
    store = Store(args.state)
    store.load()
    certificate, key = ensure_certificate(args.state)
    args.socket.parent.mkdir(parents=True, exist_ok=True)
    if args.socket.exists():
        args.socket.unlink()
    unix_server = ThreadingUnixServer(str(args.socket), UnixHandler)
    unix_server.store = store
    # Members may request their own phone approval, while SO_PEERCRED ensures
    # that only root/PAM can consume it. Android uses the TLS endpoint only.
    try:
        socket_gid = grp.getgrnam("nbshell-auth").gr_gid
    except KeyError:
        socket_gid = 0
    os.chown(args.socket, 0, socket_gid)
    os.chmod(args.socket, 0o660)
    threading.Thread(target=unix_server.serve_forever, daemon=True).start()

    http_server = ThreadingHTTPServer((args.bind, args.port), AuthHTTPHandler)
    http_server.store = store
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.load_cert_chain(certificate, key)
    http_server.socket = context.wrap_socket(http_server.socket, server_side=True)
    try:
        http_server.serve_forever()
    finally:
        unix_server.shutdown()
        args.socket.unlink(missing_ok=True)
    return 0


def control(socket_path: Path, payload: dict) -> dict:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(int(payload.get("timeout", 15)) + 3)
        client.connect(str(socket_path))
        client.sendall((json.dumps(payload) + "\n").encode())
        response = client.makefile("rb").readline(MAX_BODY)
    return json.loads(response)


def show_pairing_qr(pairing_uri: str) -> None:
    """Render the local pairing URI for humans without contaminating JSON stdout."""
    qrencode = shutil.which("qrencode")
    if not qrencode or not sys.stderr.isatty():
        return
    subprocess.run(
        [qrencode, "-t", "ANSIUTF8", pairing_uri],
        stdout=sys.stderr,
        check=False,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE)
    parser.add_argument("--socket", type=Path, default=DEFAULT_SOCKET)
    subparsers = parser.add_subparsers(dest="command", required=True)
    server = subparsers.add_parser("serve")
    server.add_argument("--bind", default="0.0.0.0")
    server.add_argument("--port", type=int, default=8766)
    pair = subparsers.add_parser("pair")
    pair.add_argument("--host", default="")
    pair.add_argument("--port", type=int, default=8766)
    authenticate = subparsers.add_parser("authenticate")
    authenticate.add_argument("--service", default=os.environ.get("PAM_SERVICE", "manual"))
    authenticate.add_argument("--user", default=os.environ.get("PAM_USER", os.environ.get("USER", "")))
    authenticate.add_argument("--timeout", type=int, default=15)
    authorize = subparsers.add_parser("authorize-next")
    authorize.add_argument("--scope", choices=("system", "sudo", "polkit-1"), default="system")
    authorize.add_argument("--user", default=os.environ.get("USER", ""))
    authorize.add_argument("--timeout", type=int, default=30)
    authorize.add_argument("--grant-ttl", type=int, default=30)
    consume = subparsers.add_parser("consume-grant")
    consume.add_argument("--service", required=True)
    consume.add_argument("--user", required=True)
    args = parser.parse_args()
    if args.command == "serve":
        return serve(args)
    payload = {"operation": args.command.replace("-", "_")}
    if args.command == "authenticate":
        payload.update(service=args.service, user=args.user, timeout=args.timeout)
    elif args.command == "authorize-next":
        payload.update(scope=args.scope, user=args.user, timeout=args.timeout, grant_ttl=args.grant_ttl)
    elif args.command == "consume-grant":
        payload.update(service=args.service, user=args.user)
    result = control(args.socket, payload)
    if args.command == "pair" and result.get("ok"):
        certificate, _ = ensure_certificate(args.state)
        query = urlencode({
            "host": args.host or default_remote_host(),
            "port": args.port,
            "token": result["pairing_token"],
            "cert_sha256": certificate_fingerprint(certificate),
        })
        result["pairing_uri"] = f"nbos-auth://pair?{query}"
        show_pairing_qr(result["pairing_uri"])
    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
