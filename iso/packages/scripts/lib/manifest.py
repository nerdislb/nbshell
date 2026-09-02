#!/usr/bin/env python3
"""Load and validate iso/packages/MANIFEST.toml.

Shell scripts in iso/packages/scripts shell out to this file (`manifest.py
load <path>`) and consume the result as JSON via jq, rather than each
re-implementing TOML parsing and schema checks in bash.
"""
import json
import re
import sys
import tomllib

_HEX40 = re.compile(r"^[0-9a-f]{40}$")
_DATE = re.compile(r"^\d{4}/\d{2}/\d{2}$")


def _fail(message: str) -> None:
    raise SystemExit(f"manifest.py: {message}")


def load(path: str) -> dict:
    with open(path, "rb") as handle:
        try:
            data = tomllib.load(handle)
        except tomllib.TOMLDecodeError as exc:
            _fail(f"{path}: invalid TOML: {exc}")

    for key in ("snapshot", "official", "custom"):
        if key not in data:
            _fail(f"{path}: missing top-level [{key}] section")

    snap = data["snapshot"]
    for key in ("date", "archive_base", "repos", "arch"):
        if key not in snap:
            _fail(f"{path}: [snapshot] missing '{key}'")
    if not _DATE.match(snap["date"]):
        _fail(f"{path}: snapshot.date {snap['date']!r} is not YYYY/MM/DD")
    if not isinstance(snap["repos"], list) or not snap["repos"]:
        _fail(f"{path}: snapshot.repos must be a non-empty list")

    official = data["official"].get("packages")
    if not isinstance(official, list) or not official:
        _fail(f"{path}: [official] packages must be a non-empty list")
    if len(set(official)) != len(official):
        dupes = sorted({p for p in official if official.count(p) > 1})
        _fail(f"{path}: [official] packages has duplicates: {dupes}")

    custom = data["custom"]
    if not isinstance(custom, list) or not custom:
        _fail(f"{path}: [[custom]] must have at least one entry")

    names = set(official)
    seen_custom = set()
    for entry in custom:
        for key in ("name", "pkgbuild", "source", "revision", "description"):
            if key not in entry:
                _fail(f"{path}: [[custom]] entry {entry!r} missing '{key}'")
        name = entry["name"]
        if name in seen_custom:
            _fail(f"{path}: duplicate [[custom]] name {name!r}")
        seen_custom.add(name)
        if name in names:
            _fail(
                f"{path}: {name!r} is listed in both [official] and [[custom]]"
            )
        names.add(name)
        if entry["source"] == "local":
            if entry["revision"] != "HEAD":
                _fail(
                    f"{path}: {name!r} has source = \"local\" so revision "
                    "must be \"HEAD\" (build-package.sh resolves and "
                    "records the real commit at build time)"
                )
        else:
            if not _HEX40.match(entry["revision"]):
                _fail(
                    f"{path}: {name!r} revision {entry['revision']!r} must "
                    "be a full 40-character git commit hash"
                )

    data["_all_package_names"] = sorted(names)
    return data


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[0] != "load":
        _fail("usage: manifest.py load <path-to-MANIFEST.toml>")
    print(json.dumps(load(argv[1]), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
