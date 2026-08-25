"""mpv-backed local playback with an owned queue."""

from __future__ import annotations

import json
import os
import select
import shutil
import socket
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Callable

from catalog import track_item, watch_url


class PlayerError(RuntimeError):
    pass


# yt-dlp has to fetch and solve YouTube's player JS challenge the first time it
# sees a new player build, which is far slower than a normal resolve. Failing
# that inside the warm budget is what makes the very first play after an install
# report "Playback failed", so a cold cache gets a much larger budget.
RESOLVE_TIMEOUT_WARM = 40
RESOLVE_TIMEOUT_COLD = 150
YT_DLP_SIGFUNC_CACHE = (
    Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    / "yt-dlp" / "youtube-sigfuncs"
)


def yt_dlp_cache_warm(path: Path | None = None) -> bool:
    """True when yt-dlp has already solved a player JS challenge."""
    target = Path(path) if path is not None else YT_DLP_SIGFUNC_CACHE
    try:
        return target.is_dir() and any(target.iterdir())
    except OSError:
        return False


def resolve_timeout(warm: bool) -> int:
    return RESOLVE_TIMEOUT_WARM if warm else RESOLVE_TIMEOUT_COLD


def quality_format(kbps: int) -> str:
    rate = 96 if kbps <= 96 else (160 if kbps <= 160 else 320)
    return f"bestaudio[abr<={rate}]/bestaudio/best"


