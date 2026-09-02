#!/usr/bin/env python3
"""Check and install checksum- and Sigstore-verified nbshell releases."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request

REPOSITORY = "nerdislb/nbshell"
API_URL = f"https://api.github.com/repos/{REPOSITORY}/releases?per_page=30"
SIGNING_WORKFLOW = f"https://github.com/{REPOSITORY}/.github/workflows/release.yml"
SIGNING_ISSUER = "https://token.actions.githubusercontent.com"
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$", re.ASCII)
MAX_DOWNLOAD_BYTES = 50 * 1024 * 1024
MAX_MEMBER_BYTES = 25 * 1024 * 1024
MAX_TOTAL_EXTRACT_BYTES = 100 * 1024 * 1024
MAX_MEMBERS = 10_000


def version_key(value: str) -> tuple:
    match = SEMVER.fullmatch(value.removeprefix("v"))
    if not match:
        raise ValueError(f"invalid version: {value}")
    major, minor, patch = (int(match.group(i)) for i in range(1, 4))
    prerelease = match.group(4)
    if prerelease is None:
        pre = (1,)
    else:
        parts = []
        for item in prerelease.split("."):
            parts.append((0, int(item)) if item.isdigit() else (1, item.lower()))
        pre = (0, *parts)
    return major, minor, patch, pre


def current_version() -> str:
    script = pathlib.Path(__file__).resolve()
    for candidate in (script.parent.parent / "VERSION", script.parent.parent.parent / "VERSION"):
        if candidate.is_file():
            return candidate.read_text(encoding="utf-8").strip()
    raise OSError("installed VERSION file is missing")


def fetch_json(url: str) -> object:
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/vnd.github+json", "User-Agent": "nbshell-updater"},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


def select_release(releases: list[dict], channel: str) -> dict | None:
    eligible = []
    for release in releases:
        if release.get("draft") or (channel == "stable" and release.get("prerelease")):
            continue
        version = str(release.get("tag_name", "")).removeprefix("v")
        try:
            key = version_key(version)
        except ValueError:
            continue
        eligible.append((key, release))
    return max(eligible, key=lambda item: item[0])[1] if eligible else None


def status(channel: str, releases: list[dict] | None = None) -> dict:
    current = current_version()
    result = {
        "ok": False,
        "channel": channel,
        "current": current,
        "latest": current,
        "available": False,
        "installable": False,
        "prerelease": False,
        "name": "",
        "url": "",
        "publishedAt": "",
        "notes": "",
        "assetUrl": "",
        "checksumUrl": "",
        "bundleUrl": "",
        "error": "",
    }
    try:
        data = releases if releases is not None else fetch_json(API_URL)
        if not isinstance(data, list):
            raise ValueError("release service returned unexpected data")
        release = select_release(data, channel)
        if release is None:
            result.update(ok=True, error="No published release is available yet")
            return result
        latest = str(release["tag_name"]).removeprefix("v")
        archive_name = f"nbshell-{latest}.tar.gz"
        checksum_name = archive_name + ".sha256"
        bundle_name = archive_name + ".sigstore.json"
        assets = {a.get("name"): a.get("browser_download_url", "") for a in release.get("assets", [])}
        result.update(
            ok=True,
            latest=latest,
            available=version_key(latest) > version_key(current),
            installable=bool(assets.get(archive_name) and assets.get(checksum_name) and assets.get(bundle_name)),
            prerelease=bool(release.get("prerelease")),
            name=release.get("name") or release.get("tag_name", ""),
            url=release.get("html_url", ""),
            publishedAt=release.get("published_at", ""),
            notes=release.get("body") or "",
            assetUrl=assets.get(archive_name, ""),
            checksumUrl=assets.get(checksum_name, ""),
            bundleUrl=assets.get(bundle_name, ""),
        )
        if result["available"] and not result["installable"]:
            result["error"] = "The release has no verified installer artifact"
    except (OSError, ValueError, KeyError, json.JSONDecodeError, urllib.error.URLError) as exc:
        result["error"] = f"Release check failed: {exc}"
    return result


def download(url: str, destination: pathlib.Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "nbshell-updater"})
    written = 0
    with urllib.request.urlopen(request, timeout=60) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            written += len(chunk)
            if written > MAX_DOWNLOAD_BYTES:
                raise ValueError(f"download exceeded {MAX_DOWNLOAD_BYTES} bytes")
            output.write(chunk)


def verify_signature(archive: pathlib.Path, bundle: pathlib.Path, version: str) -> None:
    system_cosign = pathlib.Path("/usr/bin/cosign")
    cosign = str(system_cosign) if system_cosign.is_file() else shutil.which("cosign")
    if cosign is None:
        raise ValueError("Cosign is required to verify nbshell release provenance")
    subprocess.run(
        [
            cosign,
            "verify-blob",
            str(archive),
            "--bundle",
            str(bundle),
            "--certificate-identity",
            f"{SIGNING_WORKFLOW}@refs/tags/v{version}",
            "--certificate-oidc-issuer",
            SIGNING_ISSUER,
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def safe_extract(archive: pathlib.Path, destination: pathlib.Path) -> pathlib.Path:
    destination.mkdir(parents=True, exist_ok=True)
    count = 0
    total = 0
    # Streaming mode rejects excessive member counts before tarfile has to
    # materialize every header from a compressed archive in memory.
    with tarfile.open(archive, "r|gz") as bundle:
        for member in bundle:
            count += 1
            if count > MAX_MEMBERS:
                raise ValueError(f"release archive has more than {MAX_MEMBERS} entries")
            target = destination / member.name
            if member.name.startswith("/") or destination.resolve() not in target.resolve().parents:
                raise ValueError(f"unsafe archive path: {member.name}")
            if member.issym() or member.islnk():
                raise ValueError(f"links are not allowed in release archives: {member.name}")
            if not (member.isfile() or member.isdir()):
                raise ValueError(f"unsupported archive entry type: {member.name}")
            if member.isfile():
                if member.size > MAX_MEMBER_BYTES:
                    raise ValueError(f"archive entry too large: {member.name}")
                total += member.size
                if total > MAX_TOTAL_EXTRACT_BYTES:
                    raise ValueError("release archive exceeds the uncompressed size limit")
            bundle.extract(member, destination, filter="data")
    entries = list(destination.iterdir())
    if len(entries) != 1 or not entries[0].is_dir() or not (entries[0] / "install.sh").is_file():
        raise ValueError("release archive does not contain one installable nbshell tree")
    return entries[0]


def install(channel: str, assume_yes: bool) -> int:
    info = status(channel)
    print(f"nbshell {info['current']} → {info['latest']} ({channel} channel)")
    if not info["ok"]:
        print(info["error"], file=sys.stderr)
        return 1
    if not info["available"]:
        print("nbshell is already up to date.")
        return 0
    if not info["installable"]:
        print(info["error"], file=sys.stderr)
        return 1
    if info["url"]:
        print(f"Release notes: {info['url']}")
    if not assume_yes and input("Download, verify, and install this release? [y/N] ").strip().lower() not in {"y", "yes"}:
        print("Update cancelled.")
        return 0

    with tempfile.TemporaryDirectory(prefix="nbshell-update-") as temp_name:
        temp = pathlib.Path(temp_name)
        archive = temp / f"nbshell-{info['latest']}.tar.gz"
        checksum_file = archive.with_suffix(archive.suffix + ".sha256")
        bundle_file = archive.with_suffix(archive.suffix + ".sigstore.json")
        print("Downloading release, checksum, and provenance bundle …")
        download(info["assetUrl"], archive)
        download(info["checksumUrl"], checksum_file)
        download(info["bundleUrl"], bundle_file)
        verify_signature(archive, bundle_file, info["latest"])
        expected = checksum_file.read_text(encoding="utf-8").split()[0].lower()
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()
        if not re.fullmatch(r"[0-9a-f]{64}", expected) or actual != expected:
            raise ValueError("SHA-256 verification failed; nothing was installed")
        print("Signature and checksum verified. Starting the nbshell installer …")
        source = safe_extract(archive, temp / "source")
        subprocess.run(["bash", str(source / "install.sh")], check=True)
    print(f"nbshell {info['latest']} installed successfully.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Check and install published nbshell releases")
    parser.add_argument("command", nargs="?", choices=("check", "install"), default="check")
    parser.add_argument("--channel", choices=("stable", "beta"), default="beta")
    parser.add_argument("--yes", action="store_true", help="skip the terminal confirmation")
    args = parser.parse_args()
    if args.command == "check":
        print(json.dumps(status(args.channel), ensure_ascii=False))
        return 0
    try:
        return install(args.channel, args.yes)
    except (OSError, ValueError, subprocess.CalledProcessError, urllib.error.URLError) as exc:
        print(f"Update failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
