#!/usr/bin/env python3
"""Owner-only Unix socket backend for YouTube Music."""

from __future__ import annotations

import argparse
import os
import signal
import socket
import sys
import threading
import time
import traceback
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import auth
import catalog
import play_history
import protocol
from catalog import AuthRequired, Catalog, CatalogError
from player import PlayerError, QueuePlayer
from protocol import (
    BACKEND_VERSION,
    ERROR_AUTH,
    ERROR_CATALOG,
    ERROR_INVALID_REQUEST,
    ERROR_PLAYBACK,
    ERROR_UNKNOWN_COMMAND,
    ERROR_UNSUPPORTED_VERSION,
    MAX_LINE_BYTES,
    PROTOCOL_VERSION,
    encode_line,
    event,
    parse_line,
    redact,
    response,
)


def runtime_dir() -> Path:
    root = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/omarchy-ytmusic-{os.getuid()}")
    path = root / "omarchy-ytmusic"
    path.mkdir(parents=True, exist_ok=True)
    try:
        path.chmod(0o700)
    except OSError:
        pass
    return path


def socket_path() -> Path:
    return runtime_dir() / "backend.sock"


def idle_should_exit(*, idle_minutes: int, playing: bool, client_count: int,
                     last_activity: float, now: float) -> bool:
    if idle_minutes <= 0 or playing or client_count > 0:
        return False
    return (now - last_activity) >= idle_minutes * 60


