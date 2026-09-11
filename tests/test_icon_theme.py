import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('icon_theme', Path(__file__).resolve().parents[1] / 'shell/scripts/icon-theme.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class IconThemeTests(unittest.TestCase):
    def test_precedence_missing_theme_and_malformed_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root/'config'; (config/'qt6ct').mkdir(parents=True)
            data = root/'share'
            for name in ['qt-icons', 'kde-icons', 'Papirus-Dark']:
                theme = data/'icons'/name; theme.mkdir(parents=True); (theme/'index.theme').write_text('[Icon Theme]\nName=Test\n')
            qt = config/'qt6ct/qt6ct.conf'
            qt.write_text('[Appearance]\nicon_theme=qt-icons\n')
            (config/'kdeglobals').write_text('[Icons]\nTheme=kde-icons\n')
            select = lambda: module.select_theme(config, data, str(root/'empty'))
            self.assertEqual(select(), 'qt-icons')
            qt.write_text('[Appearance]\nicon_theme=missing\n')
            self.assertEqual(select(), 'kde-icons')
            qt.write_text('malformed file')
            self.assertEqual(select(), 'kde-icons')
            (config/'kdeglobals').unlink()
            self.assertEqual(select(), 'Papirus-Dark')


if __name__ == '__main__':
    unittest.main()
