#!/usr/bin/env python3
"""Reproduce the tested Umbriel commit from public source and the bundled patch."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def prepare(destination, recipe, root=ROOT):
    def git(*args, data=None):
        return subprocess.check_output(['git', '-C', str(destination), *args], input=data, timeout=180).decode().strip()
    patch = (root / recipe['patch']).read_bytes()
    commit = (root / recipe['commit']).read_bytes()
    if hashlib.sha256(patch).hexdigest() != recipe['patchSha256']:
        raise ValueError('Umbriel patch checksum mismatch')
    digest = hashlib.sha1(b'commit ' + str(len(commit)).encode() + b'\0' + commit).hexdigest()
    if not commit.startswith(('tree ' + recipe['tree'] + '\nparent ' + recipe['baseRevision'] + '\n').encode()):
        raise ValueError('Umbriel commit tree or parent mismatch')
    if digest != recipe['revision']:
        raise ValueError('Umbriel commit object mismatch')
    if destination.exists():
        if not (destination / '.git').is_dir():
            raise ValueError('Source destination must be a standalone Git checkout')
        if git('status', '--porcelain'):
            raise ValueError('Source checkout has local changes; refusing to overwrite them')
    else:
        destination.mkdir(parents=True)
        subprocess.run(['git', 'init', '-q', str(destination)], check=True)
    if 'origin' not in git('remote').splitlines():
        git('remote', 'add', 'origin', recipe['repository'])
    # Always contact the explicit public URL, even if an existing origin differs.
    git('fetch', '--no-tags', recipe['repository'], recipe['baseRevision'])
    git('checkout', '--detach', recipe['baseRevision'])
    git('apply', '--check', '--index', '-', data=patch)
    git('apply', '--index', '-', data=patch)
    if git('write-tree') != recipe['tree']:
        raise ValueError('Patched Umbriel tree differs from the tested source')
    # Import immutable original commit metadata only after recreating its tree.
    # This does not create a remote branch or rely on the local commit being hosted.
    if git('hash-object', '-t', 'commit', '-w', '--stdin', data=commit) != recipe['revision']:
        raise ValueError('Reconstructed Umbriel revision mismatch')
    git('checkout', '--detach', recipe['revision'])
    git('submodule', 'update', '--init', '--recursive')
    if git('status', '--porcelain', '--untracked-files=no'):
        raise ValueError('Prepared Umbriel source is not clean')
    return {'revision': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}')}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    options = parser.parse_args()
    print(json.dumps(prepare(options.destination, json.loads((ROOT / 'umbriel/source.json').read_text()))))
