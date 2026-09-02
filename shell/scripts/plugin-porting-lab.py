#!/usr/bin/env python3
"""Read-only compatibility analysis for public Omarchy and GitHub plugins."""

from __future__ import annotations

import argparse
import datetime as dt
import html
import ipaddress
import json
import re
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any

SCHEMA_VERSION = 1
TIMEOUT_SECONDS = 8
MAX_REDIRECTS = 2
MAX_FILES = 90
MAX_FILE_BYTES = 220_000
MAX_TOTAL_BYTES = 1_800_000
USER_AGENT = "nbshell-porting-lab/1"
MARKETPLACE_HOSTS = {"omarchyplugins.com", "www.omarchyplugins.com", "plugins.omarchy.org"}
FETCH_HOSTS = MARKETPLACE_HOSTS | {"api.github.com", "raw.githubusercontent.com"}
TEXT_SUFFIXES = {
    ".qml", ".js", ".mjs", ".py", ".sh", ".json", ".md", ".toml",
    ".yaml", ".yml", ".desktop", ".service", ".txt",
}
IMPORTANT_NAMES = {"license", "copying", "readme", "manifest.json", "plugin.json"}


class AnalysisError(RuntimeError):
    pass


@dataclass(frozen=True)
class GitHubSource:
    owner: str
    repo: str
    ref: str = ""
    prefix: str = ""
    marketplace: dict[str, Any] | None = None

    @property
    def repository_url(self) -> str:
        return f"https://github.com/{self.owner}/{self.repo}"


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    def __init__(self) -> None:
        super().__init__()
        self.count = 0

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        self.count += 1
        if self.count > MAX_REDIRECTS:
            raise AnalysisError("The source redirected too many times.")
        validate_fetch_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _host_is_public(host: str) -> bool:
    try:
        addresses = {item[4][0] for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)}
    except socket.gaierror as exc:
        raise AnalysisError(f"Could not resolve {host}.") from exc
    if not addresses:
        return False
    for address in addresses:
        ip = ipaddress.ip_address(address)
        if not ip.is_global:
            return False
    return True


def validate_fetch_url(url: str) -> urllib.parse.ParseResult:
    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https":
        raise AnalysisError("Only HTTPS sources are supported.")
    if host not in FETCH_HOSTS:
        raise AnalysisError(f"Network access to {host or 'this host'} is not allowed.")
    if not _host_is_public(host):
        raise AnalysisError("Local and private network addresses are not allowed.")
    return parsed


