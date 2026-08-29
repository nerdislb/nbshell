#!/usr/bin/env python3
"""Launch nbshell's native session locker, with Hyprlock as a fallback."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib


CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
NB_DIR = CONFIG_HOME / "nbshell"
CONFIG_PATH = NB_DIR / "config.json"
OUTPUT_PATH = NB_DIR / "generated" / "hyprlock.conf"
NATIVE_CONFIG_PATH = NB_DIR / "generated" / "orbital-lock.json"
LOCK_DIR = Path(__file__).resolve().parents[1] / "lock"
PAM_SERVICE_PATH = Path("/etc/pam.d/nbshell-lock")
READY_PATH = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "nbshell-lock-ready"
NATIVE_UNIT = "nbshell-lock.service"


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def load_theme(config: dict) -> tuple[dict, Path]:
    name = str(config.get("theme") or "tokyo-night")
    theme_dir = NB_DIR / "themes" / name
    try:
        raw = tomllib.loads((theme_dir / "colors.toml").read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        raw = {}

    def pick(*names: str, fallback: str) -> str:
        for key in names:
            value = raw.get(key)
            if isinstance(value, str) and value.startswith("#") and len(value) in (7, 9):
                return value[:7]
        return fallback

    colors = {
        "background": pick("background", "color0", fallback="#11111b"),
        "foreground": pick("foreground", "color7", fallback="#cdd6f4"),
        "bright": pick("bright_foreground", "color15", "foreground", fallback="#ffffff"),
        "muted": pick("muted", "color8", "dark_foreground", fallback="#6c7086"),
        "red": pick("red", "color1", fallback="#f38ba8"),
        "green": pick("green", "color2", fallback="#a6e3a1"),
        "yellow": pick("yellow", "color3", fallback="#f9e2af"),
        "blue": pick("blue", "color4", fallback="#89b4fa"),
        "magenta": pick("magenta", "color5", fallback="#cba6f7"),
        "cyan": pick("cyan", "color6", fallback="#94e2d5"),
    }
    accent_role = str(config.get("accent") or "theme")
    if accent_role == "theme":
        colors["accent"] = pick("accent", "color4", "blue", fallback=colors["blue"])
    else:
        colors["accent"] = colors.get(accent_role, colors["blue"])
    return colors, theme_dir


def find_wallpaper(config: dict, theme_dir: Path) -> Path | None:
    # The running shell passes the exact image currently rendered on screen.
    # This avoids racing Config's atomic file write when the user selects a
    # wallpaper and locks immediately afterwards. CLI calls still use the
    # persisted override and theme fallback below.
    active = os.environ.get("NBSHELL_LOCK_WALLPAPER", "")
    if active:
        candidate = Path(os.path.expandvars(os.path.expanduser(active)))
        if candidate.is_file():
            return candidate.resolve()

    override = config.get("wallpaperOverride")
    if isinstance(override, str) and override:
        candidate = Path(os.path.expandvars(os.path.expanduser(override)))
        if candidate.is_file():
            return candidate.resolve()

    roots = (
        theme_dir / "backgrounds",
        Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        / "nbshell" / "wallpapers" / theme_dir.name,
        Path.home() / "Sync" / "nbshell" / "wallpapers" / theme_dir.name,
    )
    for root in roots:
        if not root.is_dir():
            continue
        for pattern in ("*.jpg", "*.jpeg", "*.png", "*.webp"):
            found = sorted(root.glob(pattern))
            if found:
                return found[0].resolve()
    return None


def rgba(color: str, alpha: int = 255) -> str:
    value = color.lstrip("#")[:6]
    if len(value) != 6 or any(ch not in "0123456789abcdefABCDEF" for ch in value):
        value = "000000"
    return f"rgba({value}{max(0, min(255, alpha)):02x})"


def bounded_int(config: dict, key: str, default: int, low: int, high: int) -> int:
    try:
        return max(low, min(high, int(config.get(key, default))))
    except (TypeError, ValueError):
        return default


def render(config_path: Path = CONFIG_PATH, output_path: Path = OUTPUT_PATH) -> Path:
    config = load_json(config_path)
    colors, theme_dir = load_theme(config)
    wallpaper = find_wallpaper(config, theme_dir)
    font = str(config.get("font") or "JetBrainsMono Nerd Font").replace("\n", " ")
    font_size = bounded_int(config, "fontSize", 14, 8, 24)
    radius = bounded_int(config, "radius", 2, 0, 40)
    border_width = bounded_int(config, "borderWidth", 1, 0, 4)
    blur = bounded_int(config, "lockBlur", 3, 0, 8)
    dim = bounded_int(config, "lockDim", 48, 0, 85)
    show_date = config.get("lockShowDate", True) is not False
    show_host = config.get("lockShowHost", True) is not False
    fingerprint_enabled = config.get("lockFingerprint", False) is True
    background_mode = str(config.get("lockBackground") or "wallpaper")
    use_wallpaper = background_mode == "wallpaper" and wallpaper is not None

    background_path = str(wallpaper).replace("\n", "") if use_wallpaper else ""
    background = f"""background {{
    monitor =
    color = {rgba(colors['background'])}
    path = {background_path}
    blur_passes = {blur if use_wallpaper else 0}
    blur_size = 7
    brightness = {(100 - dim) / 100:.2f}
}}
"""

    date_widget = ""
    if show_date:
        date_widget = f"""
