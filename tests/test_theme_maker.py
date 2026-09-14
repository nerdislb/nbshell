"""Theme Maker publication must isolate drafts and preserve existing user data."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('theme_maker', ROOT / 'shell/scripts/theme-maker.py')
maker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(maker)


class ThemeMakerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {'XDG_CONFIG_HOME': str(self.root/'config'), 'XDG_STATE_HOME': str(self.root/'state')})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.config, self.state = maker.paths()
        self.config.mkdir(parents=True)
        self.settings = {'schemaVersion': 1, 'theme': 'old', 'accent': 'blue', 'unrelated': {'keep': 42},
                         'wallpaperOverride': '/existing/image.png', 'dynamicWallpaper': {'videoEnabled': True, 'video': '/existing/loop.mp4', 'custom': 7}}
        maker.atomic_json(self.config/'config.json', self.settings)
        self.draft = {'name': 'Clean / Theme', 'palette': {'background': '#112233', 'foreground': '#eeeeee', 'accent': '#abcdef'}, 'background': {}}

    def test_draft_and_save_do_not_apply_and_never_overwrite(self):
        before = (self.config/'config.json').read_bytes()
        maker.atomic_json(self.state/'draft.json', maker.validate(self.draft))
        first = maker.publish(self.draft)
        second = maker.publish(self.draft)
        self.assertEqual(first['name'], 'clean-theme')
        self.assertEqual(second['name'], 'clean-theme-2')
        self.assertEqual((self.config/'config.json').read_bytes(), before)
        self.assertEqual(tomllib.loads((Path(first['path'])/'colors.toml').read_text())['accent'], '#abcdef')

    def test_failed_media_leaves_no_partial_theme(self):
        self.draft['background'] = {'enabled': True, 'image': str(self.root/'missing.png')}
        with self.assertRaises(OSError): maker.publish(self.draft)
        self.assertEqual(list((self.config/'themes').iterdir()), [])

    def test_validation_and_fifo_rejection(self):
        invalid = copy.deepcopy(self.draft)
        invalid['palette']['accent'] = 'bad color'
        with self.assertRaises(ValueError): maker.validate(invalid)
        invalid = copy.deepcopy(self.draft)
        invalid['background']['dim'] = float('nan')
        with self.assertRaises(ValueError): maker.validate(invalid)
        fifo = self.root/'pipe.png'
        os.mkfifo(fifo)
        with self.assertRaises(ValueError): maker.copy_media(fifo, self.root/'out.png', maker.IMAGES)

    def test_repeated_apply_never_saves_or_updates_config(self):
        before = (self.config/'config.json').read_bytes()
        with patch.object(maker, 'preview_ipc') as ipc:
            for _ in range(3):
                maker.preview(self.draft)
            self.assertEqual(ipc.call_count, 3)
            payload = json.loads(ipc.call_args.args[1])
            self.assertEqual(payload['palette']['accent'], '#abcdef')
            self.assertIsNone(payload['wallpaper'])
        self.assertEqual(maker.theme_names(), [])
        self.assertFalse(list(self.root.rglob('colors.toml')))
        self.assertEqual((self.config/'config.json').read_bytes(), before)
        # Only the explicit save creates an entry.
        maker.publish(self.draft)
        self.assertEqual(maker.theme_names(), ['clean-theme'])

    def test_export_copies_media_but_apply_references_source(self):
        image = self.root/'chosen image.png'
        image.write_bytes(b'image fixture')
        self.draft['background'] = {'enabled': True, 'image': str(image)}
        with patch.object(maker, 'preview_ipc') as ipc:
            maker.preview(self.draft)
            wallpaper = json.loads(ipc.call_args.args[1])['wallpaper']
            self.assertEqual(wallpaper['image'], str(image))
            self.assertFalse(wallpaper['videoEnabled'])
        self.assertEqual(maker.theme_names(), [])
        saved = maker.publish(self.draft, self.root/'export')
        image.unlink()
        packaged = Path(saved['path'])/saved['assets']['image']
        self.assertEqual(packaged.read_bytes(), b'image fixture')

    def test_failed_preview_does_not_fall_back_to_saving(self):
        with patch.object(maker, 'preview_ipc', side_effect=ValueError('unavailable')):
            with self.assertRaises(ValueError): maker.preview(self.draft)
        self.assertEqual(maker.theme_names(), [])

    def test_load_rejects_metadata_escape_and_hides_staging(self):
        saved = maker.publish(self.draft)
        folder = Path(saved['path'])
        maker.atomic_json(folder/'theme-maker.json', {'assets': {'image': '../../config.json'}})
        self.assertEqual(maker.load_theme(saved['name'])['background']['image'], '')
        hidden = folder.parent/'.theme-maker-incomplete'
        hidden.mkdir()
        (hidden/'colors.toml').write_text('')
        self.assertNotIn(hidden.name, maker.theme_names())
        with self.assertRaises(ValueError): maker.load_theme('../config.json')

    def test_gif_is_converted_with_poster(self):
        gif = self.root/'odd.gif'
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi', '-i', 'color=blue:s=17x19:d=0.2', str(gif)], check=True)
        self.draft['background'] = {'enabled': True, 'motion': str(gif)}
        saved = maker.publish(self.draft)
        for key in ('image', 'motion', 'gif'):
            self.assertGreater((Path(saved['path'])/saved['assets'][key]).stat().st_size, 0)
        self.assertTrue(saved['assets']['motion'].endswith('.mp4'))


if __name__ == '__main__': unittest.main()
