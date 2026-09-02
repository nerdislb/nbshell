#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import sys
import unittest
from unittest.mock import Mock, patch

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "shell/scripts/shopping-list-send.py"
SPEC = importlib.util.spec_from_file_location("shopping_list_send", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ShoppingListSendTests(unittest.TestCase):
    def test_exact_group_filter(self) -> None:
        payload = {
            "success": True,
            "data": [
                {"jid": "one@g.us", "kind": "group", "name": "Einkauf"},
                {"jid": "two@g.us", "kind": "group", "name": "Einkauf alt"},
                {"jid": "person@s.whatsapp.net", "kind": "direct", "name": "Einkauf"},
            ],
        }
        self.assertEqual(MODULE.exact_groups(payload, "einkauf"), [payload["data"][0]])

    def test_send_uses_discrete_arguments_and_resolved_jid(self) -> None:
        lookup = subprocess.CompletedProcess(
            [], 0,
            json.dumps({"success": True, "data": [{"jid": "group@g.us", "kind": "group", "name": "Einkauf"}]}),
            "",
        )
        delivery = subprocess.CompletedProcess([], 0, '{"success":true,"data":{"sent":true,"message_id":"test"}}', "")
        runner = Mock(side_effect=[lookup, delivery])

        code, payload = MODULE.send("Einkauf", "🛒 *Einkauf*\n\n☐ Milch", runner)

        self.assertEqual(code, 0)
        self.assertTrue(payload["success"])
        lookup_args = runner.call_args_list[0].args[0]
        send_args = runner.call_args_list[1].args[0]
        self.assertEqual(lookup_args[-4:], ["--query", "Einkauf", "--limit", "50"])
        self.assertEqual(send_args[-4:], ["--to", "group@g.us", "--message", "🛒 *Einkauf*\n\n☐ Milch"])
        self.assertNotIn("sh", send_args)
        self.assertNotIn("bash", send_args)

    def test_missing_group_never_sends(self) -> None:
        runner = Mock(return_value=subprocess.CompletedProcess([], 0, '{"success":true,"data":null}', ""))
        code, payload = MODULE.send("Einkauf", "list", runner)
        self.assertEqual(code, 3)
        self.assertEqual(payload["code"], "group-not-found")
        runner.assert_called_once()

    def test_failed_delivery_preserves_failure_result(self) -> None:
        lookup = subprocess.CompletedProcess(
            [], 0,
            '{"success":true,"data":[{"jid":"group@g.us","kind":"group","name":"Einkauf"}]}',
            "",
        )
        delivery = subprocess.CompletedProcess([], 1, '{"success":false,"error":"offline"}', "")
        code, payload = MODULE.send("Einkauf", "list", Mock(side_effect=[lookup, delivery]))
        self.assertEqual(code, 1)
        self.assertFalse(payload["success"])
        self.assertEqual(payload["message"], "offline")

    def test_main_reads_message_from_stdin_not_argv(self) -> None:
        captured = {}

        def fake_send(target, message, runner=subprocess.run):
            captured["target"] = target
            captured["message"] = message
            return 0, MODULE.result(True, "ok", code="sent")

        argv = ["shopping-list-send.py", "--to", "Einkauf"]
        with patch.object(MODULE, "send", fake_send), \
                patch.object(sys, "argv", argv), \
                patch.object(sys.stdin, "read", return_value="🛒 secret list"), \
                patch("builtins.print"):
            code = MODULE.main()

        self.assertEqual(code, 0)
        self.assertEqual(captured, {"target": "Einkauf", "message": "🛒 secret list"})
        self.assertNotIn("--message", argv)
        self.assertTrue(all("secret list" not in argument for argument in argv))

    def test_zero_exit_without_sent_confirmation_fails_closed(self) -> None:
        lookup = subprocess.CompletedProcess(
            [], 0,
            '{"success":true,"data":[{"jid":"group@g.us","kind":"group","name":"Einkauf"}]}',
            "",
        )
        delivery = subprocess.CompletedProcess([], 0, '{"success":true,"data":{"sent":false}}', "")
        code, payload = MODULE.send("Einkauf", "list", Mock(side_effect=[lookup, delivery]))
        self.assertEqual(code, 6)
        self.assertEqual(payload["code"], "send-unconfirmed")


if __name__ == "__main__":
    unittest.main()