# Ten-band EQ matching cliamp center frequencies (Hz).
EQ_FREQS = (70, 180, 320, 600, 1000, 3000, 6000, 12000, 14000, 16000)
EQ_LABELS = ("70", "180", "320", "600", "1k", "3k", "6k", "12k", "14k", "16k")
EQ_PRESETS: dict[str, tuple[float, ...]] = {
    "Flat": (0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    "Rock": (5, 4, 2, -1, -2, 2, 4, 5, 5, 5),
    "Pop": (-1, 2, 4, 5, 4, 1, -1, -1, 1, 2),
    "Jazz": (3, 4, 2, 1, -1, -1, 1, 2, 3, 4),
    "Classical": (3, 2, 1, 0, -1, -1, 0, 2, 3, 4),
    "Bass Boost": (8, 6, 4, 2, 0, 0, 0, 0, 0, 0),
    "Treble Boost": (0, 0, 0, 0, 0, 1, 3, 5, 6, 7),
    "Vocal": (-2, -1, 1, 4, 5, 4, 2, 0, -1, -2),
    "Electronic": (6, 4, 1, -1, -2, 1, 3, 4, 5, 6),
    "Acoustic": (3, 3, 2, 0, 1, 2, 3, 3, 2, 1),
}


def eq_filter_chain(bands: list[float]) -> str:
    """Stable 10-band lavfi graph. Always emit every band so mpv does not
    rebuild a different filter topology (that restarts the YouTube stream)."""
    parts: list[str] = []
    values = list(bands) + [0.0] * 10
    for freq, gain in zip(EQ_FREQS, values):
        clamped = max(-12.0, min(12.0, float(gain)))
        parts.append(f"equalizer=f={freq}:t=o:w=1:g={clamped:.1f}")
    return "lavfi=[" + ",".join(parts) + "]"


def media_title(item: dict | None) -> str:
    source = item or {}
    title = str(source.get("name") or source.get("title") or "").strip()
    if title:
        return title[:200]
    return "YouTube Music"


def media_artist(item: dict | None) -> str:
    source = item or {}
    artist = str(source.get("subtitle") or "").strip()
    if artist:
        return artist[:200]
    artists = source.get("artists")
    if isinstance(artists, list):
        names = [str(entry.get("name") or "").strip()
                 for entry in artists if isinstance(entry, dict)]
        artist = ", ".join(name for name in names if name)
        if artist:
            return artist[:200]
    return ""


def mpris_title(item: dict | None = None) -> str:
    title = media_title(item)
    artist = media_artist(item)
    if artist and artist.lower() not in title.lower():
        return f"{artist} - {title}"[:220]
    return title


def loadfile_command(url: str, item: dict | None = None) -> list:
    options = {"force-media-title": mpris_title(item)}
    return ["loadfile", url, "replace", -1, options]


def looks_like_stream_title(text: str) -> bool:
    value = str(text or "")
    lower = value.lower()
    return (
        "googlevideo.com" in lower
        or "videoplayback" in lower
        or "mime=audio" in lower
        or value.startswith("webm&")
        or "&ns=" in value
        or "&sig=" in value
    )


def mpv_command_line(binary: str, ipc_path: Path, mpris: str = "") -> list[str]:
    command = [
        binary,
        "--no-config",
        "--idle=yes",
        "--no-video",
        "--vo=null",
        "--force-window=no",
        "--no-terminal",
        "--audio-display=no",
        "--osc=no",
        "--load-scripts=no",
        "--keep-open=no",
        "--ytdl=no",
        "--ao=pipewire,pulse",
        "--clipboard-backends-clr",
        "--no-input-default-bindings",
        "--volume=80",
        "--title=YouTube Music",
        "--audio-client-name=omarchy-ytmusic",
        f"--input-ipc-server={ipc_path}",
        "--msg-level=cplayer=info,ao=info,ffmpeg=warn",
    ]
    if mpris:
        command.append(f"--script={mpris}")
    return command


def mpv_env(source: dict[str, str] | None = None) -> dict[str, str]:
    env = dict(source if source is not None else os.environ)
    for key in (
        "WAYLAND_DISPLAY",
        "DISPLAY",
        "HYPRLAND_INSTANCE_SIGNATURE",
        "SWAYSOCK",
        "WAYLAND_SOCKET",
    ):
        env.pop(key, None)
    return env


class Mpv:
    def __init__(self, ipc_path: Path):
        self.ipc_path = ipc_path
        self.process: subprocess.Popen | None = None
        self.sock: socket.socket | None = None
        self._next_id = 1
        self._lock = threading.Lock()

    @property
    def running(self) -> bool:
        return self.process is not None and self.process.poll() is None

    def start(self) -> None:
        if self.running:
            return
        mpv = shutil.which("mpv")
        if not mpv:
            raise PlayerError("mpv is not installed")
        self.ipc_path.parent.mkdir(parents=True, exist_ok=True)
        if self.ipc_path.exists():
            try:
                self.ipc_path.unlink()
            except OSError:
                pass
        log_path = self.ipc_path.parent / "mpv.log"
        command = mpv_command_line(mpv, self.ipc_path, _mpris_script())
        stderr = log_path.open("ab")
        try:
            self.process = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=stderr,
                env=mpv_env(),
                start_new_session=True,
            )
        finally:
            stderr.close()
        self._wait_for_socket()
        self._connect()
        self.command(["observe_property", 1, "pause"])
        self.command(["observe_property", 2, "eof-reached"])
        self.command(["observe_property", 3, "idle-active"])
        self.command(["observe_property", 4, "time-pos"])
        self.command(["observe_property", 5, "duration"])
        self.command(["observe_property", 6, "volume"])
        self.command(["observe_property", 7, "media-title"])

    def _wait_for_socket(self, timeout: float = 4.0) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.ipc_path.exists():
                return
            if self.process and self.process.poll() is not None:
                raise PlayerError("mpv exited before the control socket appeared")
            time.sleep(0.05)
        raise PlayerError("mpv control socket did not appear")

    def _connect(self) -> None:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        sock.connect(str(self.ipc_path))
        sock.setblocking(False)
        self.sock = sock

    def stop(self) -> None:
        if self.sock:
            try:
                self.command(["quit"])
            except Exception:
                pass
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None
        if self.process:
            try:
                self.process.terminate()
                self.process.wait(timeout=3)
            except Exception:
                try:
                    self.process.kill()
                except Exception:
                    pass
            self.process = None
        if self.ipc_path.exists():
            try:
                self.ipc_path.unlink()
            except OSError:
                pass

    def command(self, args: list[Any]) -> int:
        if not self.sock:
            raise PlayerError("mpv is not connected")
        with self._lock:
            request_id = self._next_id
            self._next_id += 1
            payload = json.dumps({"command": args, "request_id": request_id}) + "\n"
            self.sock.sendall(payload.encode("utf-8"))
            return request_id

    def poll_events(self, timeout: float = 0.2) -> list[dict]:
        if not self.sock:
            return []
        ready, _, _ = select.select([self.sock], [], [], timeout)
        if not ready:
            return []
        chunks = []
        while True:
            try:
                data = self.sock.recv(65536)
            except BlockingIOError:
                break
            if not data:
                break
            chunks.append(data)
        if not chunks:
            return []
        text = b"".join(chunks).decode("utf-8", errors="replace")
        events = []
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(message, dict):
                events.append(message)
        return events


