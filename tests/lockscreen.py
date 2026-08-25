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

GUARD_SPEC = importlib.util.spec_from_file_location(
    "nbshell_umbriel_resume_guard", ROOT / "shell/scripts/umbriel_resume_guard.py"
)
assert GUARD_SPEC and GUARD_SPEC.loader
GUARD = importlib.util.module_from_spec(GUARD_SPEC)
GUARD_SPEC.loader.exec_module(GUARD)


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
    config.write_text(
        json.dumps(
            {
                "theme": "test",
                "lockDim": 40,
                "font": "Test Mono",
                "fontSize": 16,
                "radius": 7,
                "borderWidth": 3,
            }
        ),
        encoding="utf-8",
    )
    output = root / "generated.conf"
    LOCKSCREEN.NB_DIR = config_dir
    LOCKSCREEN.render(config, output)
    text = output.read_text(encoding="utf-8")
    assert "rgba(ff8800ff)" in text
    assert "brightness = 0.60" in text
    assert str(wallpaper) in text
    assert "font_family = Test Mono" in text
    assert "font_size = 19" in text
    assert "rounding = 7" in text
    assert "border_size = 3" in text
    assert "outline_thickness = 3" in text
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
        mock.patch.object(LOCKSCREEN, "umbriel_binary", return_value=None),
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
        mock.patch.object(LOCKSCREEN, "umbriel_binary", return_value=None),
        mock.patch.object(LOCKSCREEN.shutil, "which", return_value="/usr/bin/hyprlock"),
        mock.patch.object(LOCKSCREEN.subprocess, "Popen", return_value=failed),
        mock.patch.object(LOCKSCREEN.subprocess, "run") as run,
        mock.patch.object(LOCKSCREEN.time, "monotonic", side_effect=[0.0, 0.1]),
    ):
        with contextlib.redirect_stderr(io.StringIO()):
            assert LOCKSCREEN.start_lock(suspend=True) == 5
        run.assert_not_called()


def check_umbriel_resume_repair() -> None:
    assert LOCKSCREEN.workspace_selector("eDP-1:1") == "1/eDP-1"
    assert LOCKSCREEN.workspace_selector("DP-1:DEV") == "DEV/DP-1"

    before = {"orphan": "eDP-1:1", "scratch": ""}
    orphaned = [
        {"id": "orphan", "workspace": ""},
        {"id": "scratch", "workspace": ""},
        {"id": "healthy", "workspace": "eDP-1:1"},
    ]
    repaired = [
        {"id": "orphan", "workspace": "eDP-1:1"},
        {"id": "scratch", "workspace": ""},
        {"id": "healthy", "workspace": "eDP-1:1"},
    ]
    completed = mock.Mock(returncode=0)
    with (
        mock.patch.object(LOCKSCREEN, "umbriel_windows", side_effect=[[], orphaned, repaired]),
        mock.patch.object(LOCKSCREEN.subprocess, "run", return_value=completed) as run,
        mock.patch.object(LOCKSCREEN.time, "sleep"),
    ):
        assert LOCKSCREEN.repair_umbriel_resume("umbriel", before, "healthy") == 1
        assert [call.args[0] for call in run.call_args_list] == [
            ["umbriel", "msg", "window-focus:orphan"],
            ["umbriel", "msg", "window-move-to-workspace:1/eDP-1"],
            ["umbriel", "msg", "window-focus:healthy"],
        ]


def check_umbriel_resume_snapshot() -> None:
    known, focused = GUARD.update_snapshot(
        [
            {"id": "healthy", "workspace": "eDP-1:1", "focused": True},
            {"id": "scratch", "workspace": "", "focused": False},
        ],
        {},
        "",
    )
    assert known == {"healthy": "eDP-1:1"}
    assert focused == "healthy"

    # The last valid assignment must survive the empty workspace reported
    # during output recreation. Scratchpads must never gain an assignment.
    known, focused = GUARD.update_snapshot(
        [
            {"id": "healthy", "workspace": "", "focused": False},
            {"id": "scratch", "workspace": "", "focused": True},
        ],
        known,
        focused,
    )
    assert known == {"healthy": "eDP-1:1"}
    assert focused == "scratch"


with tempfile.TemporaryDirectory(prefix="nbshell-lock-test-") as temporary:
    root = Path(temporary)
    check_named_theme(root)
    check_live_wallpaper_wins(root)
    check_ansi_and_solid(root)
    check_custom_command()
    check_suspend_guard()
    check_umbriel_resume_repair()
    check_umbriel_resume_snapshot()

print("Lockscreen generation: OK")
