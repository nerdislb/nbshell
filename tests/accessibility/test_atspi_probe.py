#!/usr/bin/env python3
"""Unit tests for the bounded nbshell AT-SPI probe."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

MODULE_PATH = Path(__file__).with_name("atspi_probe.py")
SPEC = importlib.util.spec_from_file_location("atspi_probe", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROBE)


class FakeStateSet:
    def __init__(self, states: list[int] | None = None) -> None:
        self._states = states or []

    def getStates(self) -> list[int]:
        return self._states


class FakeAction:
    def __init__(self, names: list[str]) -> None:
        self._names = names
        self.nActions = len(names)

    def getName(self, index: int) -> str:
        return self._names[index]


class FakeNode:
    def __init__(
        self,
        name: str,
        *,
        pid: int = 0,
        role: str = "panel",
        description: str = "",
        attributes: list[str] | None = None,
        actions: list[str] | None = None,
        children: list["FakeNode"] | None = None,
    ) -> None:
        self.name = name
        self.description = description
        self._pid = pid
        self._role = role
        self._attributes = attributes or []
        self._actions = actions
        self._children = children or []

    @property
    def childCount(self) -> int:
        return len(self._children)

    def getChildAtIndex(self, index: int) -> "FakeNode":
        return self._children[index]

    def get_process_id(self) -> int:
        return self._pid

    def getRoleName(self) -> str:
        return self._role

    def getAttributes(self) -> list[str]:
        return self._attributes

    def getState(self) -> FakeStateSet:
        return FakeStateSet()

    def queryAction(self) -> FakeAction:
        if self._actions is None:
            raise NotImplementedError
        return FakeAction(self._actions)


class ProbeTests(unittest.TestCase):
    def test_find_application_prefers_explicit_pid(self) -> None:
        applications = [
            FakeNode("quickshell", pid=10),
            FakeNode("other", pid=20),
        ]
        self.assertIs(PROBE.find_application(applications, "quickshell", 20), applications[1])

    def test_find_application_matches_default_name_case_insensitively(self) -> None:
        application = FakeNode("QuickShell", pid=10)
        self.assertIs(
            PROBE.find_application([application], PROBE.DEFAULT_APP_PATTERN),
            application,
        )

    def test_attributes_preserve_names_and_values_with_colons(self) -> None:
        self.assertEqual(
            PROBE.normalize_attributes(
                ["id:audio-output", "xml:lang:en-US", "toolkit:Qt:Quick"]
            ),
            ["id:audio-output", "xml:lang:en-US", "toolkit:Qt:Quick"],
        )
        self.assertEqual(
            PROBE.stable_id(["xml:lang:en-US", "id:audio-output"]),
            "audio-output",
        )

    def test_serialize_tree_records_semantics_and_limits_depth(self) -> None:
        leaf = FakeNode("Mute", role="push button", actions=["click"])
        child = FakeNode(
            "Output volume",
            role="slider",
            description="Master output",
            attributes=["id:audio-output-volume"],
            children=[leaf],
        )
        root = FakeNode("quickshell", role="application", children=[child])

        tree, count, truncated = PROBE.serialize_tree(root, max_depth=1, max_nodes=20)

        self.assertEqual(count, 2)
        self.assertTrue(truncated)
        self.assertEqual(tree["children"][0]["role"], "slider")
        self.assertEqual(tree["children"][0]["id"], "audio-output-volume")
        self.assertTrue(tree["children"][0]["children_truncated"])

    def test_serialize_tree_honours_node_limit(self) -> None:
        root = FakeNode(
            "quickshell",
            children=[FakeNode("one"), FakeNode("two"), FakeNode("three")],
        )
        tree, count, truncated = PROBE.serialize_tree(root, max_depth=5, max_nodes=2)
        self.assertEqual(count, 2)
        self.assertTrue(truncated)
        self.assertEqual(len(tree["children"]), 1)

    def test_tree_is_empty_requires_application_only(self) -> None:
        self.assertTrue(PROBE.tree_is_empty({"children": []}, 1))
        self.assertFalse(PROBE.tree_is_empty({"children": [{}]}, 2))

    def test_private_json_uses_mode_0600(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "snapshot.json"
            path.write_text("old\n", encoding="utf-8")
            path.chmod(0o644)
            PROBE.write_private_json(path, {"ok": True})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertIn('"ok": true', path.read_text(encoding="utf-8"))

    @unittest.skipUnless(hasattr(os, "O_NOFOLLOW"), "requires O_NOFOLLOW")
    def test_private_json_rejects_symlink_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "target.json"
            target.write_text("preserve\n", encoding="utf-8")
            link = Path(directory) / "snapshot.json"
            link.symlink_to(target)
            with self.assertRaises(OSError):
                PROBE.write_private_json(link, {"ok": True})
            self.assertEqual(target.read_text(encoding="utf-8"), "preserve\n")


if __name__ == "__main__":
    unittest.main()