label {{
    monitor =
    text = cmd[update:60000] date +\"%A  ·  %d %B %Y\"
    color = {rgba(colors['foreground'])}
    font_size = {font_size + 3}
    font_family = {font}
    position = 0, 105
    halign = center
    valign = center
}}
"""

    host_widget = ""
    if show_host:
        host_widget = f"""
label {{
    monitor =
    text = $USER  @  $HOSTNAME
    color = {rgba(colors['muted'])}
    font_size = {max(9, font_size - 1)}
    font_family = {font}
    position = 0, -145
    halign = center
    valign = center
}}
"""

    fingerprint_auth = ""
    if fingerprint_enabled:
        fingerprint_auth = """
auth {
    fingerprint {
        enabled = true
        ready_message = PLACE FINGER ON SENSOR
        present_message = SCANNING FINGERPRINT
        retry_delay = 400
    }
}
"""

    content = f"""# Generated by nbshell. Do not edit manually.
# Authentication is handled by Hyprlock and PAM.

general {{
    hide_cursor = true
    ignore_empty_input = true
    immediate_render = true
}}

{fingerprint_auth}

animations {{
    enabled = true
    bezier = nbshell, 0.22, 1, 0.36, 1
    animation = fadeIn, 1, 3, nbshell
    animation = fadeOut, 1, 2, nbshell
    animation = inputFieldDots, 1, 2, nbshell
}}

{background}
shape {{
    monitor =
    size = 660, 390
    color = {rgba(colors['background'])}
    rounding = {radius}
    border_size = {border_width}
    border_color = {rgba(colors['accent'])}
    position = 0, 0
    halign = center
    valign = center
}}

shape {{
    monitor =
    size = 620, {max(1, border_width)}
    color = {rgba(colors['accent'])}
    rounding = 0
    position = 0, 148
    halign = center
    valign = center
}}

label {{
    monitor =
    text = SESSION LOCKED
    color = {rgba(colors['accent'])}
    font_size = {font_size}
    font_family = {font}
    position = 0, 165
    halign = center
    valign = center
}}

