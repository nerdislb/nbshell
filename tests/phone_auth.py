#!/usr/bin/env python3

import importlib.util
import base64
from pathlib import Path
import subprocess
import tempfile
import time


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

print("Phone authentication core: OK")
