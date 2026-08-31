#!/usr/bin/env python3
"""Advisory design-contract checks for nbshell QML plugins."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys

ALLOW = "nbshell-design: allow-"
COLOR_TARGET = re.compile(
    r"(?:\b(?:readonly\s+)?property\s+color\s+\w+\s*:|\b(?:color|border\.color)\s*:)"
)
QUOTED_COLOR_ANYWHERE = re.compile(r"[\"'`](?:#[0-9A-Fa-f]{3,8}|[A-Za-z][A-Za-z0-9_-]*)[\"'`]")
COLOR_FUNCTION_ANYWHERE = re.compile(r"(?:(?:Qt\.)?(?:rgb|rgba|hsla|hsva)|Qt\.color)\s*\(")
DURATION_LITERAL = re.compile(r"\bduration\s*:\s*\d+")
PIXEL_LITERAL = re.compile(r"\b(?:font\.pixelSize|radius|spacing)\s*:\s*\d+(?:\.\d+)?\b")


def strip_comments(text: str) -> str:
    """Replace QML comments with spaces while preserving strings and line numbers."""
    output: list[str] = []
    index = 0
    block = False
    quote = ""
    escaped = False
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""
        if block:
            if char == "*" and next_char == "/":
                output.extend((" ", " "))
                index += 2
                block = False
            else:
                output.append("\n" if char == "\n" else " ")
                index += 1
            continue
        if quote:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            index += 1
            continue
        if char in {'"', "'", "`"}:
            quote = char
            output.append(char)
            index += 1
        elif char == "/" and next_char == "/":
            output.extend((" ", " "))
            index += 2
            while index < len(text) and text[index] != "\n":
                output.append(" ")
                index += 1
        elif char == "/" and next_char == "*":
            output.extend((" ", " "))
            index += 2
            block = True
        else:
            output.append(char)
            index += 1
    return "".join(output)


def mask_strings(text: str) -> str:
    """Replace quoted QML strings with spaces while preserving line numbers."""
    output: list[str] = []
    quote = ""
    escaped = False
    for char in text:
        if quote:
            output.append("\n" if char == "\n" else " ")
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
        elif char in {'"', "'", "`"}:
            quote = char
            output.append(" ")
        else:
            output.append(char)
    return "".join(output)


def mask_regex_literals(text: str) -> str:
    """Mask JavaScript regex literals so their example text is not QML structure."""
    output = list(text)
    index = 0
    previous = ""
    while index < len(text):
        char = text[index]
        if char.isspace():
            index += 1
            continue
        if char != "/" or previous not in "=(:,[!&|?;{":
            previous = char
            index += 1
            continue
        start = index
        index += 1
        escaped = False
        character_class = False
        while index < len(text):
            current = text[index]
            if current == "\n" and not escaped:
                break
            if escaped:
                escaped = False
            elif current == "\\":
                escaped = True
            elif current == "[":
                character_class = True
            elif current == "]":
                character_class = False
            elif current == "/" and not character_class:
                index += 1
                while index < len(text) and text[index].isalpha():
                    index += 1
                for position in range(start, index):
                    if output[position] != "\n":
                        output[position] = " "
                break
            index += 1
        previous = " "
    return "".join(output)


def has_root_member(structural: str, pattern: str) -> bool:
    depth = 0
    depths = [0] * (len(structural) + 1)
    for index, char in enumerate(structural):
        depths[index] = depth
        if char == "{":
            depth += 1
        elif char == "}":
            depth = max(0, depth - 1)
    return any(depths[match.start()] == 1 for match in re.finditer(pattern, structural))


def comment_allows(original: str, code: str, suffix: str) -> bool:
    marker = ALLOW + suffix
    start = 0
    while True:
        index = original.find(marker, start)
        if index < 0:
            return False
        if not code[index:index + len(marker)].strip():
            return True
        start = index + len(marker)


def findings_for(path: pathlib.Path) -> list[tuple[int, str, str]]:
    original = path.read_text(encoding="utf-8")
    code = strip_comments(original)
    structural = mask_regex_literals(mask_strings(code))
    original_lines = original.splitlines()
    code_lines = code.splitlines()
    findings: list[tuple[int, str, str]] = []

    def line_number(index: int) -> int:
        return structural.count("\n", 0, index) + 1

    def allowed(number: int, suffix: str) -> bool:
        index = number - 1
        return index < len(original_lines) and index < len(code_lines) \
            and comment_allows(original_lines[index], code_lines[index], suffix)

    for match in COLOR_TARGET.finditer(structural):
        value_index = match.end()
        while value_index < len(code) and code[value_index].isspace():
            value_index += 1
        value_line_end = code.find("\n", value_index)
        if value_line_end < 0:
            value_line_end = len(code)
        expression = code[value_index:value_line_end]
        structural_expression = structural[value_index:value_line_end]
        if not (QUOTED_COLOR_ANYWHERE.search(expression)
                or COLOR_FUNCTION_ANYWHERE.search(structural_expression)):
            continue
        target_line = line_number(match.start())
        value_line = line_number(value_index)
        if not (allowed(target_line, "hardcoded-color") or allowed(value_line, "hardcoded-color")):
            findings.append((value_line, "hardcoded-color", "use Theme/Color semantic roles"))

    for match in DURATION_LITERAL.finditer(structural):
        number = line_number(match.start())
        if not allowed(number, "hardcoded-duration"):
            findings.append((number, "hardcoded-duration", "use Theme motion tokens"))
    for match in PIXEL_LITERAL.finditer(structural):
        number = line_number(match.start())
        if not allowed(number, "fixed-metric"):
            findings.append((number, "fixed-metric", "use Theme/Style typography or spacing tokens"))
    return findings


def safe_entrypoint(directory: pathlib.Path, value: object) -> pathlib.Path | None:
    if not isinstance(value, str) or not value or os.path.isabs(value):
        return None
    candidate = directory / value
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(directory)
    except (OSError, ValueError):
        return None
    if candidate.is_symlink() or not resolved.is_file():
        return None
    return resolved


def entrypoint_findings(directory: pathlib.Path, manifest: dict) -> tuple[list[tuple[pathlib.Path, int, str, str]], list[str]]:
    output: list[tuple[pathlib.Path, int, str, str]] = []
    errors: list[str] = []
    entry_points = manifest.get("entryPoints", {})
    kinds = manifest.get("kinds", [])
    if not isinstance(entry_points, dict) or not isinstance(kinds, list):
        return output, ["manifest kinds and entryPoints must be valid before design checking"]
    kind_keys = {"bar-widget": "barWidget", "panel": "panel", "overlay": "overlay"}
    for kind in kinds:
        key = kind_keys.get(kind)
        if not key or key not in entry_points:
            continue
        path = safe_entrypoint(directory, entry_points[key])
        if path is None:
            errors.append(f"unsafe or missing entry point: {entry_points[key]}")
            continue
        text = strip_comments(path.read_text(encoding="utf-8"))
        structural_code = mask_regex_literals(mask_strings(text))
        if not re.search(r"^\s*import qs\.(?:Common|Commons)\b", structural_code, re.MULTILINE):
            output.append((path, 1, "missing-theme-import", "import qs.Common or qs.Commons"))
        if not re.search(r"^\s*import qs\.(?:Widgets|Ui)\b", structural_code, re.MULTILINE):
            output.append((path, 1, "missing-ui-import", "use the shared nbshell UI primitives"))
        if kind in {"panel", "overlay"}:
            if not has_root_member(structural_code, r"\bfunction\s+open\s*\("):
                output.append((path, 1, "missing-open", "panel and overlay entry points expose open(payloadJson)"))
            if not has_root_member(structural_code, r"\bfunction\s+close\s*\("):
                output.append((path, 1, "missing-close", "panel and overlay entry points expose close()"))
            if "Keys.onEscapePressed" not in structural_code and "onCloseRequested" not in structural_code:
                output.append((path, 1, "missing-escape", "provide a keyboard Escape close path"))
    return output, errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("--strict", action="store_true", help="return non-zero when findings exist")
    args = parser.parse_args()

    directory = args.directory.resolve()
    manifest_path = directory / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"design-check: cannot read {manifest_path}: {exc}", file=sys.stderr)
        return 2
    if not isinstance(manifest, dict):
        print("design-check: manifest.json must contain an object", file=sys.stderr)
        return 2

    findings: list[tuple[pathlib.Path, int, str, str]] = []
    for path in sorted(directory.rglob("*.qml")):
        if ".git" in path.parts or path.is_symlink():
            continue
        findings.extend((path, line, code, message) for line, code, message in findings_for(path))
    entry_findings, errors = entrypoint_findings(directory, manifest)
    if errors:
        for error in errors:
            print(f"design-check: {error}", file=sys.stderr)
        return 2
    findings.extend(entry_findings)
    findings.sort(key=lambda item: (str(item[0]), item[1], item[2]))

    for path, line, code, message in findings:
        relative = path.relative_to(directory)
        print(f"{relative}:{line}: {code}: {message}")

    if findings:
        print(f"Design check: {len(findings)} finding(s).")
        return 1 if args.strict else 0
    print("Design check: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