label {{
    monitor =
    text = $TIME
    color = {rgba(colors['bright'])}
    font_size = 68
    font_family = {font}
    position = 0, 48
    halign = center
    valign = center
}}
label {{
    monitor =
    text = 󰈷
    color = {rgba(colors['accent'])}
    font_size = 25
    font_family = {font}
    position = 0, -112
    halign = center
    valign = center
}}
{date_widget}
input-field {{
    monitor =
    size = 520, 54
    outline_thickness = {border_width}
    inner_color = {rgba(colors['background'])}
    outer_color = {rgba(colors['accent'])}
    check_color = {rgba(colors['green'])}
    fail_color = {rgba(colors['red'])}
    font_color = {rgba(colors['foreground'])}
    fade_on_empty = false
    rounding = {radius}
    font_family = {font}
    placeholder_text = ENTER PASSWORD
    check_text = AUTHENTICATING
    fail_text = ACCESS DENIED  ·  $PAMFAIL
    dots_size = 0.25
    dots_spacing = 0.35
    position = 0, -55
    halign = center
    valign = center
}}
{host_widget}
label {{
    monitor =
    text = KEYBOARD  $LAYOUT
    color = {rgba(colors['muted'])}
    font_size = {max(9, font_size - 3)}
    font_family = {font}
    position = 0, -174
    halign = center
    valign = center
}}
"""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=output_path.parent, delete=False
    ) as handle:
        handle.write(content)
        temporary = Path(handle.name)
    temporary.chmod(0o600)
    os.replace(temporary, output_path)
    return output_path


def lock_command(config: dict, generated: Path) -> list[str]:
    custom = config.get("lockCommand")
    if isinstance(custom, str) and custom.strip():
        command = shlex.split(custom)
        if command:
            return command
    return ["hyprlock", "--config", str(generated), "--immediate-render"]


def render_native(config_path: Path = CONFIG_PATH, output_path: Path = NATIVE_CONFIG_PATH) -> Path:
    config = load_json(config_path)
    colors, theme_dir = load_theme(config)
    wallpaper = find_wallpaper(config, theme_dir)
    document = {
        "username": os.environ.get("USER", ""),
        "wallpaper": str(wallpaper) if wallpaper else "",
        "background": colors["background"], "foreground": colors["foreground"],
        "muted": colors["muted"], "accent": colors["accent"], "red": colors["red"],
        "font": str(config.get("font") or "JetBrainsMono Nerd Font").replace("\n", " "),
        "dimOpacity": bounded_int(config, "lockDim", 48, 0, 85) / 100,
        "hourFormat": "12" if str(config.get("clockFormat")) == "12" else "24",
        "showSecondsRing": config.get("lockShowSeconds", True) is not False,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=output_path.parent, delete=False) as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")
        temporary = Path(handle.name)
    temporary.chmod(0o600)
    os.replace(temporary, output_path)
    return output_path


def native_command(config: dict, native_config: Path) -> list[str] | None:
    """Return the native command only when its runtime and PAM contract exist."""
    if isinstance(config.get("lockCommand"), str) and config["lockCommand"].strip():
        return None
    quickshell = shutil.which("quickshell") or shutil.which("qs")
    unit = CONFIG_HOME / "systemd/user" / NATIVE_UNIT
    if quickshell and (LOCK_DIR / "shell.qml").is_file() and PAM_SERVICE_PATH.is_file() and unit.is_file():
        return ["systemctl", "--user", "start", NATIVE_UNIT]
    return None


def selected_locker(config: dict, generated: Path, native_config: Path) -> tuple[list[str], dict[str, str], bool]:
    native = native_command(config, native_config)
    if native:
        environment = os.environ.copy()
        environment.update(NBSHELL_LOCK_CONFIG=str(native_config), NBSHELL_LOCK_READY=str(READY_PATH))
        return native, environment, True
    return lock_command(config, generated), os.environ.copy(), False


def locker_running(command: list[str] | None = None) -> bool:
    command = command or ["hyprlock"]
    if command == ["systemctl", "--user", "start", NATIVE_UNIT]:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "--quiet", NATIVE_UNIT],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0
    if "-p" in command and str(LOCK_DIR) in command:
        result = subprocess.run(
            ["pgrep", "-f", f"(^|/)(quickshell|qs).* -p {str(LOCK_DIR)}($| )"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0
    process_name = Path(command[0]).name
    result = subprocess.run(
        ["pgrep", "-x", process_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    return result.returncode == 0


def umbriel_binary() -> str | None:
    detected = shutil.which("umbriel")
    local = Path.home() / ".local/bin/umbriel"
    if detected:
        return detected
    return str(local) if local.is_file() and os.access(local, os.X_OK) else None


def umbriel_windows(binary: str) -> list[dict]:
    try:
        result = subprocess.run(
            [binary, "windows", "--json"], capture_output=True, text=True,
            timeout=2, check=False,
        )
        value = json.loads(result.stdout) if result.returncode == 0 else []
        return value if isinstance(value, list) else []
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return []


def workspace_selector(workspace: str) -> str:
    """Convert Umbriel's IPC id (OUTPUT:NAME) to its action selector."""
    output, separator, name = workspace.rpartition(":")
    return f"{name}/{output}" if separator and output and name else workspace


def repair_umbriel_resume(binary: str, before: dict[str, str], focused_id: str) -> int:
    """Reattach only windows that lost a previously valid workspace on resume."""
    repaired_ids: set[str] = set()
    for _ in range(10):
        current = umbriel_windows(binary)
        # Umbriel may need a moment to recreate outputs and workspace groups.
        if not current:
            time.sleep(0.5)
            continue
        orphaned = [
            row for row in current
            if str(row.get("id") or "") in before
            and before.get(str(row.get("id") or ""), "")
            and str(row.get("workspace") or "") == ""
        ]
        if not orphaned:
            break
        for row in orphaned:
            window_id = str(row["id"])
            selector = workspace_selector(before[window_id])
            focus = subprocess.run([binary, "msg", f"window-focus:{window_id}"])
            if focus.returncode == 0:
                move = subprocess.run([binary, "msg", f"window-move-to-workspace:{selector}"])
                if move.returncode == 0:
                    repaired_ids.add(window_id)
        time.sleep(0.5)
    if repaired_ids and focused_id:
        subprocess.run([binary, "msg", f"window-focus:{focused_id}"])
    return len(repaired_ids)


