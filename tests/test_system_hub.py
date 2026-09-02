#!/usr/bin/env python3

import importlib.util
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "shell/scripts/system-hub.py"
SPEC = importlib.util.spec_from_file_location("nbshell_system_hub", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
HUB = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = HUB
SPEC.loader.exec_module(HUB)


class ArchNewsLinkTests(unittest.TestCase):
    def test_accepts_arch_linux_https_origins(self):
        self.assertEqual(
            HUB.arch_news_link("https://archlinux.org/news/example/"),
            "https://archlinux.org/news/example/",
        )
        self.assertEqual(
            HUB.arch_news_link("https://security.archlinux.org/issue/1"),
            "https://security.archlinux.org/issue/1",
        )

    def test_rejects_shell_text_and_other_origins(self):
        fallback = "https://archlinux.org/news/"
        for value in (
            "https://evil.example/$(touch /tmp/owned)",
            "https://archlinux.org.evil.example/news/",
            "http://archlinux.org/news/",
            "file:///etc/passwd",
            "https://archlinux.org@evil.example/news/",
            "",
            None,
        ):
            self.assertEqual(HUB.arch_news_link(value), fallback)


if __name__ == "__main__":
    unittest.main()
