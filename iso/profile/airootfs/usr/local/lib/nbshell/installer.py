#!/usr/bin/env python3
"""Private, destructive whole-disk nbshell installer orchestrator."""

from __future__ import annotations

import argparse
import getpass
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid
import re

TARGET_MOUNT = Path("/mnt/archinstall")
TARGET_PACKAGES = [
    "base", "linux", "linux-firmware", "btrfs-progs", "networkmanager",
    "sudo", "greetd", "quickshell", "umbriel", "xdg-desktop-portal",
    "xdg-desktop-portal-umbriel", "nbshell", "pipewire", "pipewire-pulse",
    "wireplumber", "wl-clipboard", "hyprpolkitagent",
    "ttf-jetbrains-mono-nerd",
]


def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=check, text=True, capture_output=True)


def serial_log(message: str) -> None:
    """Best-effort machine-readable marker for QEMU acceptance."""
    try:
        with Path("/dev/ttyS0").open("a", encoding="utf-8") as serial:
            serial.write(f"NBSHELL_ISO: {message}\n")
    except OSError:
        pass


def live_disk() -> str | None:
    """Return the parent disk backing the live ISO, when discoverable."""
    source = run("findmnt", "-n", "-o", "SOURCE", "/run/archiso/bootmnt", check=False).stdout.strip()
    if not source.startswith("/dev/"):
        return None
    parent = run("lsblk", "-ndo", "PKNAME", source, check=False).stdout.strip()
    return f"/dev/{parent}" if parent else source


def disks() -> list[dict[str, object]]:
    payload = json.loads(run("lsblk", "--json", "--bytes", "--nodeps", "-o", "PATH,SIZE,MODEL,TYPE,RO,RM").stdout)
    excluded = live_disk()
    return [
        item for item in payload.get("blockdevices", [])
        if item.get("type") == "disk"
        and not item.get("ro") and not item.get("rm")
        and item.get("path") != excluded
    ]


def confirmations_match(device: str, typed_device: str, erase_phrase: str) -> bool:
    """Pure safety gate used by the TUI and unit tests."""
    return typed_device == device and erase_phrase == f"ERASE {device}"


def size(value: int, unit: str) -> dict[str, object]:
    return {"sector_size": {"unit": "B", "value": 512}, "unit": unit, "value": value}


def config(
    device: str,
    encrypted: bool,
    *,
    disk_bytes: int = 64 * 1024**3,
    timezone: str = "UTC",
) -> tuple[dict[str, object], dict[str, object]]:
    mib = 1024**2
    aligned_bytes = disk_bytes // mib * mib
    root_bytes = aligned_bytes - 1026 * mib
    if root_bytes < 16 * 1024**3:
        raise ValueError("Target disk must provide at least 16 GiB after the EFI partition")
    esp_id, root_id = str(uuid.uuid4()), str(uuid.uuid4())
    root = {
        "btrfs": [
            {"mountpoint": "/", "name": "@"},
            {"mountpoint": "/home", "name": "@home"},
            {"mountpoint": "/var/log", "name": "@log"},
            {"mountpoint": "/var/cache/pacman/pkg", "name": "@pkg"},
        ],
        "flags": [], "fs_type": "btrfs", "mount_options": ["compress=zstd"],
        "mountpoint": None, "dev_path": None, "obj_id": root_id, "start": size(1025, "MiB"),
        "size": size(root_bytes, "B"), "status": "create", "type": "primary",
    }
    disk_config: dict[str, object] = {
        "config_type": "manual_partitioning",
        "device_modifications": [{
            "device": device, "wipe": True,
            "partitions": [{
                "btrfs": [], "flags": ["esp", "boot"], "fs_type": "fat32",
                "mount_options": [], "mountpoint": "/boot", "obj_id": esp_id,
                "dev_path": None,
                "start": size(1, "MiB"), "size": size(1024, "MiB"),
                "status": "create", "type": "primary",
            }, root],
        }],
        "btrfs_options": {"snapshot_config": None},
    }
    creds: dict[str, object] = {}
    if encrypted:
        disk_config["disk_encryption"] = {
            "encryption_type": "luks", "partitions": [root_id], "hsm_device": None,
        }
    cfg: dict[str, object] = {
        "archinstall-language": "English",
        "bootloader_config": {"bootloader": "Systemd-boot", "uki": False, "removable": False},
        "disk_config": disk_config, "hostname": "nbshell", "kernels": ["linux"],
        "locale_config": {"kb_layout": "us", "sys_enc": "UTF-8", "sys_lang": "en_US"},
        "mirror_config": {"custom_repositories": [{
            "name": "nbshell", "url": "file:///var/cache/nbshell/repo",
            "sign_check": "Optional", "sign_option": "TrustAll",
        }]},
        "network_config": {"type": "nm"}, "ntp": True, "offline": True,
        "packages": TARGET_PACKAGES, "profile_config": None, "silent": True,
        "swap": {"enabled": True, "algorithm": "zstd"}, "timezone": timezone,
    }
    return cfg, creds


