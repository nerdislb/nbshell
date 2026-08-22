#!/usr/bin/env python3
import importlib.util
import pathlib
import tempfile

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

with tempfile.TemporaryDirectory() as name:
    destination = pathlib.Path(name)
    archive = destination / "unsafe.tar.gz"
    import io
    import tarfile
    with tarfile.open(archive, "w:gz") as bundle:
        info = tarfile.TarInfo("../escape")
        info.size = 1
        bundle.addfile(info, io.BytesIO(b"x"))
    try:
        UPDATE.safe_extract(archive, destination / "out")
    except ValueError:
        pass
    else:
        raise AssertionError("unsafe archive path was accepted")

print("Shell updater tests: OK")