def fetch_bytes(url: str, limit: int = MAX_FILE_BYTES) -> bytes:
    validate_fetch_url(url)
    opener = urllib.request.build_opener(SafeRedirectHandler())
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json, application/json, text/plain;q=0.9, */*;q=0.2"},
    )
    try:
        with opener.open(request, timeout=TIMEOUT_SECONDS) as response:
            data = response.read(limit + 1)
    except AnalysisError:
        raise
    except urllib.error.HTTPError as exc:
        if exc.code == 403 and "api.github.com" in url:
            raise AnalysisError("GitHub API access is rate-limited. Try again later.") from exc
        raise AnalysisError(f"The source returned HTTP {exc.code}.") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise AnalysisError("The source could not be reached within the time limit.") from exc
    if len(data) > limit:
        raise AnalysisError("A remote response exceeded the analysis size limit.")
    return data


def fetch_json(url: str, limit: int = MAX_FILE_BYTES) -> Any:
    try:
        return json.loads(fetch_bytes(url, limit).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AnalysisError("A remote JSON response was invalid.") from exc


def parse_github_url(url: str) -> GitHubSource:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() not in {"github.com", "www.github.com"}:
        raise AnalysisError("Enter a public HTTPS GitHub repository or Omarchy marketplace link.")
    parts = [urllib.parse.unquote(part) for part in parsed.path.split("/") if part]
    if len(parts) < 2:
        raise AnalysisError("The GitHub URL must include an owner and repository.")
    owner, repo = parts[0], parts[1].removesuffix(".git")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", owner) or not re.fullmatch(r"[A-Za-z0-9_.-]+", repo):
        raise AnalysisError("The GitHub owner or repository name is invalid.")
    ref = ""
    prefix = ""
    if len(parts) > 2:
        if parts[2] != "tree" or len(parts) < 4:
            raise AnalysisError("Use a repository URL or a GitHub /tree/<ref>/<path> URL.")
        ref = parts[3]
        prefix = "/".join(parts[4:]).strip("/")
    return GitHubSource(owner=owner, repo=repo, ref=ref, prefix=prefix)


def resolve_marketplace_url(url: str) -> GitHubSource:
    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or host not in MARKETPLACE_HOSTS:
        raise AnalysisError("This is not a supported Omarchy marketplace URL.")
    plugin_id = urllib.parse.parse_qs(parsed.query).get("id", [""])[0].strip()
    if not plugin_id and parsed.fragment:
        plugin_id = urllib.parse.parse_qs(parsed.fragment).get("id", [""])[0].strip()
    if not plugin_id:
        path_parts = [part for part in parsed.path.split("/") if part]
        if path_parts and path_parts[-1] not in {"index.html", "plugin.html", "plugins"}:
            plugin_id = urllib.parse.unquote(path_parts[-1])
    if not plugin_id:
        raise AnalysisError("Open a specific marketplace plugin page before analyzing it.")
    catalog_url = f"https://{host}/catalog.json"
    document = fetch_json(catalog_url, 8_000_000)
    plugins = document.get("plugins", []) if isinstance(document, dict) else []
    record = next((item for item in plugins if str(item.get("id", "")) == plugin_id), None)
    if not isinstance(record, dict):
        raise AnalysisError(f"Marketplace plugin '{plugin_id}' was not found in the current catalog.")
    source = parse_github_url(str(record.get("repo", "")))
    manifest_path = str(record.get("manifestPath", "")).strip("/")
    prefix = manifest_path.rsplit("/", 1)[0] if "/" in manifest_path else ""
    ref = str(record.get("upstreamObservedCommit") or record.get("listingValidatedCommit") or "")
    return GitHubSource(source.owner, source.repo, ref=ref, prefix=prefix, marketplace=record)


def resolve_source(url: str) -> GitHubSource:
    value = url.strip()
    if len(value) > 2048:
        raise AnalysisError("The source URL is too long.")
    parsed = urllib.parse.urlparse(value)
    host = (parsed.hostname or "").lower()
    if host in MARKETPLACE_HOSTS:
        return resolve_marketplace_url(value)
    return parse_github_url(value)


def _api_url(path: str) -> str:
    return "https://api.github.com" + path


def fetch_repository(source: GitHubSource) -> tuple[dict[str, str], dict[str, Any]]:
    metadata = fetch_json(_api_url(f"/repos/{source.owner}/{source.repo}"), 500_000)
    if not isinstance(metadata, dict):
        raise AnalysisError("GitHub returned invalid repository metadata.")
    ref = source.ref or str(metadata.get("default_branch") or "")
    if not ref:
        raise AnalysisError("The repository has no analyzable default branch.")
    tree = fetch_json(_api_url(f"/repos/{source.owner}/{source.repo}/git/trees/{urllib.parse.quote(ref, safe='')}?recursive=1"), 8_000_000)
    if not isinstance(tree, dict) or not isinstance(tree.get("tree"), list):
        raise AnalysisError("GitHub did not return a repository tree.")
    prefix = source.prefix.strip("/")
    candidates: list[tuple[str, int]] = []
    for item in tree["tree"]:
        if item.get("type") != "blob":
            continue
        path = str(item.get("path", ""))
        if prefix and path != prefix and not path.startswith(prefix + "/"):
            continue
        relative = path[len(prefix):].lstrip("/") if prefix else path
        name = relative.rsplit("/", 1)[-1].lower()
        suffix = "." + name.rsplit(".", 1)[-1] if "." in name else ""
        size = int(item.get("size") or 0)
        if size <= MAX_FILE_BYTES and (suffix in TEXT_SUFFIXES or name in IMPORTANT_NAMES):
            candidates.append((path, size))
    candidates.sort(key=lambda pair: (
        0 if pair[0].lower().endswith("manifest.json") else
        1 if pair[0].rsplit("/", 1)[-1].lower().startswith("readme") else
        2 if pair[0].rsplit("/", 1)[-1].lower() in {"license", "copying"} else 3,
        pair[0],
    ))
    files: dict[str, str] = {}
    total = 0
    for path, size in candidates[:MAX_FILES]:
        if total + size > MAX_TOTAL_BYTES:
            break
        raw = f"https://raw.githubusercontent.com/{source.owner}/{source.repo}/{urllib.parse.quote(ref, safe='')}/{urllib.parse.quote(path)}"
        try:
            data = fetch_bytes(raw, MAX_FILE_BYTES)
            text = data.decode("utf-8")
        except (AnalysisError, UnicodeDecodeError):
            continue
        relative = path[len(prefix):].lstrip("/") if prefix else path
        files[relative] = text
        total += len(data)
    if not files:
        raise AnalysisError("No supported text source files were found at this repository location.")
    info = {
        "ref": ref,
        "prefix": prefix,
        "default_branch": metadata.get("default_branch", ""),
        "repository_description": metadata.get("description") or "",
        "truncated_tree": bool(tree.get("truncated")),
        "candidate_count": len(candidates),
        "analyzed_count": len(files),
        "analyzed_bytes": total,
    }
    return files, info


def _manifest(files: dict[str, str]) -> tuple[str, dict[str, Any] | None]:
    paths = sorted((path for path in files if path.lower().endswith("manifest.json")), key=lambda value: (value.count("/"), value))
    for path in paths:
        try:
            value = json.loads(files[path])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return path, value
    return "", None


def _locations(files: dict[str, str], pattern: re.Pattern[str], limit: int = 4) -> list[str]:
    found: list[str] = []
    for path, text in files.items():
        for number, line in enumerate(text.splitlines(), 1):
            if pattern.search(line):
                found.append(f"{path}:{number}")
                if len(found) >= limit:
                    return found
    return found


def analyze_files(source: GitHubSource, files: dict[str, str], info: dict[str, Any]) -> dict[str, Any]:
    manifest_path, manifest = _manifest(files)
    combined = "\n".join(files.values())
    lowered = combined.lower()
    findings: list[dict[str, Any]] = []

    def add(rule_id: str, severity: str, title: str, detail: str, hint: str, locations: list[str] | None = None) -> None:
        findings.append({
            "rule_id": rule_id,
            "severity": severity,
            "title": title,
            "detail": detail,
            "hint": hint,
            "locations": locations or [],
        })

    schema = manifest.get("schemaVersion") if manifest else None
    if manifest is None:
        add("manifest-missing", "warning", "No plugin manifest found", "The analyzer could not establish an explicit runtime contract.", "Identify the actual plugin root and create a nbshell manifest v2 before porting.")
    elif schema == 2 and isinstance(manifest.get("kinds"), list):
        add("nbshell-manifest-v2", "positive", "nbshell manifest v2 detected", "The declared runtime kinds can map directly to the nbshell host contract.", "Validate the source with nbshell's manifest and strict design checks after adaptation.", [manifest_path])
    else:
        add("foreign-manifest", "info", "Foreign or legacy manifest", "The manifest does not declare the nbshell v2 contract.", "Map its component type to bar-widget, panel, overlay, or service and generate a fresh nbshell manifest.", [manifest_path])

    rules = [
        ("hyprland-api", "warning", "Hyprland integration", r"\bhyprctl\b|\.config/hypr|hyprland", "Replace compositor commands and workspace assumptions with Umbriel IPC or standard Wayland protocols."),
        ("niri-api", "warning", "Niri-specific integration", r"\bniri\s+msg\b|\.config/niri|niri-ipc", "Replace Niri-specific calls with Umbriel IPC or standard Wayland protocols."),
        ("omarchy-shell-api", "warning", "Omarchy shell coupling", r"import\s+qs\.(Services|Modules|Config)|\bOmarchy\w*\b", "Keep portable data logic, but remap shell services and lifecycle to public nbshell APIs."),
        ("portable-ui-api", "positive", "Portable UI imports", r"import\s+qs\.(Commons|Ui)\b", "Reuse compatible controls where practical, then run the strict nbshell design check."),
        ("nbshell-ui-api", "positive", "Native nbshell UI imports", r"import\s+qs\.(Common|Widgets)\b", "Preserve the public imports and validate the component lifecycle."),
        ("process-execution", "info", "External process use", r"\bProcess\s*\{|Quickshell\.execDetached|subprocess\.|os\.system\(|child_process", "Declare every command dependency and pass untrusted values as separate process arguments."),
        ("network-access", "info", "Network access", r"XMLHttpRequest|\bfetch\s*\(|urllib\.|requests\.|\bcurl\b|\bwget\b", "Document endpoints, timeouts, data handling, and the visible privacy decision."),
        ("filesystem-write", "warning", "Filesystem mutation", r"writeTextFile|open\([^\n]*['\"]w|\.write_text\(|FileMode\.Write|os\.remove\(|shutil\.", "Constrain writes to XDG state/config/cache locations and make disable/remove behavior explicit."),
        ("dynamic-code", "danger", "Dynamic code execution", r"\beval\s*\(|new\s+Function\s*\(|\bexec\s*\(", "Do not port dynamic execution. Replace it with explicit parsing and typed operations."),
        ("privileged-install", "danger", "Privileged or implicit installation", r"\bsudo\b|\bpacman\s+-S|\byay\s+-S|systemctl\s+enable|curl[^\n]*\|\s*(?:ba)?sh", "Remove automatic installation and privilege changes. Declare dependencies for an explicit user-controlled setup flow."),
        ("security-boundary", "danger", "Security-boundary replacement", r"\bpkexec\b|polkit-agent|polkit\.addRule|/etc/polkit|\blockscreen\b|\block\s*screen\b|\bgreetd\b|pam\.d", "Do not ship lock, greeter, PAM, or privilege-agent replacements as a community plugin."),
        ("hardcoded-design", "info", "Private visual literals", r"#[0-9a-fA-F]{6,8}|radius\s*:\s*\d+|duration\s*:\s*\d+", "Rebuild visual constants with nbshell Theme tokens and shared controls."),
    ]
    for rule_id, severity, title, expression, hint in rules:
        pattern = re.compile(expression, re.IGNORECASE)
        inspected = files
        if severity == "danger":
            inspected = {
                path: text for path, text in files.items()
                if path.lower().endswith((".qml", ".js", ".mjs", ".py", ".sh", ".service"))
            }
        locations = _locations(inspected, pattern)
        if locations:
            add(rule_id, severity, title, f"Matched in {len(locations)} representative location(s).", hint, locations)

    license_declared = str((manifest or {}).get("license") or "").strip()
    has_license_file = any(path.rsplit("/", 1)[-1].lower() in {"license", "license.md", "license.txt", "copying"} for path in files)
    marketplace_license = str((source.marketplace or {}).get("license") or "").strip()
    if not license_declared and not has_license_file and marketplace_license.lower() in {"", "see repository"}:
        add("license-unclear", "warning", "License is unclear", "No reusable-code license was confirmed in the analyzed source.", "Treat the repository as idea-only until a compatible license is verified.")

    marketplace = source.marketplace or {}
    name = str(marketplace.get("name") or (manifest or {}).get("name") or source.repo)
    description = str(marketplace.get("description") or (manifest or {}).get("description") or info.get("repository_description") or "")
    context_text = f"{name} {description} {' '.join(map(str, marketplace.get('tags', [])))}".lower()
    duplicates = [
        (r"notification", "Notifications & Clipboard"),
        (r"clipboard", "Notifications & Clipboard"),
        (r"volume|audio control|pipewire", "Volume and application audio"),
        (r"music|youtube music|media player", "nbshell music and media"),
        (r"calendar", "Dashboard calendar"),
        (r"task|todo", "Tasks"),
        (r"theme|wallpaper", "Theme and wallpaper picker"),
        (r"screenshot|screen record|capture", "Capture"),
        (r"tailscale", "Tailscale"),
        (r"emoji", "Emoji picker"),
        (r"ai usage|model usage|token usage", "AI usage"),
        (r"system monitor|cpu|memory", "System load"),
        (r"workspace overview|workspace switch", "Workspaces"),
    ]
    existing = []
    for expression, feature in duplicates:
        if re.search(expression, context_text):
            existing.append(feature)
    existing = list(dict.fromkeys(existing))
    if existing:
        add("existing-capability", "info", "Potential nbshell overlap", "Related built-in capability: " + ", ".join(existing), "Compare the missing user outcome before creating a second implementation.")

    kinds: list[str] = []
    if manifest and isinstance(manifest.get("kinds"), list):
        kinds = [str(item) for item in manifest["kinds"] if str(item) in {"bar-widget", "panel", "overlay", "service"}]
    if not kinds:
        kind = str(marketplace.get("kind") or "").lower()
        mapping = {"widget": "bar-widget", "bar widget": "bar-widget", "panel": "panel", "overlay": "overlay", "service": "service"}
        if kind in mapping:
            kinds = [mapping[kind]]
        elif any(path.lower().endswith("barwidget.qml") for path in files):
            kinds = ["bar-widget"]
        elif any(path.lower().endswith("panel.qml") for path in files):
            kinds = ["panel"]
        elif any(path.lower().endswith("overlay.qml") for path in files):
            kinds = ["overlay"]

    danger_count = sum(item["severity"] == "danger" for item in findings)
    warning_count = sum(item["severity"] == "warning" for item in findings)
    has_portable_ui = any(item["rule_id"] in {"portable-ui-api", "nbshell-ui-api"} for item in findings)
    shell_coupled = any(item["rule_id"] in {"hyprland-api", "niri-api", "omarchy-shell-api"} for item in findings)
    has_backend = any(path.endswith((".py", ".sh", ".js", ".mjs")) for path in files)

    if danger_count:
        recommendation = "not-recommended"
        recommendation_label = "Not recommended as-is"
        summary = "Security-sensitive behavior must be removed before any port is considered."
    elif existing and len(existing) >= 1:
        recommendation = "compare-existing"
        recommendation_label = "Compare with existing nbshell feature"
        summary = "Start from the missing user outcome, not from a duplicate code port."
    elif has_portable_ui and not shell_coupled:
        recommendation = "native-port"
        recommendation_label = "Native port possible"
        summary = "The source has a useful portable base and can be adapted to the nbshell plugin contract."
    elif has_backend:
        recommendation = "backend-reuse"
        recommendation_label = "Reuse backend, rebuild UI"
        summary = "Keep narrowly licensed data or protocol logic and rebuild shell integration with nbshell primitives."
    else:
        recommendation = "rebuild"
        recommendation_label = "Rebuild from the idea"
        summary = "The product idea is more reusable than the current implementation."

    score = 100
    score -= danger_count * 35
    score -= warning_count * 12
    if schema != 2:
        score -= 12
    if not kinds:
        score -= 8
    if info.get("truncated_tree") or info.get("analyzed_count", 0) < min(3, info.get("candidate_count", 0)):
        score -= 8
    score = max(0, min(100, score))
    effort = "low" if score >= 80 and not shell_coupled else "medium" if score >= 45 and danger_count == 0 else "high"
    confidence = "high" if manifest is not None and info.get("analyzed_count", 0) >= 3 and not info.get("truncated_tree") else "medium"
    if manifest is None or info.get("analyzed_count", 0) < 2:
        confidence = "low"
    confidence_note = (
        f"Static review of {info.get('analyzed_count', len(files))} text files; code was not executed. "
        "Runtime behavior, generated files, private dependencies, and intent cannot be proven by this report."
    )

    plan: list[str] = []
    if existing:
        plan.append("Compare the requested outcome with the existing " + ", ".join(existing) + " capability and define the real gap.")
    if danger_count:
        plan.append("Remove every dynamic, privileged, or security-boundary operation before re-evaluating the source.")
    plan.append("Choose the smallest nbshell runtime contract" + (": " + ", ".join(kinds) if kinds else " (bar-widget, panel, overlay, or service)") + ".")
    if shell_coupled:
        plan.append("Replace Omarchy and compositor-specific services with public nbshell APIs, Umbriel IPC, or standard Wayland protocols.")
    if has_backend:
        plan.append("Separate reusable data/protocol logic from shell UI and process control; keep only license-compatible parts.")
    plan.append("Generate a fresh nbshell manifest v2 and rebuild visible UI with qs.Common and qs.Widgets.")
    plan.append("Run plugin validation, strict design checks, focused tests, and a manual dark/light keyboard review before enabling it.")

    reusable = []
    if has_backend:
        reusable.append("Data and protocol logic, after license and side-effect review")
    if has_portable_ui:
        reusable.append("Public qs.Commons / qs.Ui component structure")
    if manifest:
        reusable.append("Plugin metadata as a migration reference")
    if not reusable:
        reusable.append("Product idea and user workflow only")

    replace = []
    if shell_coupled:
        replace.append("Omarchy and compositor integration")
    if any(item["rule_id"] == "hardcoded-design" for item in findings):
        replace.append("Private colors, metrics, and motion values")
    if schema != 2:
        replace.append("Manifest and lifecycle contract")
    if danger_count:
        replace.append("Privileged or dynamic execution paths")

    report = {
        "schema_version": SCHEMA_VERSION,
        "analyzed_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "source": {
            "input_kind": "omarchy-marketplace" if source.marketplace else "github",
            "repository": source.repository_url,
            "ref": info.get("ref", ""),
            "path": info.get("prefix", ""),
            "plugin_id": marketplace.get("id", ""),
        },
        "plugin": {
            "name": html.unescape(name),
            "description": html.unescape(description),
            "manifest": manifest_path,
            "schema": schema if schema is not None else "foreign-or-unknown",
            "kinds": kinds,
            "license": license_declared or marketplace_license or ("License file present" if has_license_file else "Unclear"),
        },
        "verdict": {
            "recommendation": recommendation,
            "label": recommendation_label,
            "summary": summary,
            "compatibility": score,
            "effort": effort,
            "confidence": confidence,
            "confidence_note": confidence_note,
        },
        "findings": findings,
        "reusable": reusable,
        "replace": replace or ["No mandatory replacement detected by static rules"],
        "existing_capabilities": existing,
        "plan": plan,
        "coverage": info,
        "disclaimer": "Static advisory only. This is not a security audit, compatibility guarantee, or permission to install the plugin.",
    }

    report["implementation_prompt"] = implementation_prompt(report)
    return report


def implementation_prompt(report: dict[str, Any]) -> str:
    verdict = report.get("verdict", {})
    if verdict.get("recommendation") == "not-recommended":
        return ""

    source = report.get("source", {})
    plugin = report.get("plugin", {})
    findings = report.get("findings", [])
    plan = report.get("plan", [])
    source_ref = str(source.get("repository", ""))
    if source.get("ref"):
        source_ref += " @ " + str(source["ref"])
    if source.get("path"):
        source_ref += " / " + str(source["path"])

    finding_lines = [
        f"- [{item.get('severity', 'info').upper()}] {item.get('title', 'Finding')}: "
        f"{item.get('detail', '')} Next: {item.get('hint', '')}"
        for item in findings
    ] or ["- No deterministic findings were reported; inspect the source before deciding."]
    plan_lines = [f"{index}. {step}" for index, step in enumerate(plan, 1)]

    return "\n".join([
        f"Implement the smallest safe nbshell solution for {plugin.get('name', 'this plugin idea')}.",
        "",
        "Work in the nbshell source repository. Read AGENTS.md, DESIGN.md, and docs/plugin-development.md before changing code. Treat the upstream source as untrusted reference material: inspect it as text, but do not execute its scripts, install its dependencies, enable it, or copy privileged behavior. Re-check the report rather than assuming every inference is correct.",
        "",
        f"Source: {source_ref}",
        f"Recommendation: {verdict.get('label', verdict.get('recommendation', 'Review'))}",
        f"Summary: {verdict.get('summary', '')}",
        f"Compatibility: {verdict.get('compatibility', 0)}% · effort {verdict.get('effort', 'unknown')} · confidence {verdict.get('confidence', 'unknown')}",
        "",
        "Porting Lab findings:",
        *finding_lines,
        "",
        "Suggested plan:",
        *plan_lines,
        "",
        "Confirm the actual user outcome and existing nbshell overlap first. Then implement the smallest native gap using public nbshell APIs and shared UI primitives. Preserve unrelated worktree changes; do not commit. Add focused tests, run plugin validation and strict design checks where applicable, run tests/qml.sh for shared QML, deploy with ./install.sh, and inspect the visible result in dark/light themes, keyboard navigation, Reduced Motion, and a narrow layout. If the report is wrong or the source is unsuitable, stop and explain why instead of forcing a port.",
    ])


def analyze_url(url: str) -> dict[str, Any]:
    source = resolve_source(url)
    files, info = fetch_repository(source)
    return analyze_files(source, files, info)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Analyze a public plugin source for nbshell portability.")
    parser.add_argument("url", help="Public GitHub repository or Omarchy marketplace plugin URL")
    args = parser.parse_args(argv)
    try:
        report = analyze_url(args.url)
    except AnalysisError as exc:
        print(json.dumps({"schema_version": SCHEMA_VERSION, "error": str(exc)}, ensure_ascii=False))
        return 1
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