def start_lock(suspend: bool = False) -> int:
    generated = render()
    native_config = render_native()
    config = load_json(CONFIG_PATH)
    command, environment, native = selected_locker(config, generated, native_config)
    fallback_command = lock_command(config, generated)
    # A fallback started after an earlier native failure is still a valid,
    # secure locker. Do not race it with a second session-lock client.
    if native and locker_running(fallback_command):
        command, environment, native = fallback_command, os.environ.copy(), False
    if not shutil.which(command[0]):
        print(f"nbshell: screen locker is not installed: {command[0]}", file=sys.stderr)
        return 127
    if native and not locker_running(command):
        READY_PATH.unlink(missing_ok=True)
        started = subprocess.run(command, env=environment)
        if started.returncode != 0:
            if not locker_running(command):
                os.execvpe(fallback_command[0], fallback_command, os.environ.copy())
            return started.returncode
        deadline = time.monotonic() + 4.0
        while time.monotonic() < deadline:
            if READY_PATH.is_file():
                break
            if not locker_running(command):
                os.execvpe(fallback_command[0], fallback_command, os.environ.copy())
            time.sleep(0.05)
        else:
            print("nbshell: native locker did not confirm secure output coverage", file=sys.stderr)
            return 1

    if not suspend:
        if locker_running(command):
            return 0
        if native:
            READY_PATH.unlink(missing_ok=True)
        os.execvpe(command[0], command, environment)

    umbriel = umbriel_binary()
    windows_before = umbriel_windows(umbriel) if umbriel else []
    workspaces_before = {
        str(row.get("id")): str(row.get("workspace"))
        for row in windows_before
        if row.get("id") and row.get("workspace")
    }
    focused_before = next(
        (str(row.get("id")) for row in windows_before if row.get("focused")), ""
    )

    locker = None
    if not locker_running(command):
        if native:
            READY_PATH.unlink(missing_ok=True)
        locker = subprocess.Popen(command, env=environment)
        deadline = time.monotonic() + (4.0 if native else 1.5)
        while time.monotonic() < deadline:
            code = locker.poll()
            if code is not None:
                print(f"nbshell: screen locker exited before suspend ({code})", file=sys.stderr)
                return code or 1
            if native and READY_PATH.is_file():
                break
            time.sleep(0.05)
        else:
            if native:
                print("nbshell: screen locker did not confirm secure output coverage", file=sys.stderr)
                return 1
    elif native and not READY_PATH.is_file():
        print("nbshell: native locker is running but not ready for suspend", file=sys.stderr)
        return 1
    result = subprocess.run(["systemctl", "suspend"])
    if result.returncode == 0 and umbriel and workspaces_before:
        repair_umbriel_resume(umbriel, workspaces_before, focused_before)
    return result.returncode


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else "lock"
    if action == "render":
        print(render())
        return 0
    if action == "render-native":
        print(render_native())
        return 0
    if action == "status":
        generated = render()
        native_config = render_native()
        config = load_json(CONFIG_PATH)
        command, _, native = selected_locker(config, generated, native_config)
        running = locker_running(command)
        if native and not running:
            running = locker_running(lock_command(config, generated))
        print("locked" if running else "unlocked")
        return 0
    if action == "lock":
        return start_lock()
    if action == "suspend":
        return start_lock(suspend=True)
    if action == "preview":
        native_config = render_native()
        quickshell = shutil.which("quickshell") or shutil.which("qs")
        if not quickshell:
            print("nbshell: Quickshell is not installed", file=sys.stderr)
            return 127
        environment = os.environ.copy()
        environment.update(NBSHELL_LOCK_PREVIEW="1", NBSHELL_LOCK_CONFIG=str(native_config))
        os.execvpe(quickshell, [quickshell, "-p", str(LOCK_DIR)], environment)
    print("usage: lockscreen.py lock|suspend|render|render-native|status|preview", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