def _mpris_script() -> str:
    candidates = [
        "/usr/lib/mpv-mpris/mpris.so",
        "/usr/lib/mpv/scripts/mpris.so",
        "/usr/lib64/mpv-mpris/mpris.so",
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return ""


class StreamResolver:
    def __init__(self, cookies_path: Path | None = None, kbps: int = 320):
        self.cookies_path = cookies_path
        self.kbps = kbps
        self._cache: dict[str, tuple[float, str]] = {}
        self._lock = threading.Lock()

    def set_quality(self, kbps: int) -> None:
        self.kbps = kbps
        with self._lock:
            self._cache.clear()

    def set_cookies(self, path: Path | None) -> None:
        self.cookies_path = path
        with self._lock:
            self._cache.clear()

    def resolve(self, video_id: str) -> str:
        video_id = str(video_id or "").strip()
        if not video_id:
            raise PlayerError("Missing video id")
        now = time.time()
        with self._lock:
            cached = self._cache.get(video_id)
            if cached and cached[0] > now:
                return cached[1]
        url = self._yt_dlp(video_id)
        with self._lock:
            self._cache[video_id] = (now + 4 * 60 * 60, url)
        return url

    def prefetch(self, video_id: str) -> None:
        def worker() -> None:
            try:
                self.resolve(video_id)
            except Exception:
                pass
        threading.Thread(target=worker, daemon=True).start()

    def _yt_dlp(self, video_id: str) -> str:
        binary = shutil.which("yt-dlp")
        if not binary:
            raise PlayerError("yt-dlp is not installed")
        url = watch_url(video_id)
        command = [
            binary,
            "--extractor-args", "youtube:player_client=android",
            "-f", quality_format(self.kbps),
            "-g",
            "--no-playlist",
            "--no-warnings",
            "--no-progress",
            url,
        ]
        # Do not pass cookies here: they push yt-dlp onto web_music, which
        # needs a GVS PO token we cannot mint. android URLs work unsigned.
        warm = yt_dlp_cache_warm()
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=resolve_timeout(warm),
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            if warm:
                raise PlayerError(
                    "YouTube took too long to answer. Try that track again."
                ) from exc
            raise PlayerError(
                "Preparing YouTube playback took too long the first time. "
                "Try that track again; the next one is much faster."
            ) from exc
        stream = (result.stdout or "").strip().splitlines()
        if result.returncode != 0 or not stream:
            detail = (result.stderr or "").strip().splitlines()
            message = detail[-1] if detail else "Could not resolve audio stream"
            raise PlayerError(message)
        return stream[-1]


class QueuePlayer:
    def __init__(
        self,
        runtime_dir: Path,
        on_change: Callable[[], None] | None = None,
        catalog_radio: Callable[[str], list[dict]] | None = None,
        on_played: Callable[[dict], None] | None = None,
    ):
        self.mpv = Mpv(runtime_dir / "mpv.sock")
        self.resolver = StreamResolver()
        self.on_change = on_change or (lambda: None)
        self.on_played = on_played or (lambda _item: None)
        self.catalog_radio = catalog_radio
        self.queue: list[dict] = []
        self.index = -1
        self.shuffle = False
        self.repeat = "off"
        self.playing = False
        self.volume = 80
        self.muted = False
        self.volume_before_mute = 80
        self.position_ms = 0
        self.duration_ms = 0
        self.error = ""
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._pending_eof = False
        self._generation = 0
        self._sleep_deadline = 0.0
        self._sleep_after = ""
        self._display_title = ""
        self.resolving = False
        self.last_activity = time.time()
        self.eq_bands: list[float] = list(EQ_PRESETS["Flat"])
        self.eq_preset = "Flat"
        self._eq_timer: threading.Timer | None = None
        self._eq_guard_until = 0.0
        self._eq_last_chain = ""

    @property
    def current(self) -> dict | None:
        if 0 <= self.index < len(self.queue):
            return self.queue[self.index]
        return None

    def snapshot_track(self) -> dict | None:
        item = self.current
        return dict(item) if item else None

    def ensure_started(self) -> None:
        if not self.mpv.running:
            self.mpv.start()
            self._stop.clear()
            if not self._thread or not self._thread.is_alive():
                self._thread = threading.Thread(target=self._loop, daemon=True)
                self._thread.start()
            self.mpv.command(["set_property", "volume", self.volume])
            self.apply_eq(immediate=True)

    def shutdown(self) -> None:
        self._stop.set()
        self.mpv.stop()
        self.playing = False

    def load(self, items: list[dict], index: int = 0, play: bool = True) -> None:
        tracks = [item for item in items if isinstance(item, dict) and item.get("videoId")]
        if not tracks:
            raise PlayerError("Nothing playable in that selection")
        self.queue = tracks
        self.index = max(0, min(int(index or 0), len(tracks) - 1))
        self.note_activity()
        self.ensure_started()
        self._play_current(start=play)

    def add_to_queue(self, item: dict) -> None:
        track = item if item.get("type") == "track" else track_item(item)
        if not track or not track.get("videoId"):
            raise PlayerError("That item cannot be queued")
        self.queue.append(track)
        self.note_activity()
        if self.current and self.current.get("videoId"):
            nxt = self._upcoming_video_id()
            if nxt:
                self.resolver.prefetch(nxt)
        self.on_change()

    def reorder_queue(self, source_index: int, destination_index: int) -> None:
        if not self.queue:
            return
        source = max(0, min(int(source_index), len(self.queue) - 1))
        destination = max(0, min(int(destination_index), len(self.queue) - 1))
        if source == destination:
            return
        with self._lock:
            current = self.index
            item = self.queue.pop(source)
            self.queue.insert(destination, item)
            if current == source:
                self.index = destination
            elif source < destination and source < current <= destination:
                self.index -= 1
            elif destination < source and destination <= current < source:
                self.index += 1
        self.note_activity()
        self.on_change()

    def eq_snapshot(self) -> dict[str, Any]:
        return {
            "bands": [float(value) for value in self.eq_bands],
            "preset": self.eq_preset,
            "labels": list(EQ_LABELS),
        }

    def apply_eq(self, immediate: bool = False) -> None:
        if not self.mpv.running:
            return
        with self._lock:
            if self._eq_timer:
                self._eq_timer.cancel()
                self._eq_timer = None
            if immediate:
                self._flush_eq_locked()
                return
            timer = threading.Timer(0.08, self._flush_eq)
            timer.daemon = True
            self._eq_timer = timer
            timer.start()

    def _flush_eq(self) -> None:
        with self._lock:
            self._eq_timer = None
            self._flush_eq_locked()

    def _flush_eq_locked(self) -> None:
        if not self.mpv.running:
            return
        chain = eq_filter_chain(self.eq_bands)
        if chain == self._eq_last_chain:
            return
        self._eq_last_chain = chain
        self._eq_guard_until = time.time() + 1.5
        try:
            self.mpv.command(["set_property", "af", chain])
        except PlayerError:
            pass

    def set_eq_band(self, index: int, gain: float) -> None:
        band = max(0, min(int(index), len(self.eq_bands) - 1))
        self.eq_bands[band] = max(-12.0, min(12.0, float(gain)))
        self.eq_preset = "Custom"
        self.apply_eq()
        self.on_change()

    def set_eq_preset(self, name: str) -> None:
        preset = EQ_PRESETS.get(str(name or "").strip())
        if not preset:
            raise PlayerError("Unknown EQ preset")
        self.eq_bands = list(preset)
        self.eq_preset = str(name)
        self.apply_eq()
        self.on_change()

    def restore_eq(self, preset: str, bands: list | None = None) -> None:
        name = str(preset or "").strip() or "Flat"
        if name == "Custom":
            values = list(bands or [])
            cleaned: list[float] = []
            for index in range(10):
                try:
                    gain = float(values[index]) if index < len(values) else 0.0
                except (TypeError, ValueError):
                    gain = 0.0
                cleaned.append(max(-12.0, min(12.0, round(gain * 2) / 2)))
            self.eq_bands = cleaned
            self.eq_preset = "Custom"
            self.apply_eq(immediate=True)
            self.on_change()
            return
        if name not in EQ_PRESETS:
            name = "Flat"
        preset = EQ_PRESETS[name]
        self.eq_bands = list(preset)
        self.eq_preset = name
        self.apply_eq(immediate=True)
        self.on_change()

    def cycle_eq_preset(self) -> str:
        names = list(EQ_PRESETS.keys())
        if self.eq_preset in names:
            nxt = (names.index(self.eq_preset) + 1) % len(names)
        else:
            nxt = 0
        self.set_eq_preset(names[nxt])
        return names[nxt]

    def play(self) -> None:
        if not self.current:
            raise PlayerError("Nothing is queued")
        self.ensure_started()
        self.mpv.command(["set_property", "pause", False])
        self.playing = True
        self.note_activity()
        self.on_change()

    def pause(self) -> None:
        if not self.mpv.running:
            return
        self.mpv.command(["set_property", "pause", True])
        self.playing = False
        self.note_activity()
        self.on_change()

    def toggle(self) -> None:
        if self.playing:
            self.pause()
        else:
            self.play()

    def stop(self) -> None:
        if self.mpv.running:
            try:
                self.mpv.command(["stop"])
            except Exception:
                pass
        self.playing = False
        self.position_ms = 0
        self.note_activity()
        self.on_change()

    def next(self) -> None:
        self.note_activity()
        if self._advance():
            self._play_current(start=True)
        else:
            self.playing = False
            self.on_change()

    def previous(self) -> None:
        self.note_activity()
        if self.position_ms > 3000 and self.current:
            self.seek(0)
            return
        if self.index > 0:
            self.index -= 1
            self._play_current(start=True)
        elif self.repeat == "context" and self.queue:
            self.index = len(self.queue) - 1
            self._play_current(start=True)
        else:
            self.seek(0)

    def seek(self, position_ms: int) -> None:
        if not self.mpv.running:
            return
        seconds = max(0, int(position_ms or 0)) / 1000.0
        self.mpv.command(["seek", seconds, "absolute"])
        self.position_ms = int(seconds * 1000)
        self.note_activity()
        self.on_change()

    def set_volume(self, volume: int) -> None:
        volume = max(0, min(100, int(volume)))
        self.volume = volume
        self.muted = volume <= 0
        if volume > 0:
            self.volume_before_mute = volume
        if self.mpv.running:
            self.mpv.command(["set_property", "volume", volume])
        self.note_activity()
        self.on_change()

    def set_shuffle(self, value: bool) -> None:
        self.shuffle = bool(value)
        self.note_activity()
        self.on_change()

    def set_repeat(self, mode: str) -> None:
        if mode not in ("off", "context", "track"):
            mode = "off"
        self.repeat = mode
        self.note_activity()
        self.on_change()

    def cycle_repeat(self) -> str:
        nxt = {"off": "context", "context": "track", "track": "off"}[self.repeat]
        self.set_repeat(nxt)
        return nxt

    def set_sleep(self, minutes: float = 0, after: str = "") -> None:
        if after in ("track", "context"):
            self._sleep_after = after
            self._sleep_deadline = 0.0
        elif minutes > 0:
            self._sleep_deadline = time.time() + minutes * 60
            self._sleep_after = ""
        else:
            self._sleep_deadline = 0.0
            self._sleep_after = ""
        self.note_activity()
        self.on_change()

    def sleep_active(self) -> bool:
        return self._sleep_deadline > 0 or bool(self._sleep_after)

    def sleep_remaining_seconds(self) -> int:
        if self._sleep_deadline <= 0:
            return 0
        return max(0, int(self._sleep_deadline - time.time()))

    def note_activity(self) -> None:
        self.last_activity = time.time()

    def _upcoming_video_id(self) -> str:
        nxt = self.index + 1
        if 0 <= nxt < len(self.queue):
            return str(self.queue[nxt].get("videoId") or "")
        return ""

    def _publish_title(self, item: dict | None = None) -> None:
        title = mpris_title(item if item is not None else self.current)
        self._display_title = title
        if not self.mpv.running:
            return
        try:
            self.mpv.command(["set_property", "force-media-title", title])
        except Exception:
            pass

    def _play_current(self, start: bool = True) -> None:
        item = self.current
        if not item:
            raise PlayerError("Nothing is queued")
        video_id = str(item.get("videoId") or "")
        self.error = ""
        self.ensure_started()
        self._publish_title(item)
        # A cold resolve can take a while. Tell the UI before blocking on it so
        # it can show progress instead of looking stalled.
        self.resolving = True
        self.on_change()
        try:
            url = self.resolver.resolve(video_id)
            self._publish_title(item)
            self.mpv.command(loadfile_command(url, item))
            self.mpv.command(["set_property", "pause", not start])
            self.playing = start
            self.position_ms = 0
            self.duration_ms = int(item.get("durationMs") or 0)
        except Exception as exc:
            self.error = str(exc)
            self.playing = False
            self.resolving = False
            self.on_change()
            raise PlayerError(str(exc)) from exc
        finally:
            self.resolving = False
        nxt = self._upcoming_video_id()
        if nxt:
            self.resolver.prefetch(nxt)
        elif self.catalog_radio and len(self.queue) - self.index <= 2:
            self._fill_radio(video_id)
        self._generation += 1
        try:
            self.on_played(item)
        except Exception:
            pass
        self.on_change()

    def _fill_radio(self, video_id: str) -> None:
        def worker() -> None:
            try:
                related = self.catalog_radio(video_id) if self.catalog_radio else []
            except Exception:
                related = []
            if not related:
                return
            with self._lock:
                seen = {str(item.get("videoId") or "") for item in self.queue}
                added = 0
                for item in related:
                    vid = str(item.get("videoId") or "")
                    if not vid or vid in seen:
                        continue
                    self.queue.append(item)
                    seen.add(vid)
                    added += 1
                    if added >= 24:
                        break
                nxt = self._upcoming_video_id()
            if nxt:
                self.resolver.prefetch(nxt)
            if added:
                self.on_change()
        threading.Thread(target=worker, daemon=True).start()

    def _advance(self) -> bool:
        if self._sleep_after == "track":
            self._sleep_after = ""
            return False
        if self.repeat == "track" and self.current:
            return True
        if self.shuffle and len(self.queue) > 1:
            import random
            choices = [i for i in range(len(self.queue)) if i != self.index]
            if not choices:
                return False
            self.index = random.choice(choices)
            return True
        if self.index + 1 < len(self.queue):
            self.index += 1
            return True
        if self.repeat == "context" and self.queue:
            if self._sleep_after == "context":
                self._sleep_after = ""
                return False
            self.index = 0
            return True
        return False

    def _loop(self) -> None:
        while not self._stop.is_set():
            if self._sleep_deadline and time.time() >= self._sleep_deadline:
                self._sleep_deadline = 0.0
                try:
                    self.pause()
                except Exception:
                    pass
                continue
            try:
                events = self.mpv.poll_events(0.25)
            except Exception:
                time.sleep(0.2)
                continue
            changed = False
            eof = False
            for event in events:
                name = event.get("event")
                if name == "property-change":
                    prop = event.get("name")
                    value = event.get("data")
                    if prop == "pause":
                        self.playing = value is False
                        changed = True
                    elif prop == "time-pos" and isinstance(value, (int, float)):
                        self.position_ms = int(max(0, value) * 1000)
                    elif prop == "duration" and isinstance(value, (int, float)) and value > 0:
                        self.duration_ms = int(value * 1000)
                        changed = True
                    elif prop == "volume" and isinstance(value, (int, float)):
                        self.volume = int(max(0, min(100, value)))
                    elif prop == "eof-reached" and value is True:
                        eof = True
                    elif prop == "media-title":
                        shown = str(value or "")
                        if self._display_title and (
                            looks_like_stream_title(shown) or shown != self._display_title
                        ):
                            self._publish_title()
                elif name in ("file-loaded", "playback-restart"):
                    self._publish_title()
                    if name == "playback-restart":
                        self.playing = True
                        self.error = ""
                        changed = True
                elif name == "end-file":
                    reason = str(event.get("reason") or "")
                    if reason in ("eof", "0"):
                        eof = True
                    elif reason == "error":
                        if time.time() < self._eq_guard_until:
                            continue
                        self.playing = False
                        self.error = self.error or "Playback failed"
                        changed = True
            if eof and self.playing:
                if self._advance():
                    try:
                        self._play_current(start=True)
                    except Exception:
                        self.playing = False
                        changed = True
                else:
                    self.playing = False
                    changed = True
            if changed:
                self.on_change()
