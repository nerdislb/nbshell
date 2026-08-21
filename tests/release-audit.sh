#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import json
import pathlib
import re
import subprocess

root = pathlib.Path.cwd()
version = (root / "VERSION").read_text(encoding="utf-8").strip()
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?", version):
    raise SystemExit(f"invalid VERSION: {version!r}")
changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
if f"## [{version}]" not in changelog:
    raise SystemExit(f"CHANGELOG.md has no {version} section")

tracked = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
tracked = [name for name in tracked if name]
sensitive_names = re.compile(
    r"(^|/)(?:\.env(?:\..+)?|credentials?\.(?:json|toml|ya?ml)|cookies?\.txt|secrets?\.(?:json|toml|ya?ml))$",
    re.I,
)
bad_names = [name for name in tracked if sensitive_names.search(name)]
if bad_names:
    raise SystemExit("sensitive-looking files are tracked:\n  " + "\n  ".join(bad_names))

checks = {
    "absolute home path": re.compile(r"/home/(?!user(?:/|\b)|example(?:/|\b)|alice(?:/|\b))[A-Za-z0-9._-]+/"),
    "private IPv4 address": re.compile(r"\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
}
findings = []
for name in tracked:
    path = root / name
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for label, pattern in checks.items():
        # Security parser tests intentionally contain fake home paths and
        # private-network URLs to prove that they are rejected.
        if "/tests/" in name and label in ("absolute home path", "private IPv4 address"):
            continue
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            findings.append(f"{name}:{line}: {label}: {match.group(0)}")
if findings:
    raise SystemExit("release privacy audit failed:\n  " + "\n  ".join(findings))

catalog = json.loads((root / "shell/Catalog/plugins.json").read_text(encoding="utf-8"))
catalog_ids = {item["id"] for item in catalog["plugins"]}
for manifest_path in sorted((root / "plugins").glob("*/manifest.json")):
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for field in ("id", "name", "version", "author", "license", "repository"):
        if not manifest.get(field):
            raise SystemExit(f"{manifest_path}: missing release field {field}")
    if manifest["id"] not in catalog_ids:
        raise SystemExit(f"{manifest_path}: bundled plugin missing from catalog")

print(f"Release audit: OK ({version}, {len(tracked)} tracked files)")
PY
