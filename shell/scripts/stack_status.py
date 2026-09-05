"""Deterministic, stdlib-only tested-stack evaluator. No probes during import/evaluate."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import stat
import subprocess
import time

COMPONENTS = ("nbshell", "quickshell", "qt", "umbriel", "portal", "platform")
STATES = ("tested", "supported", "compatible-unverified", "degraded", "unsupported", "security-blocked")
DEFAULT_MANIFEST = Path(__file__).resolve().parent.parent / "Catalog/tested-stack.json"
LIMIT = 65536
SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?")


def version(value):
    if not isinstance(value, str) or len(value) > 128:
        return None
    match = SEMVER.fullmatch(value)
    if not match:
        return None
    pre = match[4]
    if pre and any(p.isdigit() and len(p) > 1 and p[0] == "0" for p in pre.split(".")):
        return None
    # Release sorts after prerelease; numeric identifiers sort before text.
    suffix = (1,) if pre is None else (0, tuple((0, int(p)) if p.isdigit() else (1, p) for p in pre.split(".")))
    return tuple(int(match[i]) for i in (1, 2, 3)) + (suffix,)


def valid(value, kind):
    if not isinstance(value, str) or len(value) > 128:
        return False
    if kind == "version":
        return version(value) is not None
    if kind == "revision":
        return re.fullmatch(r"[0-9a-f]{40}", value) is not None
    return re.fullmatch(r"[a-z0-9_-]+:[a-z0-9_-]+", value) is not None


def load_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NONBLOCK), "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("JSON input must be a regular file")
        raw = stream.read(LIMIT + 1)
    if len(raw) > LIMIT:
        raise ValueError("JSON input too large")
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("invalid JSON constant")))


def validate_manifest(manifest):
    if not isinstance(manifest, dict) or type(manifest.get("schemaVersion")) is not int or manifest["schemaVersion"] != 1:
        raise ValueError("unsupported manifest schema")
    if type(manifest.get("manifestVersion")) is not int or manifest["manifestVersion"] < 1:
        raise ValueError("invalid manifest version")
    if version(manifest.get("nbshellVersion")) is None:
        raise ValueError("invalid nbshell version")
    rules = manifest.get("components")
    if not isinstance(rules, dict) or set(rules) != set(COMPONENTS):
        raise ValueError("invalid manifest components")
    for name in COMPONENTS:
        rule = rules[name]
        kind = "revision" if name in ("umbriel", "portal") else "platform" if name == "platform" else "version"
        if not isinstance(rule, dict) or rule.get("kind") != kind:
            raise ValueError("invalid component kind")
        if "minimum" not in rule or (rule["minimum"] is not None and (kind != "version" or version(rule["minimum"]) is None)):
            raise ValueError("invalid component minimum")
        for field in ("supported", "incompatible", "securityBlocked"):
            values = rule.get(field)
            if not isinstance(values, list) or any(not valid(v, kind) for v in values):
                raise ValueError("invalid component policy")
    stacks = manifest.get("testedStacks")
    if not isinstance(stacks, list):
        raise ValueError("invalid tested stacks")
    for stack in stacks:
        if not isinstance(stack, dict) or not isinstance(stack.get("evidence"), str) or not stack["evidence"].strip():
            raise ValueError("tested stack requires evidence")
        values = stack.get("components")
        if not isinstance(values, dict) or set(values) != set(COMPONENTS) or any(not valid(values[n], rules[n]["kind"]) for n in COMPONENTS):
            raise ValueError("tested stack must pin all components")
    return manifest


def evaluate(manifest, observed):
    """Return schema v1 status. Invalid input raises ValueError; no I/O or mutation.

    observed = {"schemaVersion": 1, "components": {name: {
        "value": str | None, "available": bool | None, "dirty": bool,
        "health": "ok" | "unknown" | "degraded"}}}
    Missing components/values mean unknown, never supported. Revision prefixes
    and dirty builds never match policy pins. Block policies take precedence.
    """
    validate_manifest(manifest)
    if not isinstance(observed, dict) or type(observed.get("schemaVersion")) is not int or observed["schemaVersion"] != 1:
        raise ValueError("unsupported observation schema")
    source = observed.get("components")
    if not isinstance(source, dict) or set(source) - set(COMPONENTS):
        raise ValueError("invalid observed components")
    result = {}
    for name in COMPONENTS:
        item = source.get(name, {})
        if not isinstance(item, dict) or set(item) - {"value", "available", "dirty", "health"}:
            raise ValueError("invalid component observation")
        value = item.get("value")
        available = item.get("available")
        dirty = item.get("dirty", False)
        health = item.get("health", "unknown")
        if (value is not None and (not isinstance(value, str) or len(value) > 128)) or (available is not None and type(available) is not bool) or type(dirty) is not bool or health not in ("ok", "unknown", "degraded"):
            raise ValueError("invalid component observation fields")
        rule = manifest["components"][name]
        well_formed = valid(value, rule["kind"])
        # Deny semver identities regardless of build metadata, including dirty
        # builds. Revision policies require exact full hashes.
        parsed = version(value) if rule["kind"] == "version" else None
        minimum = version(rule["minimum"]) if rule["minimum"] is not None else None
        def denied(field):
            return value in rule[field] or (parsed is not None and any(parsed == version(v) for v in rule[field]))
        if denied("securityBlocked"):
            state, reason = "security-blocked", "security-policy"
        elif denied("incompatible"):
            state, reason = "unsupported", "known-incompatible"
        elif parsed is not None and minimum is not None and parsed < minimum:
            state, reason = "unsupported", "below-minimum"
        elif name == "platform" and well_formed and isinstance(value, str) and not value.startswith("linux:"):
            state, reason = "unsupported", "non-linux-platform"
        elif available is False:
            state, reason = "degraded", "missing-component"
        elif health == "degraded":
            state, reason = "degraded", "functional-check-failed"
        elif not well_formed:
            state, reason = "compatible-unverified", "unknown-or-unresolved-version"
        elif dirty:
            state, reason = "compatible-unverified", "development-build"
        elif value in rule["supported"]:
            state, reason = "supported", "documented-baseline"
        else:
            state, reason = "compatible-unverified", "outside-recorded-baseline"
        # Never echo arbitrary malformed values (paths, control codes, secrets).
        result[name] = {"value": value if well_formed else None, "available": available,
                        "dirty": dirty, "health": health, "status": state, "reason": reason}
    matched = None
    for index, stack in enumerate(manifest["testedStacks"]):
        if all(result[n]["value"] == stack["components"][n] and not result[n]["dirty"]
               and result[n]["status"] in ("supported", "compatible-unverified") for n in COMPONENTS):
            matched = index
            for item in result.values():
                item.update(status="tested", reason="exact-tested-stack")
            break
    status = max((item["status"] for item in result.values()), key=STATES.index)
    return {"schemaVersion": 1, "manifestVersion": manifest["manifestVersion"],
            "nbshellVersion": manifest["nbshellVersion"], "status": status,
            "testedStack": matched, "components": result}


def bounded_probe(argv, timeout=2.0, limit=4096):
    """Read-only fixed argv callers only. Bound wall time AND output allocation.

    Drop stderr, close stdin, kill the isolated process group on timeout/overflow.
    No raw output/error details escape into diagnostic JSON.
    """
    executable = shutil.which(argv[0])
    if not executable:
        return None, "missing"
    try:
        with subprocess.Popen([executable, *argv[1:]], stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              start_new_session=True, env={"PATH": os.defpath, "LC_ALL": "C"}) as proc:
            try:
                assert proc.stdout is not None
                data = bytearray()
                deadline = time.monotonic() + timeout
                with selectors.DefaultSelector() as selector:
                    selector.register(proc.stdout, selectors.EVENT_READ)
                    while True:
                        remaining = deadline - time.monotonic()
                        if remaining <= 0 or not selector.select(remaining):
                            return None, "timeout"
                        chunk = os.read(proc.stdout.fileno(), min(4096, limit + 1 - len(data)))
                        if not chunk:
                            break
                        data.extend(chunk)
                        if len(data) > limit:
                            return None, "overflow"
                try:
                    code = proc.wait(timeout=max(0.001, deadline - time.monotonic()))
                except subprocess.TimeoutExpired:
                    return None, "timeout"
                return (data.decode("utf-8", errors="replace").strip(), "ok") if code == 0 else (None, "failed")
            finally:
                # Include descendants even when the direct process already exited.
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    except OSError:
        return None, "failed"


def probe_stack():
    """Identify local payload/executable versions, NOT running-server identity.

    The portal backend has no safe revision probe. Leave it explicitly unknown;
    never start the service or infer its revision from a source checkout.
    """
    components = {n: {"value": None, "available": None, "health": "unknown"} for n in COMPONENTS}
    # Repository VERSION and installed shell/VERSION are both supported locations.
    base = Path(__file__).resolve().parent.parent
    for path in (base / "VERSION", base.parent / "VERSION"):
        try:
            with path.open("r", encoding="utf-8") as stream:
                value = stream.read(129).strip()
            if version(value) is not None:
                components["nbshell"].update(value=value, available=True)
                break
        except (OSError, UnicodeError):
            pass
    commands = {"quickshell": ["quickshell", "--version"],
                "qt": ["/usr/lib/qt6/bin/qtpaths", "--qt-version"],
                "umbriel": ["umbriel", "--version"]}
    for name, argv in commands.items():
        text, outcome = bounded_probe(argv)
        # Missing qtpaths is missing introspection, not evidence Qt is absent.
        components[name]["available"] = False if outcome == "missing" and name != "qt" else True if outcome == "ok" else None
        if outcome == "ok" and text is not None:
            if name == "qt" and version(text) is not None:
                components[name]["value"] = text
            elif name == "quickshell":
                match = re.fullmatch(r"Quickshell ([^\s]+)(?: \([^\r\n]*\))?", text)
                if match and version(match[1]) is not None:
                    components[name]["value"] = match[1]
                    components[name]["dirty"] = "-dirty" in text
            else:
                match = re.fullmatch(r"umbriel [^\s]+ \(([0-9a-f]{40})(-dirty)?\)", text)
                if match:
                    components[name].update(value=match[1], dirty=bool(match[2]))
    try:
        with open("/etc/os-release", encoding="utf-8") as stream:
            data = stream.read(4096)
        ids = re.findall(r'^ID=(?:"([a-z0-9_-]+)"|([a-z0-9_-]+))$', data, re.M)
        if len(ids) == 1:
            components["platform"].update(value=os.uname().sysname.lower() + ":" + (ids[0][0] or ids[0][1]), available=True)
    except (OSError, UnicodeError):
        pass
    return {"schemaVersion": 1, "components": components}