class Backend:
    def __init__(self, auth_path: Path | None = None):
        self.auth_path = auth.default_auth_path() if auth_path is None else auth_path
        self.catalog: Catalog | None = None
        self.signed_in = False
        self.account_name = ""
        self.lifecycle = "starting"
        self.error = ""
        self.idle_minutes = 15
        self.quality_kbps = 320
        self.generation = 0
        self._clients: list[socket.socket] = []
        self._clients_lock = threading.Lock()
        self._catalog_lock = threading.Lock()
        self._stop = threading.Event()
        self.player = QueuePlayer(
            runtime_dir(),
            on_change=self._on_player_change,
            catalog_radio=self._radio_tracks,
            on_played=self._remember_play,
        )
        self.local_history = play_history.load()
        self._last_broadcast = 0.0

    def start_catalog(self) -> None:
        from ytmusicapi import YTMusic

        path = auth.resolve_auth_path(str(self.auth_path) if self.auth_path else None)
        self.auth_path = path
        try:
            if auth.auth_available(path):
                self.catalog = Catalog(YTMusic(str(path)))
                self.signed_in = True
                cookies = auth.export_cookies(path)
                self.player.resolver.set_cookies(cookies)
                try:
                    info = self.catalog.account()
                    self.account_name = info.get("name") or ""
                except Exception:
                    self.account_name = ""
            else:
                self.catalog = Catalog(YTMusic())
                self.signed_in = False
                self.account_name = ""
            self.lifecycle = "ready"
            self.error = ""
        except Exception as exc:
            try:
                self.catalog = Catalog(YTMusic())
                self.signed_in = False
                self.lifecycle = "ready"
                self.error = redact(str(exc))
            except Exception as inner:
                self.catalog = None
                self.lifecycle = "error"
                self.error = redact(str(inner))

    def state(self) -> dict[str, Any]:
        track = self.player.snapshot_track()
        return {
            "lifecycle": self.lifecycle,
            "backend_version": BACKEND_VERSION,
            "protocol_version": PROTOCOL_VERSION,
            "signed_in": self.signed_in,
            "account_name": self.account_name,
            "playing": self.player.playing,
            "resolving": self.player.resolving,
            "shuffle": self.player.shuffle,
            "repeat": self.player.repeat,
            "volume": self.player.volume,
            "muted": self.player.muted,
            "position_ms": self.player.position_ms,
            "duration_ms": self.player.duration_ms,
            "track": track,
            "queue": list(self.player.queue),
            "queue_index": self.player.index,
            "sleep_active": self.player.sleep_active(),
            "sleep_remaining": self.player.sleep_remaining_seconds(),
            "idle_minutes": self.idle_minutes,
            "quality_kbps": self.quality_kbps,
            "eq": self.player.eq_snapshot(),
            "generation": self.generation,
            "error": self.error or self.player.error,
            "play_history": list(self.local_history),
        }

    def broadcast(self) -> None:
        self.generation += 1
        data = encode_line(event("state_changed", self.state()))
        with self._clients_lock:
            living = []
            for client in self._clients:
                try:
                    client.sendall(data)
                    living.append(client)
                except OSError:
                    try:
                        client.close()
                    except OSError:
                        pass
            self._clients[:] = living
        self._last_broadcast = time.time()

    def _on_player_change(self) -> None:
        now = time.time()
        # Position-only ticks are already sent on a 1s timer. Coalesce bursts.
        if now - self._last_broadcast < 0.05:
            return
        self.broadcast()

    def _radio_tracks(self, video_id: str) -> list[dict]:
        if not self.catalog:
            return []
        with self._catalog_lock:
            return self.catalog.watch_playlist(video_id)

    def _remember_play(self, item: dict) -> None:
        self.local_history = play_history.remember(item, self.local_history)

    def handle(self, message: dict[str, Any]) -> dict[str, Any]:
        version = message.get("v", PROTOCOL_VERSION)
        request_id = message.get("id")
        if version != PROTOCOL_VERSION:
            return response(request_id, False, code=ERROR_UNSUPPORTED_VERSION,
                            message="This plugin backend speaks protocol 1")
        command = str(message.get("command") or "").strip()
        try:
            result = self.dispatch(command, message)
            return response(request_id, True, result)
        except AuthRequired as exc:
            self._invalidate_session()
            return response(request_id, False, code=ERROR_AUTH, message=str(exc))
        except AuthError as exc:
            return response(request_id, False, code=ERROR_AUTH, message=str(exc))
        except CatalogError as exc:
            return response(request_id, False, code=ERROR_CATALOG, message=str(exc))
        except PlayerError as exc:
            return response(request_id, False, code=ERROR_PLAYBACK, message=str(exc))
        except ValueError as exc:
            return response(request_id, False, code=ERROR_INVALID_REQUEST, message=str(exc))
        except Exception as exc:
            traceback.print_exc()
            return response(request_id, False, code=ERROR_INVALID_REQUEST,
                            message=redact(str(exc)))

    def dispatch(self, command: str, message: dict[str, Any]) -> dict[str, Any]:
        self.player.note_activity()
        if command in ("hello", "ping", "get_state"):
            return self.state()
        if command == "setup_auth":
            return self.setup_auth(str(message.get("headers_raw") or ""))
        if command == "import_browser":
            return self.import_browser()
        if command == "logout":
            return self.logout()
        if command == "set_idle_minutes":
            self.idle_minutes = max(0, min(1440, int(message.get("minutes") or 0)))
            return self.state()
        if command == "set_quality":
            self.quality_kbps = 96 if int(message.get("kbps") or 320) <= 96 else (
                160 if int(message.get("kbps") or 320) <= 160 else 320)
            self.player.resolver.set_quality(self.quality_kbps)
            return self.state()
        if command == "play":
            self.player.play()
            return self.state()
        if command == "pause":
            self.player.pause()
            return self.state()
        if command == "toggle":
            self.player.toggle()
            return self.state()
        if command == "stop":
            self.player.stop()
            return self.state()
        if command == "next":
            self.player.next()
            return self.state()
        if command == "previous":
            self.player.previous()
            return self.state()
        if command == "seek":
            self.player.seek(int(message.get("position_ms") or 0))
            return self.state()
        if command == "set_volume":
            volume = message.get("volume")
            if volume is None:
                volume = message.get("value")
            self.player.set_volume(int(volume if volume is not None else 80))
            return self.state()
        if command == "set_shuffle":
            self.player.set_shuffle(bool(message.get("shuffle")))
            return self.state()
        if command == "set_repeat":
            self.player.set_repeat(str(message.get("mode") or "off"))
            return self.state()
        if command == "load":
            return self.load(message)
        if command == "add_to_queue":
            item = message.get("item") or {}
            if not isinstance(item, dict):
                raise ValueError("item is required")
            self.player.add_to_queue(item)
            return {"queue": list(self.player.queue)}
        if command == "reorder_queue":
            self.player.reorder_queue(
                int(message.get("source_index") or 0),
                int(message.get("destination_index") or 0),
            )
            return {"queue": list(self.player.queue), "index": self.player.index}
        if command == "set_eq_band":
            self.player.set_eq_band(
                int(message.get("index") or 0),
                float(message.get("gain") or 0),
            )
            return self.player.eq_snapshot()
        if command == "set_eq_preset":
            self.player.set_eq_preset(str(message.get("name") or ""))
            return self.player.eq_snapshot()
        if command == "cycle_eq_preset":
            name = self.player.cycle_eq_preset()
            return self.player.eq_snapshot() | {"preset": name}
        if command == "restore_eq":
            self.player.restore_eq(
                str(message.get("preset") or "Flat"),
                message.get("bands"),
            )
            return self.player.eq_snapshot()
        if command == "search":
            return self.require_catalog().search(
                str(message.get("query") or ""),
                str(message.get("filter") or ""),
                int(message.get("limit") or 24),
            )
        if command == "browse":
            return self.browse(
                str(message.get("view") or "home"),
                force=bool(message.get("force")),
            )
        if command == "get_playlist":
            return self.require_catalog().playlist(str(message.get("item_id") or ""))
        if command == "get_album":
            return self.require_catalog().album(str(message.get("item_id") or ""))
        if command == "get_artist":
            return self.require_catalog().artist(str(message.get("item_id") or ""))
        if command == "get_queue":
            return {"items": list(self.player.queue), "index": self.player.index}
        if command == "like":
            return self.like(str(message.get("video_id") or ""), bool(message.get("liked")))
        if command == "create_playlist":
            item = self.require_catalog().create_playlist(str(message.get("name") or ""))
            return {"playlist": item}
        if command == "add_to_playlist":
            self.require_catalog().add_to_playlist(
                str(message.get("playlist_id") or ""),
                str(message.get("video_id") or ""),
            )
            return {}
        if command == "sleep":
            self.player.set_sleep(
                minutes=float(message.get("minutes") or 0),
                after=str(message.get("after") or ""),
            )
            return self.state()
        if command == "cancel_sleep":
            self.player.set_sleep(0, "")
            return self.state()
        if not command:
            raise ValueError("missing command")
        raise ValueError(f"Unknown command: {command}")

    def require_catalog(self) -> Catalog:
        if not self.catalog:
            raise CatalogError("YouTube Music is unavailable")
        return self.catalog

    def setup_auth(self, headers_raw: str) -> dict[str, Any]:
        if not headers_raw.strip():
            raise AuthError("Paste the request headers from music.youtube.com")
        try:
            path = auth.save_headers(headers_raw, auth.default_auth_path())
        except Exception as exc:
            raise AuthError(redact(str(exc))) from exc
        return self._activate_auth(path)

    def import_browser(self) -> dict[str, Any]:
        try:
            path = auth.import_from_browser(auth.default_auth_path())
        except auth.BrowserAuthError as exc:
            raise AuthError(str(exc)) from exc
        except Exception as exc:
            raise AuthError(redact(str(exc))) from exc
        return self._activate_auth(path)

    def _activate_auth(self, path: Path) -> dict[str, Any]:
        self.auth_path = path
        self.start_catalog()
        if not self.signed_in:
            raise AuthError(self.error or "Those headers were not accepted")
        self.broadcast()
        return self.state()

    def logout(self) -> dict[str, Any]:
        try:
            self.player.stop()
        except Exception:
            pass
        auth.clear_auth(self.auth_path)
        self.start_catalog()
        self.broadcast()
        return self.state()

    def browse(self, view: str, force: bool = False) -> dict[str, Any]:
        cat = self.require_catalog()
        with self._catalog_lock:
            if view == "home":
                return {"home": cat.home(force=force), "signed_in": self.signed_in}
            if view == "history":
                remote = cat.history() if self.signed_in else []
                return {"items": play_history.merge(self.local_history, remote)}
            if view == "liked":
                return {"items": cat.liked()}
            if view == "playlists":
                return {"items": cat.playlists()}
            if view == "library_songs":
                return {"items": cat.library_songs()}
            if view == "library_albums":
                return {"items": cat.library_albums()}
            if view == "library_artists":
                return {"items": cat.library_artists()}
            if view == "library":
                return {
                    "songs": cat.library_songs(),
                    "albums": cat.library_albums(),
                    "artists": cat.library_artists(),
                    "playlists": cat.playlists(),
                    "liked": cat.liked(),
                    "history": cat.history(),
                }
        raise ValueError(f"Unknown view: {view}")

    def like(self, video_id: str, liked: bool) -> dict[str, Any]:
        if not video_id:
            raise ValueError("video_id is required")
        if not self.signed_in:
            raise AuthError("Sign in to like songs")
        try:
            self.require_catalog().rate_song(video_id, liked)
        except AuthRequired as exc:
            self._invalidate_session()
            raise AuthError(str(exc)) from exc
        current = self.player.current
        if current and current.get("videoId") == video_id:
            current["liked"] = liked
        self.broadcast()
        return {"liked": liked}

    def _invalidate_session(self) -> None:
        if not self.signed_in and not self.account_name:
            return
        self.signed_in = False
        self.account_name = ""
        self.broadcast()

    def load(self, message: dict[str, Any]) -> dict[str, Any]:
        items = message.get("items")
        index = int(message.get("index") or message.get("offset_index") or 0)
        radio = message.get("radio") is True
        video_id = str(message.get("video_id") or "")
        playlist_id = str(message.get("playlist_id") or "")
        album_id = str(message.get("album_id") or "")
        artist_id = str(message.get("artist_id") or "")
        play = message.get("play", True) is not False

        resolved: list[dict] = []
        if isinstance(items, list) and items:
            resolved = [item for item in items if isinstance(item, dict) and item.get("videoId")]
        elif playlist_id:
            resolved = self.require_catalog().playlist(playlist_id).get("tracks") or []
        elif album_id:
            resolved = self.require_catalog().album(album_id).get("tracks") or []
        elif artist_id:
            detail = self.require_catalog().artist(artist_id)
            resolved = detail.get("tracks") or []
            if not resolved and detail.get("radioId"):
                resolved = self.require_catalog().playlist(str(detail["radioId"])).get("tracks") or []
        elif video_id:
            seed = {
                "kind": "item",
                "type": "track",
                "id": video_id,
                "uri": f"ytm:track:{video_id}",
                "name": str(message.get("name") or "YouTube Music"),
                "subtitle": str(message.get("subtitle") or ""),
                "videoId": video_id,
                "externalUrl": f"https://music.youtube.com/watch?v={video_id}",
            }
            if radio or True:
                related = self._radio_tracks(video_id)
                resolved = related or [seed]
                if resolved and resolved[0].get("videoId") != video_id:
                    resolved = [seed] + [item for item in resolved if item.get("videoId") != video_id]
            else:
                resolved = [seed]
            index = 0

        if not resolved:
            raise PlayerError("Nothing playable was found")
        if video_id:
            for i, item in enumerate(resolved):
                if item.get("videoId") == video_id:
                    index = i
                    break
        self.player.load(resolved, index=index, play=play)
        return self.state()

    def serve(self, path: Path) -> None:
        if path.exists():
            try:
                path.unlink()
            except OSError:
                pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(path))
        os.chmod(path, 0o600)
        server.listen(8)
        server.settimeout(0.5)
        print(f"ytmusic-backend listening on {path}", file=sys.stderr)
        idle_thread = threading.Thread(target=self._idle_watch, daemon=True)
        idle_thread.start()
        position_thread = threading.Thread(target=self._position_watch, daemon=True)
        position_thread.start()
        catalog_thread = threading.Thread(target=self._start_catalog_locked, daemon=True)
        catalog_thread.start()
        try:
            while not self._stop.is_set():
                try:
                    client, _ = server.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                thread = threading.Thread(target=self._client_loop, args=(client,), daemon=True)
                thread.start()
        finally:
            self._stop.set()
            self.player.shutdown()
            try:
                server.close()
            except OSError:
                pass
            if path.exists():
                try:
                    path.unlink()
                except OSError:
                    pass

    def _start_catalog_locked(self) -> None:
        self.start_catalog()
        self.broadcast()
        self._warm_stream_cache()

    def _catalog_video_id(self) -> str:
        """Any real videoId from the catalog.

        Used so warming yt-dlp needs no hardcoded video that could later be
        taken down or blocked in the user's region.
        """
        if not self.catalog:
            return ""
        for view in ("history", "liked", "home"):
            try:
                with self._catalog_lock:
                    if view == "home":
                        items = [track for shelf in self.catalog.home() or []
                                 for track in (shelf.get("tracks") or [])]
                    else:
                        items = getattr(self.catalog, view)()
            except Exception:
                continue
            for item in items or []:
                video_id = str((item or {}).get("videoId") or "")
                if video_id:
                    return video_id
        return ""

    def _warm_stream_cache(self) -> None:
        """Solve YouTube's player JS challenge before the user presses play.

        The first resolve against a new player build is slow enough to look
        like a failure. Doing it in the background at startup means the first
        deliberate play is already fast.
        """
        from player import yt_dlp_cache_warm

        if yt_dlp_cache_warm():
            return

        def worker() -> None:
            video_id = self._catalog_video_id()
            if not video_id or self._stop.is_set():
                return
            print("ytmusic-backend warming yt-dlp player cache",
                  file=sys.stderr)
            try:
                self.player.resolver.resolve(video_id)
            except Exception:
                pass

        threading.Thread(target=worker, daemon=True).start()

    def _client_loop(self, client: socket.socket) -> None:
        client.settimeout(1.0)
        self.player.note_activity()
        with self._clients_lock:
            self._clients.append(client)
        try:
            client.sendall(encode_line(event("state_changed", self.state())))
        except OSError:
            self._drop(client)
            return
        buffer = b""
        while not self._stop.is_set():
            try:
                chunk = client.recv(65536)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            buffer += chunk
            if len(buffer) > MAX_LINE_BYTES and b"\n" not in buffer:
                break
            while b"\n" in buffer:
                raw, buffer = buffer.split(b"\n", 1)
                if len(raw) > MAX_LINE_BYTES:
                    self._drop(client)
                    return
                message = parse_line(raw.decode("utf-8", errors="replace"))
                if not message:
                    continue
                reply = self.handle(message)
                try:
                    client.sendall(encode_line(reply))
                except OSError:
                    self._drop(client)
                    return
        self._drop(client)

    def _drop(self, client: socket.socket) -> None:
        with self._clients_lock:
            self._clients = [item for item in self._clients if item is not client]
        try:
            client.close()
        except OSError:
            pass

    def _idle_watch(self) -> None:
        while not self._stop.is_set():
            time.sleep(15)
            with self._clients_lock:
                clients = len(self._clients)
            if idle_should_exit(
                idle_minutes=self.idle_minutes,
                playing=self.player.playing,
                client_count=clients,
                last_activity=self.player.last_activity,
                now=time.time(),
            ):
                print("ytmusic-backend idle shutdown", file=sys.stderr)
                self._stop.set()
                return

    def _position_watch(self) -> None:
        while not self._stop.is_set():
            time.sleep(1.0)
            if self.player.playing:
                self.broadcast()


class AuthError(RuntimeError):
    pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="YouTube Music backend")
    parser.add_argument("--auth", default="", help="Path to ytmusicapi browser.json")
    parser.add_argument("--socket", default="", help="Unix socket path")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        from catalog import duration_ms, track_item
        sample = {
            "title": "Test Song",
            "videoId": "dQw4w9wgkcQ",
            "artists": [{"name": "Artist", "id": "UC123"}],
            "duration": "3:45",
            "thumbnails": [{"url": "https://example.com/a.jpg", "width": 226}],
        }
        item = track_item(sample)
        assert item and item["durationMs"] == 225000
        assert duration_ms({"duration": "1:02:03"}) == 3723000
        probe = encode_line(event("state_changed", {"lifecycle": "ready"}))
        assert probe.endswith(b"\n")
        assert b"lifecycle" in probe
        print("ok")
        return 0

    auth_path = Path(os.path.expanduser(args.auth)) if args.auth else None
    backend = Backend(auth_path)

    def handle_stop(signum, frame):
        backend._stop.set()

    signal.signal(signal.SIGTERM, handle_stop)
    signal.signal(signal.SIGINT, handle_stop)
    path = Path(args.socket) if args.socket else socket_path()
    backend.serve(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