def hash_password(password: str) -> str:
    result = subprocess.run(
        ("openssl", "passwd", "-6", "-stdin"), input=password + "\n",
        check=True, text=True, capture_output=True,
    )
    return result.stdout.strip()


def collect() -> tuple[str, int, bool, str, str, str, str]:
    choices = disks()
    if not choices:
        raise SystemExit("No eligible non-live, writable fixed disk found.")
    print("Eligible disks (the live ISO disk is excluded):")
    for item in choices:
        print(f"  {item['path']}  {int(item['size']) // (1024**3)} GiB  {item.get('model') or ''}")
    device = input("Target device: ").strip()
    allowed = {str(item["path"]) for item in choices}
    if device not in allowed:
        raise SystemExit("Target is not an eligible disk.")
    disk_bytes = int(str(next(item["size"] for item in choices if str(item["path"]) == device)))
    phrase = input(f"Type ERASE {device}: ").strip()
    if not confirmations_match(device, device, phrase):
        raise SystemExit("Confirmation did not match; nothing changed.")
    encrypted = input("Encrypt root with LUKS? [y/N]: ").strip().lower() == "y"
    luks = getpass.getpass("LUKS passphrase: ") if encrypted else ""
    if encrypted and (len(luks) < 8 or luks != getpass.getpass("Repeat passphrase: ")):
        raise SystemExit("Passphrases differ or are shorter than 8 characters.")
    timezone = input("Timezone [UTC]: ").strip() or "UTC"
    username = input("Desktop username [nbshell]: ").strip() or "nbshell"
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", username):
        raise SystemExit("Username must be a valid lowercase Linux account name.")
    password = getpass.getpass(f"Password for {username}: ")
    if len(password) < 8 or password != getpass.getpass("Repeat password: "):
        raise SystemExit("Passwords differ or are shorter than 8 characters.")
    return device, disk_bytes, encrypted, luks, timezone, username, hash_password(password)


def provision_target(
    username: str,
    *,
    source_lib: Path = Path("/usr/local/lib/nbshell"),
    source_units: Path = Path("/etc/systemd/system"),
) -> None:
    """Install ISO-owned first-boot assets before entering the target chroot."""
    target_lib = TARGET_MOUNT / source_lib.relative_to("/")
    target_units = TARGET_MOUNT / "etc/systemd/system"
    target_lib.mkdir(parents=True, exist_ok=True)
    target_units.mkdir(parents=True, exist_ok=True)
    for name in ("target-setup.sh", "firstboot.sh"):
        shutil.copy2(source_lib / name, target_lib / name)
    for name in ("nbshell-firstboot.service", "nbshell-recovery.service"):
        shutil.copy2(source_units / name, target_units / name)
    target_config = TARGET_MOUNT / "etc/nbshell"
    target_config.mkdir(parents=True, exist_ok=True)
    (target_config / "install-user").write_text(username + "\n", encoding="utf-8")
    (target_config / "install-user").chmod(0o600)


def invoke_archinstall(config_path: Path, creds_path: Path) -> None:
    command = (
        "archinstall", "--config", str(config_path), "--creds", str(creds_path),
        "--silent", "--offline",
    )
    # Mandatory parser/schema validation before archinstall can touch a disk.
    run(*command, "--dry-run")
    run(*command)


def main() -> int:
    parser = argparse.ArgumentParser(description="nbshell whole-disk installer (UEFI only)")
    parser.add_argument("--install", action="store_true", help="permit installation after all safety gates")
    args = parser.parse_args()
    print("nbshell private preview installer — QEMU/UEFI, whole disk, no dual boot")
    serial_log("installer-ready")
    if not args.install:
        print("DRY RUN: no disk commands will run. Re-run with the documented install gate.")
        serial_log("dry-run-complete")
        return 0
    if os.environ.get("NBSHELL_ALLOW_INSTALL") != "ERASE":
        raise SystemExit("Refusing: set NBSHELL_ALLOW_INSTALL=ERASE explicitly.")
    if not Path("/sys/firmware/efi").is_dir():
        raise SystemExit("Refusing: this v1 installer requires UEFI.")
    device, disk_bytes, encrypted, luks, timezone, username, password_hash = collect()
    cfg, creds = config(device, encrypted, disk_bytes=disk_bytes, timezone=timezone)
    creds["users"] = [{"username": username, "enc_password": password_hash, "sudo": True}]
    if encrypted:
        creds["encryption_password"] = luks
    with tempfile.TemporaryDirectory(prefix="nbshell-install-", dir="/run") as work:
        config_path, creds_path = Path(work, "config.json"), Path(work, "creds.json")
        config_path.write_text(json.dumps(cfg, indent=2) + "\n")
        creds_path.write_text(json.dumps(creds) + "\n")
        config_path.chmod(0o600)
        creds_path.chmod(0o600)
        invoke_archinstall(config_path, creds_path)
    provision_target(username)
    run("arch-chroot", str(TARGET_MOUNT), "/usr/local/lib/nbshell/target-setup.sh")
    print("Installation complete. Remove the ISO and reboot.")
    serial_log("install-complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
