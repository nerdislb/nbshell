#!/usr/bin/env python3
import importlib.util
import io
import pathlib
import tarfile
import tempfile
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("nbshell_update", ROOT / "shell/scripts/nbshell-update.py")
UPDATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATE)

assert UPDATE.version_key("1.0.0") > UPDATE.version_key("1.0.0-beta.9")
assert UPDATE.version_key("1.2.0-beta.2") > UPDATE.version_key("1.2.0-beta.1")
assert UPDATE.version_key("2.0.0") > UPDATE.version_key("1.99.99")

releases = [
    {"tag_name": "v1.0.0", "draft": False, "prerelease": False},
    {"tag_name": "v1.1.0-beta.1", "draft": False, "prerelease": True},
    {"tag_name": "v9.0.0", "draft": True, "prerelease": False},
]
assert UPDATE.select_release(releases, "stable")["tag_name"] == "v1.0.0"
assert UPDATE.select_release(releases, "beta")["tag_name"] == "v1.1.0-beta.1"

with mock.patch.object(UPDATE, "current_version", return_value="1.0.0"):
    release = {
        "tag_name": "v1.1.0",
        "draft": False,
        "prerelease": False,
        "assets": [
            {"name": "nbshell-1.1.0.tar.gz", "browser_download_url": "archive"},
            {"name": "nbshell-1.1.0.tar.gz.sha256", "browser_download_url": "checksum"},
            {"name": "nbshell-1.1.0.tar.gz.sigstore.json", "browser_download_url": "bundle"},
        ],
    }
    info = UPDATE.status("stable", [release])
    assert info["installable"] is True
    assert info["bundleUrl"] == "bundle"
    release["assets"].pop()
    assert UPDATE.status("stable", [release])["installable"] is False

with tempfile.TemporaryDirectory() as name:
    archive = pathlib.Path(name) / "nbshell-1.1.0.tar.gz"
    bundle = pathlib.Path(name) / "nbshell-1.1.0.tar.gz.sigstore.json"
    archive.touch()
    bundle.touch()
    with mock.patch.object(UPDATE.shutil, "which", return_value="/usr/bin/cosign"), \
            mock.patch.object(UPDATE.subprocess, "run") as run:
        UPDATE.verify_signature(archive, bundle, "1.1.0")
        command = run.call_args.args[0]
        assert command[:3] == ["/usr/bin/cosign", "verify-blob", str(archive)]
        assert f"{UPDATE.SIGNING_WORKFLOW}@refs/tags/v1.1.0" in command
        assert UPDATE.SIGNING_ISSUER in command
    with mock.patch.object(UPDATE.shutil, "which", return_value=None):
        try:
            UPDATE.verify_signature(archive, bundle, "1.1.0")
        except ValueError as exc:
            assert "Cosign" in str(exc)
        else:
            raise AssertionError("missing Cosign was accepted")

def add_file(bundle, name, data=b"x"):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    bundle.addfile(info, io.BytesIO(data))


def add_special(bundle, name, kind):
    info = tarfile.TarInfo(name)
    info.type = kind
    info.linkname = "/etc/passwd" if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ""
    bundle.addfile(info)


def expect_rejected(build, message, **limits):
    with tempfile.TemporaryDirectory() as name:
        destination = pathlib.Path(name)
        archive = destination / "unsafe.tar.gz"
        with tarfile.open(archive, "w:gz") as bundle:
            build(bundle)
        patches = [mock.patch.object(UPDATE, key, value) for key, value in limits.items()]
        for patcher in patches:
            patcher.start()
        try:
            UPDATE.safe_extract(archive, destination / "out")
        except ValueError:
            pass
        else:
            raise AssertionError(message)
        finally:
            for patcher in reversed(patches):
                patcher.stop()


expect_rejected(lambda b: add_file(b, "../escape"), "relative traversal was accepted")
expect_rejected(lambda b: add_file(b, "/etc/passwd"), "absolute path was accepted")
expect_rejected(lambda b: add_special(b, "root/link", tarfile.SYMTYPE), "symlink was accepted")
expect_rejected(lambda b: add_special(b, "root/hardlink", tarfile.LNKTYPE), "hardlink was accepted")
expect_rejected(lambda b: add_special(b, "root/fifo", tarfile.FIFOTYPE), "FIFO was accepted")
expect_rejected(lambda b: add_file(b, "root/large", b"xx"), "large member was accepted", MAX_MEMBER_BYTES=1)
expect_rejected(
    lambda b: (add_file(b, "root/a", b"xx"), add_file(b, "root/b", b"xx")),
    "expanded size limit was ignored",
    MAX_MEMBER_BYTES=10,
    MAX_TOTAL_EXTRACT_BYTES=3,
)
expect_rejected(
    lambda b: (add_file(b, "root/a", b""), add_file(b, "root/b", b"")),
    "member-count limit was ignored",
    MAX_MEMBERS=1,
)
expect_rejected(lambda b: add_file(b, "no-install/readme"), "missing installer was accepted")
expect_rejected(
    lambda b: (add_file(b, "root/install.sh"), add_file(b, "outside")),
    "top-level file beside the source root was accepted",
)
expect_rejected(
    lambda b: (add_file(b, "one/install.sh"), add_file(b, "two/install.sh")),
    "multiple source roots were accepted",
)

with tempfile.TemporaryDirectory() as name:
    root = pathlib.Path(name)
    archive = root / "valid.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        add_file(bundle, "nbshell-test/install.sh", b"#!/bin/sh\n")
    extracted = UPDATE.safe_extract(archive, root / "out")
    assert extracted.name == "nbshell-test" and (extracted / "install.sh").is_file()


class OversizedResponse:
    def __init__(self):
        self.chunks = iter((b"abc", b"de", b""))

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self, _size):
        return next(self.chunks)


with tempfile.TemporaryDirectory() as name, \
        mock.patch.object(UPDATE, "MAX_DOWNLOAD_BYTES", 4), \
        mock.patch.object(UPDATE.urllib.request, "urlopen", return_value=OversizedResponse()):
    destination = pathlib.Path(name) / "asset"
    try:
        UPDATE.download("https://github.com/example", destination)
    except ValueError:
        pass
    else:
        raise AssertionError("oversized download was accepted")
    assert destination.read_bytes() == b"abc"

print("Shell updater tests: OK")
