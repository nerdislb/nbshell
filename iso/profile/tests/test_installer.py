#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
MODULE = HERE.parent / "airootfs/usr/local/lib/nbshell/installer.py"
spec = importlib.util.spec_from_file_location("nbshell_installer", MODULE)
installer = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(installer)


class Result:
    def __init__(self, stdout: str):
        self.stdout = stdout


class InstallerTests(unittest.TestCase):
    def test_temporary_directory_is_portable(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(Path(directory).is_dir())

    def test_live_disk_is_excluded(self):
        listing = {"blockdevices": [
            {"path": "/dev/vda", "size": 10, "model": "ISO", "type": "disk", "ro": False, "rm": False},
            {"path": "/dev/vdb", "size": 20, "model": "TARGET", "type": "disk", "ro": False, "rm": False},
            {"path": "/dev/vdc", "size": 30, "model": "USB", "type": "disk", "ro": False, "rm": True},
        ]}
        with patch.object(installer, "run", return_value=Result(json.dumps(listing))), \
             patch.object(installer, "live_disk", return_value="/dev/vda"):
            self.assertEqual(["/dev/vdb"], [d["path"] for d in installer.disks()])

    def test_confirmation_requires_both_exact_values(self):
        self.assertTrue(installer.confirmations_match("/dev/vdb", "/dev/vdb", "ERASE /dev/vdb"))
        self.assertFalse(installer.confirmations_match("/dev/vdb", "/dev/vda", "ERASE /dev/vdb"))
        self.assertFalse(installer.confirmations_match("/dev/vdb", "/dev/vdb", "erase /dev/vdb"))

    def test_current_archinstall_contract_and_credentials_separation(self):
        cfg, creds = installer.config("/dev/vdb", True)
        disk = cfg["disk_config"]
        self.assertEqual("Systemd-boot", cfg["bootloader_config"]["bootloader"])
        self.assertEqual("manual_partitioning", disk["config_type"])
        self.assertEqual("luks", disk["disk_encryption"]["encryption_type"])
        root_id = disk["device_modifications"][0]["partitions"][1]["obj_id"]
        self.assertEqual([root_id], disk["disk_encryption"]["partitions"])
        self.assertIsNone(disk["device_modifications"][0]["partitions"][1]["dev_path"])
        self.assertNotIn("encryption_password", json.dumps(cfg))
        self.assertEqual({}, creds)
        self.assertEqual("UTC", cfg["timezone"])
        repository = cfg["mirror_config"]["custom_repositories"][0]
        self.assertEqual(("Optional", "TrustAll"), (repository["sign_check"], repository["sign_option"]))
        self.assertEqual("nbshell", repository["name"])
        self.assertEqual("file:///var/cache/nbshell/repo", repository["url"])
        geometry = disk["device_modifications"][0]["partitions"][0]["size"]
        self.assertEqual({"unit": "B", "value": 512}, geometry["sector_size"])
        root_size = disk["device_modifications"][0]["partitions"][1]["size"]
        self.assertEqual("B", root_size["unit"])
        self.assertGreater(root_size["value"], 16 * 1024**3)

    def test_small_disk_is_rejected_before_archinstall(self):
        with self.assertRaisesRegex(ValueError, "at least 16 GiB"):
            installer.config("/dev/vdb", False, disk_bytes=12 * 1024**3)

    def test_archinstall_preflight_precedes_real_invocation(self):
        with patch.object(installer, "run") as mocked:
            installer.invoke_archinstall(Path("/run/config"), Path("/run/creds"))
        self.assertEqual("--dry-run", mocked.call_args_list[0].args[-1])
        self.assertNotIn("--dry-run", mocked.call_args_list[1].args)
        self.assertIn("--offline", mocked.call_args_list[0].args)

    def test_sensitive_files_are_mode_600(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory, name) for name in ("config.json", "creds.json")]
            for path in paths:
                path.write_text("{}")
                path.chmod(0o600)
                self.assertEqual(0o600, stat.S_IMODE(path.stat().st_mode))

    def test_target_provisioning_records_install_user_privately(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_lib = root / "source-lib"
            source_units = root / "source-units"
            source_lib.mkdir()
            source_units.mkdir()
            for name in ("target-setup.sh", "firstboot.sh"):
                (source_lib / name).write_text("#!/bin/sh\n")
            for name in ("nbshell-firstboot.service", "nbshell-recovery.service"):
                (source_units / name).write_text("[Service]\n")
            with patch.object(installer, "TARGET_MOUNT", root / "target"):
                installer.provision_target(
                    "alice", source_lib=source_lib, source_units=source_units
                )
            marker = root / "target/etc/nbshell/install-user"
            self.assertEqual("alice\n", marker.read_text())
            self.assertEqual(0o600, stat.S_IMODE(marker.stat().st_mode))

    def test_password_hash_does_not_pass_secret_in_argv(self):
        completed = Result("$6$salt$hash\n")
        with patch.object(installer.subprocess, "run", return_value=completed) as mocked:
            self.assertEqual("$6$salt$hash", installer.hash_password("secret-value"))
        self.assertNotIn("secret-value", mocked.call_args.args[0])
        self.assertEqual("secret-value\n", mocked.call_args.kwargs["input"])


if __name__ == "__main__":
    unittest.main()
