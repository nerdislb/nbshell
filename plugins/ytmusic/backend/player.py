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


def quality_format(kbps: int) -> str:
    rate = 96 if kbps <= 96 else (160 if kbps <= 160 else 320)
    return f"bestaudio[abr<={rate}]/bestaudio"


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
        "--title=Omarchy YouTube Music",
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
            "-f", quality_format(self.kbps),
            "-g",
            "--no-playlist",
            "--no-warnings",
            "--no-progress",
            url,
        ]
        if self.cookies_path and self.cookies_path.is_file():
            command[1:1] = ["--cookies", str(self.cookies_path)]
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=40,
            check=False,
        )
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
    ):
        self.mpv = Mpv(runtime_dir / "mpv.sock")
        self.resolver = StreamResolver()
        self.on_change = on_change or (lambda: None)
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
        self.last_activity = time.time()

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
            self.on_change()
            raise PlayerError(str(exc)) from exc
        nxt = self._upcoming_video_id()
        if nxt:
            self.resolver.prefetch(nxt)
        elif self.catalog_radio and len(self.queue) - self.index <= 2:
            self._fill_radio(video_id)
        self._generation += 1
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
