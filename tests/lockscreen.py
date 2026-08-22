#!/usr/bin/env python3

import importlib.util
import contextlib
import io
import json
from pathlib import Path
import tempfile
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "nbshell_lockscreen", ROOT / "shell/scripts/lockscreen.py"
)
assert SPEC and SPEC.loader
LOCKSCREEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LOCKSCREEN)


def check_named_theme(root: Path) -> None:
    config_dir = root / "nbshell"
    theme_dir = config_dir / "themes" / "test"
    theme_dir.mkdir(parents=True)
    wallpaper = theme_dir / "backgrounds" / "wall paper.jpg"
    wallpaper.parent.mkdir()
    wallpaper.write_bytes(b"test")
    (theme_dir / "colors.toml").write_text(
        'background = "#101010"\nforeground = "#eeeeee"\naccent = "#ff8800"\nred = "#dd0000"\ngreen = "#00dd00"\n',
        encoding="utf-8",
    )
    config = config_dir / "config.json"
    config.write_text(json.dumps({"theme": "test", "lockDim": 40}), encoding="utf-8")
    output = root / "generated.conf"
    LOCKSCREEN.NB_DIR = config_dir
    LOCKSCREEN.render(config, output)
    text = output.read_text(encoding="utf-8")
    assert "rgba(ff8800ff)" in text
    assert "brightness = 0.60" in text
    assert str(wallpaper) in text
    assert "SESSION LOCKED" in text
    assert output.stat().st_mode & 0o777 == 0o600


def check_live_wallpaper_wins(root: Path) -> None:
    theme_dir = root / "theme"
    theme_dir.mkdir()
    configured = root / "configured.jpg"
    active = root / "active.jpg"
    configured.write_bytes(b"configured")
    active.write_bytes(b"active")
    with mock.patch.dict(
        LOCKSCREEN.os.environ, {"NBSHELL_LOCK_WALLPAPER": str(active)}
    ):
        assert LOCKSCREEN.find_wallpaper(
            {"wallpaperOverride": str(configured)}, theme_dir
        ) == active.resolve()


def check_ansi_and_solid(root: Path) -> None:
    config_dir = root / "nbshell-ansi"
    theme_dir = config_dir / "themes" / "ansi"
    theme_dir.mkdir(parents=True)
    (theme_dir / "colors.toml").write_text(
        'color0 = "#020202"\ncolor1 = "#ff0000"\ncolor2 = "#00ff00"\ncolor4 = "#2244ff"\ncolor7 = "#dddddd"\ncolor8 = "#777777"\ncolor15 = "#ffffff"\n',
        encoding="utf-8",
    )
    config = config_dir / "config.json"
    config.write_text(
        json.dumps({"theme": "ansi", "lockBackground": "solid", "lockShowHost": False}),
        encoding="utf-8",
    )
    output = root / "ansi.conf"
    LOCKSCREEN.NB_DIR = config_dir
    LOCKSCREEN.render(config, output)
    text = output.read_text(encoding="utf-8")
    assert "rgba(2244ffff)" in text
    assert "path = \n" in text
    assert "$USER  @  $HOSTNAME" not in text


def check_custom_command() -> None:
    assert LOCKSCREEN.lock_command({"lockCommand": "waylock -fork-on-lock"}, Path("x")) == [
        "waylock",
        "-fork-on-lock",
    ]
    assert LOCKSCREEN.lock_command({}, Path("generated.conf")) == [
        "hyprlock",
        "--config",
        "generated.conf",
        "--immediate-render",
    ]
    assert LOCKSCREEN.locker_running(["this-process-cannot-exist"]) is False


def check_suspend_guard() -> None:
    alive = mock.Mock()
    alive.poll.return_value = None
    completed = mock.Mock(returncode=0)
    with (
        mock.patch.object(LOCKSCREEN, "render", return_value=Path("generated.conf")),
        mock.patch.object(LOCKSCREEN, "load_json", return_value={}),
        mock.patch.object(LOCKSCREEN, "locker_running", return_value=False),
        mock.patch.object(LOCKSCREEN.shutil, "which", return_value="/usr/bin/hyprlock"),
        mock.patch.object(LOCKSCREEN.subprocess, "Popen", return_value=alive),
        mock.patch.object(LOCKSCREEN.subprocess, "run", return_value=completed) as run,
        mock.patch.object(LOCKSCREEN.time, "monotonic", side_effect=[0.0, 2.0]),
    ):
        assert LOCKSCREEN.start_lock(suspend=True) == 0
        run.assert_called_once_with(["systemctl", "suspend"])

    failed = mock.Mock()
    failed.poll.return_value = 5
    with (
        mock.patch.object(LOCKSCREEN, "render", return_value=Path("generated.conf")),
        mock.patch.object(LOCKSCREEN, "load_json", return_value={}),
        mock.patch.object(LOCKSCREEN, "locker_running", return_value=False),
        mock.patch.object(LOCKSCREEN.shutil, "which", return_value="/usr/bin/hyprlock"),
        mock.patch.object(LOCKSCREEN.subprocess, "Popen", return_value=failed),
        mock.patch.object(LOCKSCREEN.subprocess, "run") as run,
        mock.patch.object(LOCKSCREEN.time, "monotonic", side_effect=[0.0, 0.1]),
    ):
        with contextlib.redirect_stderr(io.StringIO()):
            assert LOCKSCREEN.start_lock(suspend=True) == 5
        run.assert_not_called()


with tempfile.TemporaryDirectory(prefix="nbshell-lock-test-") as temporary:
    root = Path(temporary)
    check_named_theme(root)
    check_live_wallpaper_wins(root)
    check_ansi_and_solid(root)
    check_custom_command()
    check_suspend_guard()

print("Lockscreen generation: OK")
