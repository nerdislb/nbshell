#!/usr/bin/env python3
"""Rebuild an unpublished commit from a remote containing only its parent."""
import copy
import hashlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
prepare = runpy.run_path(str(ROOT / 'shell/scripts/prepare-umbriel-source.py'))['prepare']

class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); source = self.root / 'source'; source.mkdir()
        def git(*args):
            return subprocess.check_output(['git', '-C', str(source), *args], stderr=subprocess.DEVNULL).strip()
        git('init', '-q'); git('config', 'user.name', 'Fixture'); git('config', 'user.email', 'fixture@example.invalid')
        (source / 'file').write_text('before\n'); git('add', '.'); git('commit', '-qm', 'base')
        base = git('rev-parse', 'HEAD').decode()
        remote = self.root / 'remote.git'; git('clone', '--bare', str(source), str(remote))
        (source / 'file').write_text('after\n'); git('commit', '-qam', 'local unpublished patch')
        (self.root / 'patch').write_bytes(git('diff', base, 'HEAD') + b'\n')
        # check_output().strip() would change the immutable commit's final newline.
        (self.root / 'commit').write_bytes(subprocess.check_output(['git','-C',str(source),'cat-file','commit','HEAD']))
        self.recipe = {'repository': str(remote), 'baseRevision': base, 'revision': git('rev-parse','HEAD').decode(), 'tree':git('rev-parse','HEAD^{tree}').decode(), 'patch':'patch', 'patchSha256':hashlib.sha256((self.root/'patch').read_bytes()).hexdigest(), 'commit':'commit'}
        self.destination = self.root / 'prepared'
    def test_fresh_and_repeat_without_remote_target(self):
        for _ in range(2):
            result = prepare(self.destination, self.recipe, self.root)
            self.assertEqual(result['revision'], self.recipe['revision'])
            self.assertEqual((self.destination / 'file').read_text(), 'after\n')
    def test_dirty_source_is_preserved(self):
        prepare(self.destination, self.recipe, self.root)
        (self.destination/'file').write_text('user edit\n')
        with self.assertRaisesRegex(ValueError, 'local changes'):
            prepare(self.destination, self.recipe, self.root)
        self.assertEqual((self.destination/'file').read_text(), 'user edit\n')
    def test_unrelated_clean_checkout_is_untouched(self):
        subprocess.run(['git', 'clone', '-q', str(self.root/'source'), str(self.destination)], check=True)
        before = subprocess.check_output(['git','-C',str(self.destination),'rev-parse','HEAD'])
        with self.assertRaisesRegex(ValueError, 'origin'):
            prepare(self.destination, self.recipe, self.root)
        self.assertEqual(subprocess.check_output(['git','-C',str(self.destination),'rev-parse','HEAD']), before)
        self.assertEqual((self.destination/'file').read_text(), 'after\n')
    def test_tampered_inputs_fail(self):
        for key in ('patchSha256', 'revision', 'tree'):
            recipe = copy.deepcopy(self.recipe); recipe[key] = '0' * len(recipe[key])
            with self.subTest(key=key), self.assertRaises(ValueError):
                prepare(self.root/key, recipe, self.root)
    def test_shipped_recipe_matches_contract_and_commit(self):
        recipe = json.loads((ROOT/'umbriel/source.json').read_text())
        contract = json.loads((ROOT/'shell/Catalog/umbriel-capabilities.json').read_text())
        commit = (ROOT/recipe['commit']).read_bytes()
        self.assertEqual(recipe['revision'], contract['referenceRevision'])
        self.assertTrue(commit.startswith(('tree '+recipe['tree']+'\nparent '+recipe['baseRevision']+'\n').encode()))
        self.assertEqual(hashlib.sha1(b'commit '+str(len(commit)).encode()+b'\0'+commit).hexdigest(), recipe['revision'])
        self.assertEqual(hashlib.sha256((ROOT/recipe['patch']).read_bytes()).hexdigest(), recipe['patchSha256'])

    def test_release_archive_contains_complete_source_recipe(self):
        # Exercise the actual release pathspec against a Git tree containing
        # the shipped recipe inputs, including the ISO-only package consumer.
        recipe = json.loads((ROOT/'umbriel/source.json').read_text())
        archive_repo = self.root/'archive-repo'
        archive_repo.mkdir()
        paths = {'umbriel/source.json', recipe['patch'], recipe['commit'],
                 'shell/scripts/prepare-umbriel-source.py'}
        for relative in paths:
            target = archive_repo/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/relative).read_bytes())
        (archive_repo/'iso').mkdir(exist_ok=True)
        (archive_repo/'iso/excluded').write_text('internal ISO content')
        def git(*args):
            return subprocess.check_output(['git', '-C', str(archive_repo), *args])
        git('init', '-q')
        git('add', '.')
        tree = git('write-tree').decode().strip()
        workflow = (ROOT/'.github/workflows/release.yml').read_text()
        self.assertIn("-- . ':(exclude)iso'", workflow)
        payload = git('archive', '--format=tar', tree, '--', '.', ':(exclude)iso')
        with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
            names = set(archive.getnames())
            self.assertFalse(any(name == 'iso' or name.startswith('iso/') for name in names))
            self.assertFalse(any(member.issym() or member.islnk() for member in archive))
            bundled = json.load(archive.extractfile('umbriel/source.json'))
            patch = archive.extractfile(bundled['patch']).read()
            commit = archive.extractfile(bundled['commit']).read()
            self.assertIn('shell/scripts/prepare-umbriel-source.py', names)
        self.assertEqual(hashlib.sha256(patch).hexdigest(), bundled['patchSha256'])
        self.assertEqual(hashlib.sha1(b'commit '+str(len(commit)).encode()+b'\0'+commit).hexdigest(), bundled['revision'])
        self.assertTrue(commit.startswith(('tree '+bundled['tree']+'\nparent '+bundled['baseRevision']+'\n').encode()))

    def test_iso_recipe_uses_canonical_patch(self):
        recipe = json.loads((ROOT/'umbriel/source.json').read_text())
        package_patch = ROOT/'iso/packages/pkgbuilds/umbriel/pointer-modifiers.patch'
        self.assertEqual(package_patch.resolve(), (ROOT/recipe['patch']).resolve())
        pkgbuild = (package_patch.parent/'PKGBUILD').read_text()
        self.assertIn(recipe['patchSha256'], pkgbuild)

if __name__ == '__main__': unittest.main()
