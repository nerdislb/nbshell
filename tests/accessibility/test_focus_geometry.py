"""Regression checks for isolated panel-focus geometry and speech assertions."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'panel_focus', Path(__file__).resolve().parents[1] / 'wayland-panel-focus.py')
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FocusGeometryTest(unittest.TestCase):
    def test_inside_and_exact_edges(self):
        self.assertTrue(module.rect_contains((10, 20, 100, 80), (20, 30, 40, 20)))
        self.assertTrue(module.rect_contains((10, 20, 100, 80), (10, 20, 100, 80)))

    def test_each_clipped_edge(self):
        for row in [(9, 30, 40, 20), (20, 19, 40, 20),
                    (80, 30, 31, 20), (20, 80, 40, 21)]:
            with self.subTest(row=row):
                self.assertFalse(module.rect_contains((10, 20, 100, 80), row))

    def test_output_containment_does_not_prove_viewport_containment(self):
        row = (20, 110, 100, 20)
        self.assertTrue(module.rect_contains((0, 0, 800, 600), row))
        self.assertFalse(module.rect_contains((10, 20, 200, 100), row))

    def test_empty_and_negative_dimensions(self):
        for row in [(20, 30, 0, 20), (20, 30, 40, 0), (20, 30, -1, 20)]:
            with self.subTest(row=row):
                self.assertFalse(module.rect_contains((10, 20, 100, 80), row))
        self.assertFalse(module.rect_contains((0, 0, 0, 80), (0, 0, 10, 10)))


class OrcaSpeechSequenceTest(unittest.TestCase):
    def test_order_and_repeated_labels(self):
        lines = [f"SPEECH OUTPUT: '{label}' {{}}" for label in ['Edge', 'BAR', 'Edge']]
        self.assertTrue(module.speech_sequence_present(lines, ['Edge', 'BAR', 'Edge']))
        self.assertFalse(module.speech_sequence_present(lines, ['BAR', 'Edge', 'Edge']))

    def test_non_speech_and_partial_labels_do_not_count(self):
        self.assertFalse(module.speech_sequence_present(["FOCUS: 'Edge'"], ['Edge']))
        self.assertFalse(module.speech_sequence_present(["SPEECH OUTPUT: 'Edge extra'"], ['Edge']))

    def test_missing_speech_does_not_pass(self):
        self.assertFalse(module.speech_sequence_present([], ['Edge']))


if __name__ == '__main__':
    unittest.main()
