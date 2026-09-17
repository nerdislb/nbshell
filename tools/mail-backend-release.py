#!/usr/bin/env python3
"""Build evidence and verify nbshell's backend-only Mail release (no pin mutation)."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
MAIL = ROOT / "plugins/omamail"
spec = importlib.util.spec_from_file_location("mail_packaging", MAIL / "scripts/package-backend.py")
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)
ARCHES = ("x86_64", "aarch64")


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def version():
    value = packaging.check(MAIL)
    if not re.fullmatch(r"\d+\.\d+\.\d+-nbshell\.[1-9][0-9]*", value):
        raise ValueError("expected a uniquely versioned nbshell rebuild")
    return value


def verify_binary(binary, arch):
    data = binary.read_bytes()
    machine = {"x86_64": 62, "aarch64": 183}[arch]
    if data[:6] != b"\x7fELF\x02\x01" or int.from_bytes(data[18:20], "little") != machine:
        raise ValueError("backend ELF architecture mismatch")
    if "INTERP" in run("readelf", "-l", str(binary)) or "NEEDED" in run("readelf", "-d", str(binary)):
        raise ValueError("backend must be statically linked")
    # Generic CI paths are public build context; personal workstation paths are not.
    homes = re.findall(rb"/(?:home|Users)/([^/\x00\s]+)", data)
    if any(name not in (b"runner",) for name in homes):
        raise ValueError("backend contains a non-generic home path")
    if run(str(binary), "--version") != "omamail " + version():
        raise ValueError("backend version mismatch")
    run("python3", str(MAIL / "tests/test_backend_api.py"), "--binary", str(binary),
        "--expected-version", version())


def prepare(binary, arch, output):
    if platform.machine() != arch:
        raise ValueError("release proof must run natively on the target architecture")
    verify_binary(binary, arch)
    packages = tomllib.loads((MAIL / "Cargo.lock").read_text())["package"]
    rustls = [p["version"] for p in packages if p["name"] == "rustls"]
    if rustls != ["0.23.45"]:
        raise ValueError("reassess the TLS advisory before changing the approved lock")
    packaging.package(binary, arch, output)
    contract = packaging.read_api(MAIL / "backend-api.json")
    contract["releasedApiVersion"] = contract["apiVersion"]
    contract["unreleased"] = {"methods": [], "cases": []}
    (output / "backend-api.json").write_text(json.dumps(contract, indent=2) + "\n")
    (output / "backend-build.json").write_text(json.dumps(packaging.provenance(MAIL), indent=2, sort_keys=True) + "\n")
    evidence = dict(schemaVersion=1, version=version(), architecture=arch,
                    sourceCommit=run("git", "rev-parse", "HEAD", cwd=ROOT),
                    rustc=run("rustc", "--version"), target=arch + "-unknown-linux-musl",
                    binarySha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                    rustls=rustls[0], apiVersion=contract["apiVersion"],
                    workflow="mail-backend.yml", nativeContract="passed")
    (output / f"build-{arch}.json").write_text(json.dumps(evidence, indent=2) + "\n")


def assemble(inputs, output):
    output.mkdir(parents=True, exist_ok=False)
    expected = set()
    for arch in ARCHES:
        source = inputs / ("mail-" + arch)
        for name in (f"omamail-linux-{arch}.tar.gz", f"build-{arch}.json", "backend-api.json", "backend-build.json"):
            path = source / name
            if path.is_symlink() or not path.is_file() or path.stat().st_size > 25 * 1024 * 1024:
                raise ValueError("missing or oversized build artifact")
            content = path.read_bytes()
            target = output / name
            if target.exists() and target.read_bytes() != content:
                raise ValueError("native builds disagree about source or API provenance")
            target.write_bytes(content)
            expected.add(name)
        evidence = json.loads((source / f"build-{arch}.json").read_bytes())
        if (evidence["sourceCommit"] != run("git", "rev-parse", "HEAD", cwd=ROOT)
                or evidence["version"] != version() or evidence["architecture"] != arch):
            raise ValueError("native build evidence differs from release source")
    (output / "SHA256SUMS").write_text("".join(
        hashlib.sha256((output / name).read_bytes()).hexdigest() + "  " + name + "\n"
        for name in sorted(expected) if name.endswith(".tar.gz")))
    packaging.verify(output, ARCHES)
    packaging.check_provenance(MAIL, output / "backend-build.json")


def verify(directory, arch):
    packaging.verify(directory, ARCHES)
    packaging.check_provenance(MAIL, directory / "backend-build.json")
    contract = packaging.read_api(MAIL / "backend-api.json")
    contract["releasedApiVersion"] = contract["apiVersion"]
    contract["unreleased"] = {"methods": [], "cases": []}
    if packaging.read_api(directory / "backend-api.json") != contract:
        raise ValueError("published API differs from the tested source contract")
    expected = {f"omamail-linux-{a}.tar.gz" for a in ARCHES}
    checksums = {}
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([a-zA-Z0-9_.-]+)", line)
        if not match or match[2] in checksums:
            raise ValueError("malformed or duplicate release checksum")
        checksums[match[2]] = match[1]
    if set(checksums) != expected:
        raise ValueError("release checksum set differs")
    for name, digest in checksums.items():
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise ValueError("release metadata or archive hash mismatch")
    with tempfile.TemporaryDirectory(prefix="mail-published-") as temp:
        binary = Path(temp) / "omamail"
        with tarfile.open(directory / f"omamail-linux-{arch}.tar.gz") as archive:
            member, = archive.getmembers()
            if member.name != "omamail" or not member.isfile() or member.size > 25 * 1024 * 1024:
                raise ValueError("unexpected backend archive layout")
            binary.write_bytes(archive.extractfile(member).read())
        binary.chmod(0o700)
        evidence = json.loads((directory / f"build-{arch}.json").read_bytes())
        if (evidence["version"] != version() or evidence["architecture"] != arch
                or evidence["apiVersion"] != contract["apiVersion"]):
            raise ValueError("published build identity mismatch")
        if hashlib.sha256(binary.read_bytes()).hexdigest() != evidence["binarySha256"]:
            raise ValueError("binary differs from tested native build")
        verify_binary(binary, arch)
        # Run the real consumer with real HTTPS downloads in an isolated profile.
        plugin = Path(temp) / "plugin"
        (plugin / "scripts").mkdir(parents=True)
        shutil.copyfile(MAIL / "scripts/backend-runtime.py", plugin / "scripts/backend-runtime.py")
        (plugin / "backend-version").write_text(version() + "\n")
        (plugin / "backend-api.json").write_text(json.dumps(contract))
        pins = {a: checksums[f"omamail-linux-{a}.tar.gz"] for a in ARCHES}
        (plugin / "backend-release.json").write_text(json.dumps(dict(
            schemaVersion=1, version=version(), archives=pins)))
        env = {key: os.environ[key] for key in ("PATH", "LANG") if key in os.environ}
        env.update(HOME=temp, XDG_DATA_HOME=str(Path(temp) / "data"))
        installed = json.loads(run("python3", str(plugin / "scripts/backend-runtime.py"), "install", env=env))
        if installed["state"] != "ready":
            raise ValueError("real published install failed: " + installed["error"])
        if Path(installed["executable"]).read_bytes() != binary.read_bytes():
            raise ValueError("consumer installed different bytes from the public contract probe")
    print(json.dumps(dict(version=version(), architecture=arch, publishedContract="passed")))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    cmd = commands.add_parser("prepare")
    cmd.add_argument("binary", type=Path)
    cmd.add_argument("arch", choices=ARCHES)
    cmd.add_argument("output", type=Path)
    cmd = commands.add_parser("assemble")
    cmd.add_argument("inputs", type=Path)
    cmd.add_argument("output", type=Path)
    cmd = commands.add_parser("verify")
    cmd.add_argument("directory", type=Path)
    cmd.add_argument("arch", choices=ARCHES)
    commands.add_parser("version")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.binary.resolve(), args.arch, args.output)
    elif args.command == "assemble":
        assemble(args.inputs, args.output)
    elif args.command == "verify":
        verify(args.directory, args.arch)
    else:
        print(version())
