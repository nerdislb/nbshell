#!/usr/bin/env python3
"""Core and standalone login text must explicitly choose a safe format."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
# Mask strings and comments before parsing braces; inspect only own properties,
# so an explicitly formatted child cannot conceal an unsafe parent Text.
TOKENS = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|//[^\n]*|/\*[\s\S]*?\*/')
ELEMENT = re.compile(r'\b(?:Text|Label)\s*\{')


def text_blocks(source):
    masked = TOKENS.sub(lambda m: ''.join('\n' if c == '\n' else ' ' for c in m[0]), source)
    for opening in ELEMENT.finditer(masked):
        depth = 1; own = []; index = opening.end()
        while index < len(masked) and depth:
            char = masked[index]
            if char == '{': depth += 1
            elif char == '}': depth -= 1
            own.append(char if depth == 1 else ' ')
            index += 1
        yield opening, ''.join(own)


def unsafe(source, artist_links=False):
    failures = []
    for opening, body in text_blocks(source):
        plain = re.search(r'\btextFormat\s*:\s*Text\.PlainText\b', body)
        audited_links = artist_links and re.search(r'\bid\s*:\s*linkMap\b', body) and re.search(r'\btextFormat\s*:\s*Text\.StyledText\b', body)
        if not plain and not audited_links:
            failures.append(source.count('\n', 0, opening.start()) + 1)
    return failures


def main():
    assert unsafe('Text { text: "<img>"; Text { textFormat: Text.PlainText } }') == [1]
    assert unsafe('// Text {\nText { textFormat: Text.PlainText; text: "}" }') == []
    assert unsafe('Text { text: "/*"; /* textFormat: Text.PlainText */ }') == [1]
    failures = []
    for directory in ('shell', 'greeter/qml', 'plugins'):
        for path in sorted((ROOT / directory).rglob('*.qml')):
            if 'tests' in path.relative_to(ROOT).parts:
                continue
            relative = str(path.relative_to(ROOT))
            failures.extend(f'{relative}:{line}: explicit PlainText required' for line in unsafe(path.read_text(), relative == 'plugins/ytmusic/ArtistLinks.qml'))
    if failures: raise SystemExit('\n'.join(failures))
    print('Core, login, and bundled plugin text format contracts: OK')


if __name__ == '__main__': main()
