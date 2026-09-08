#!/usr/bin/env python3

import importlib.util
import base64
from pathlib import Path
import subprocess
import tempfile
import time
import socket
import ssl
import threading


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("phone_auth", ROOT / "auth/nbshell_phone_auth.py")
assert SPEC and SPEC.loader
AUTH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUTH)

request = {
    "id": "request",
    "nonce": "nonce",
    "service": "sudo",
    "user": "nerdi",
    "expires_at": 123,
}
assert AUTH.canonical(request) == b"nbshell-auth-v1\nrequest\nnonce\nsudo\nnerdi\n123"
assert AUTH.token_hash("secret") == AUTH.token_hash("secret")
assert AUTH.token_hash("secret") != AUTH.token_hash("other")
assert "authorize-next".replace("-", "_") == "authorize_next"

with tempfile.TemporaryDirectory(prefix="nbshell-auth-test-") as temporary:
    store = AUTH.Store(Path(temporary))
    store.load()
    token = store.start_pairing(ttl=30)
    assert token
    try:
        store.pair(token, {"device_id": "", "public_key_pem": "invalid"})
    except ValueError:
        pass
    else:
        raise AssertionError("invalid pairing payload was accepted")
    assert AUTH.token_hash(token) in store.pair_tokens, "invalid payload consumed one-time token"
    created = store.create_request("sudo", "nerdi", 10)
    assert created["service"] == "sudo"
    assert created["expires_at"] > time.time()
    assert len(store.pending()) == 1

    key = Path(temporary) / "device-key.pem"
    public = Path(temporary) / "device-public.pem"
    data = Path(temporary) / "challenge"
    signature = Path(temporary) / "signature.der"
    subprocess.run(
        ["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)],
        check=True, capture_output=True,
    )
    subprocess.run(
        ["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(public)],
        check=True, capture_output=True,
    )
    data.write_bytes(AUTH.canonical(created))
    subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key), "-out", str(signature), str(data)],
        check=True, capture_output=True,
    )
    paired = store.pair(token, {
        "device_id": "phone",
        "name": "test",
        "public_key_pem": public.read_text(encoding="utf-8"),
    })
    assert AUTH.token_hash(token) not in store.pair_tokens
    assert store.authenticate_device("phone", paired["bearer_token"])["name"] == "test"
    store.approve(created["id"], "phone", signature.read_bytes())
    assert store.consume_when_approved(created["id"], 1)
    assert not store.consume_when_approved(created["id"], 1)

    grant = store.add_grant("nerdi", "system", 30)
    assert grant["scope"] == "system"
    assert store.consume_grant("sudo", "nerdi")
    assert not store.consume_grant("sudo", "nerdi")

    store.add_grant("nerdi", "polkit-1", 30)
    assert not store.consume_grant("sudo", "nerdi")
    assert store.consume_grant("polkit-1", "nerdi")

    certificate, certificate_key = AUTH.ensure_certificate(Path(temporary))
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certificate, certificate_key)
    server = AUTH.ThreadingHTTPServer(("127.0.0.1", 0), AUTH.AuthHTTPHandler,
                                     ssl_context=context, max_workers=2, connection_timeout=1.0)
    server.store = store
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    clients = []
    try:
        # The first peer never speaks TLS. Another client must still complete
        # its handshake and receive an ordinary HTTP response immediately.
        stalled = socket.create_connection(server.server_address, timeout=2)
        clients.append(stalled)
        client_context = ssl._create_unverified_context()
        with client_context.wrap_socket(socket.create_connection(server.server_address, timeout=2),
                                        server_hostname="localhost") as good:
            good.sendall(b"GET /nonexistent HTTP/1.0\r\n\r\n")
            assert b"404" in good.recv(4096)
        stalled.settimeout(2)
        assert stalled.recv(1) == b"", "stalled TLS connection exceeded its deadline"
        # A valid TLS client with an incomplete body also has a finite lifetime.
        with client_context.wrap_socket(socket.create_connection(server.server_address, timeout=2),
                                        server_hostname="localhost") as slow_body:
            slow_body.sendall(b"POST /v1/pair HTTP/1.0\r\nContent-Length: 100\r\n\r\n{")
            started = time.monotonic()
            try:
                while slow_body.recv(4096):
                    pass
            except (ssl.SSLError, ConnectionResetError):
                pass
            assert time.monotonic() - started < 1.8
    finally:
        for client in clients:
            client.close()
        server.shutdown(); server.server_close(); thread.join(timeout=2)

print("Phone authentication core: OK")
