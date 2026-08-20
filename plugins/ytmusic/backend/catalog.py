"""Normalize YouTube Music catalog objects for the Quickshell UI."""

from __future__ import annotations

import re
from typing import Any

WATCH_BASE = "https://music.youtube.com/watch?v="
PLAYLIST_BASE = "https://music.youtube.com/playlist?list="
CHANNEL_BASE = "https://music.youtube.com/channel/"
BROWSE_BASE = "https://music.youtube.com/browse/"


def _text(value: Any) -> str:
    return str(value or "").strip()


def _first_dict(value: Any) -> dict:
    return value if isinstance(value, dict) else {}


def duration_ms(item: dict | None) -> int:
    source = item or {}
    seconds = source.get("duration_seconds")
    if seconds is None:
        seconds = source.get("lengthSeconds")
    try:
        if seconds is not None and str(seconds) != "":
            return max(0, int(float(seconds))) * 1000
    except (TypeError, ValueError):
        pass
    text = _text(source.get("duration") or source.get("length"))
    if not text:
        return 0
    parts = text.split(":")
    try:
        values = [int(part) for part in parts]
    except ValueError:
        return 0
    total = 0
    for part in values:
        total = total * 60 + part
    return total * 1000


def thumbnail_url(item: dict | None, min_width: int = 120) -> str:
    source = item or {}
    thumbs = source.get("thumbnails") or source.get("thumbnail")
    if isinstance(thumbs, dict):
        thumbs = thumbs.get("thumbnails") or thumbs.get("url")
    if isinstance(thumbs, str):
        return thumbs
    if not isinstance(thumbs, list) or not thumbs:
        album = source.get("album")
        if isinstance(album, dict):
            return thumbnail_url(album, min_width)
        return ""
    chosen = ""
    chosen_width = -1
    for thumb in thumbs:
        if isinstance(thumb, str) and thumb:
            chosen = thumb
            continue
        if not isinstance(thumb, dict):
            continue
        url = _text(thumb.get("url"))
        if not url:
            continue
        width = int(thumb.get("width") or 0)
        if width >= min_width and width >= chosen_width:
            chosen = url
            chosen_width = width
        elif chosen_width < 0:
            chosen = url
            chosen_width = width
    return chosen


def artist_entries(item: dict | None) -> list[dict]:
    source = item or {}
    artists = source.get("artists")
    if artists is None:
        artists = source.get("author")
    if isinstance(artists, dict):
        artists = [artists]
    if not isinstance(artists, list):
        name = _text(source.get("artist"))
        return [{"id": "", "name": name, "type": "artist", "kind": "context"}] if name else []
    result = []
    for artist in artists:
        if isinstance(artist, str):
            name = artist.strip()
            if name:
                result.append({"id": "", "name": name, "type": "artist", "kind": "context"})
            continue
        if not isinstance(artist, dict):
            continue
        name = _text(artist.get("name"))
        if not name:
            continue
        result.append({
            "id": _text(artist.get("id") or artist.get("channelId")),
            "name": name,
            "type": "artist",
            "kind": "context",
            "uri": artist_uri(_text(artist.get("id") or artist.get("channelId"))),
        })
    return result


def artist_names(item: dict | None) -> str:
    return ", ".join(entry["name"] for entry in artist_entries(item) if entry.get("name"))


def album_item(item: dict | None) -> dict | None:
    source = item or {}
    album = source.get("album")
    if isinstance(album, str) and album.strip():
        return {
            "kind": "context",
            "type": "album",
            "id": "",
            "uri": "",
            "name": album.strip(),
            "subtitle": artist_names(source),
            "imageUrl": thumbnail_url(source),
        }
    if not isinstance(album, dict):
        return None
    album_id = _text(album.get("id") or album.get("browseId") or album.get("audioPlaylistId"))
    name = _text(album.get("name") or album.get("title"))
    if not name and not album_id:
        return None
    return {
        "kind": "context",
        "type": "album",
        "id": album_id,
        "uri": album_uri(album_id),
        "name": name or "Album",
        "subtitle": artist_names(source),
        "imageUrl": thumbnail_url(album) or thumbnail_url(source),
        "externalUrl": browse_url(album_id),
    }


def video_id_of(item: dict | None) -> str:
    source = item or {}
    video_id = _text(source.get("videoId") or source.get("video_id"))
    if video_id:
        return video_id
    candidate = source.get("id")
    return _text(candidate) if _looks_like_video(candidate) else ""


def _looks_like_video(value: Any) -> bool:
    text = _text(value)
    return bool(re.fullmatch(r"[A-Za-z0-9_-]{11}", text))


def playlist_id_of(item: dict | None) -> str:
    source = item or {}
    return _text(
        source.get("playlistId")
        or source.get("audioPlaylistId")
        or source.get("browseId")
        or (source.get("id") if not _looks_like_video(source.get("id")) else "")
    )


def track_uri(video_id: str) -> str:
    return f"ytm:track:{video_id}" if video_id else ""


def playlist_uri(playlist_id: str) -> str:
    return f"ytm:playlist:{playlist_id}" if playlist_id else ""


def album_uri(album_id: str) -> str:
    return f"ytm:album:{album_id}" if album_id else ""


def artist_uri(artist_id: str) -> str:
    return f"ytm:artist:{artist_id}" if artist_id else ""


def watch_url(video_id: str) -> str:
    return WATCH_BASE + video_id if video_id else ""


def playlist_url(playlist_id: str) -> str:
    return PLAYLIST_BASE + playlist_id if playlist_id else ""


def browse_url(browse_id: str) -> str:
    if not browse_id:
        return ""
    if browse_id.startswith("UC"):
        return CHANNEL_BASE + browse_id
    if browse_id.startswith("PL") or browse_id.startswith("OL") or browse_id.startswith("RD"):
        return playlist_url(browse_id)
    return BROWSE_BASE + browse_id


def liked_flag(item: dict | None) -> bool:
    status = _text((item or {}).get("likeStatus") or (item or {}).get("like_status")).upper()
    return status == "LIKE"


def track_item(raw: Any, fallback_type: str = "track") -> dict | None:
    if not isinstance(raw, dict):
        return None
    result_type = _text(raw.get("resultType") or raw.get("type") or fallback_type).lower()
    if result_type in ("artist",):
        return context_item(raw, "artist")
    if result_type in ("album", "ep", "single"):
        return context_item(raw, "album")
    if result_type in ("playlist",):
        return context_item(raw, "playlist")
    video_id = _text(raw.get("videoId") or raw.get("video_id"))
    if not video_id and _looks_like_video(raw.get("id")) and result_type in ("", "song", "video", "track"):
        video_id = _text(raw.get("id"))
    title = _text(raw.get("title") or raw.get("name"))
    if not title:
        return None
    if not video_id:
        if result_type in ("album", "playlist", "artist"):
            return context_item(raw, result_type)
        return None
    artists = artist_entries(raw)
    album = album_item(raw)
    duration = duration_ms(raw)
    playlist_id = _text(raw.get("playlistId"))
    return {
        "kind": "item",
        "type": "track",
        "id": video_id,
        "uri": track_uri(video_id),
        "name": title,
        "subtitle": artist_names(raw),
        "album": (album or {}).get("name") or "",
        "artists": artists,
        "albumItem": album,
        "imageUrl": thumbnail_url(raw),
        "durationMs": duration,
        "videoId": video_id,
        "playlistId": playlist_id,
        "externalUrl": watch_url(video_id),
        "liked": liked_flag(raw),
        "setVideoId": _text(raw.get("setVideoId")),
    }


def context_item(raw: Any, forced_type: str = "") -> dict | None:
    if not isinstance(raw, dict):
        return None
    item_type = (forced_type or _text(raw.get("resultType") or raw.get("type"))).lower()
    if item_type in ("ep", "single"):
        item_type = "album"
    if item_type not in ("album", "artist", "playlist"):
        if raw.get("browseId") and raw.get("artists"):
            item_type = "album"
        elif raw.get("subscribers") or raw.get("channelId"):
            item_type = "artist"
        elif raw.get("playlistId") or str(raw.get("id") or "").startswith("PL"):
            item_type = "playlist"
        else:
            return None
    name = _text(raw.get("title") or raw.get("name") or raw.get("artist"))
    if not name:
        return None
    item_id = _text(
        raw.get("browseId")
        or raw.get("channelId")
        or raw.get("playlistId")
        or raw.get("audioPlaylistId")
        or raw.get("id")
    )
    uri = {
        "album": album_uri(item_id),
        "artist": artist_uri(item_id),
        "playlist": playlist_uri(item_id),
    }[item_type]
    subtitle = artist_names(raw)
    if item_type == "artist":
        subtitle = _text(raw.get("subscribers") or raw.get("subtitle"))
    elif item_type == "playlist":
        subtitle = _text(raw.get("author") if isinstance(raw.get("author"), str)
                         else (raw.get("author") or {}).get("name") if isinstance(raw.get("author"), dict)
                         else subtitle)
        count = raw.get("count") or raw.get("trackCount")
        if count:
            subtitle = (subtitle + " · " if subtitle else "") + f"{count} songs"
    return {
        "kind": "context",
        "type": item_type,
        "id": item_id,
        "uri": uri,
        "name": name,
        "subtitle": subtitle,
        "album": name if item_type == "album" else "",
        "artists": artist_entries(raw),
        "imageUrl": thumbnail_url(raw),
        "durationMs": duration_ms(raw),
        "videoId": "",
        "playlistId": item_id if item_type == "playlist" else _text(raw.get("audioPlaylistId") or raw.get("playlistId")),
        "externalUrl": browse_url(item_id) or playlist_url(item_id),
        "liked": False,
        "year": _text(raw.get("year")),
        "description": _text(raw.get("description")),
    }


def normalize_item(raw: Any) -> dict | None:
    if not isinstance(raw, dict):
        return None
    result_type = _text(raw.get("resultType") or raw.get("type")).lower()
    if result_type in ("artist", "album", "playlist", "ep", "single"):
        return context_item(raw, "album" if result_type in ("ep", "single") else result_type)
    if raw.get("videoId") or _looks_like_video(raw.get("id")):
        return track_item(raw)
    return context_item(raw) or track_item(raw)


def map_items(values: Any, limit: int = 0) -> list[dict]:
    if isinstance(values, dict):
        values = values.get("tracks") or values.get("results") or values.get("contents") or values.get("items") or []
    if not isinstance(values, list):
        return []
    out: list[dict] = []
    for raw in values:
        item = normalize_item(raw)
        if not item:
            continue
        out.append(item)
        if limit and len(out) >= limit:
            break
    return out


def shelf_from_home(raw: Any, track_limit: int = 12) -> dict | None:
    if not isinstance(raw, dict):
        return None
    title = _text(raw.get("title"))
    tracks = map_items(raw.get("contents"), limit=track_limit)
    if not tracks:
        return None
    return {"title": title or "Home", "tracks": tracks}


class Catalog:
    def __init__(self, ytmusic):
        self.yt = ytmusic

    def account(self) -> dict:
        try:
            info = self.yt.get_account_info() or {}
        except Exception:
            info = {}
        name = _text(
            info.get("accountName")
            or info.get("name")
            or (info.get("account") or {}).get("name")
        )
        return {"name": name, "raw": info}

    def home(self, limit: int = 6) -> list[dict]:
        try:
            shelves = self.yt.get_home(limit=limit)
        except Exception:
            shelves = []
        out = []
        for shelf in shelves or []:
            mapped = shelf_from_home(shelf)
            if mapped:
                out.append(mapped)
            if len(out) >= limit:
                break
        return out

    def history(self, limit: int = 40) -> list[dict]:
        try:
            raw = self.yt.get_history()
        except Exception:
            raw = []
        return map_items(raw, limit=limit)

    def liked(self, limit: int = 50) -> list[dict]:
        try:
            raw = self.yt.get_liked_songs(limit=limit)
        except Exception:
            raw = {}
        return map_items(raw, limit=limit)

    def playlists(self, limit: int = 50) -> list[dict]:
        try:
            raw = self.yt.get_library_playlists(limit=limit)
        except Exception:
            raw = []
        return [item for item in map_items(raw, limit=limit) if item.get("type") == "playlist" or item.get("kind") == "context"]

    def library_songs(self, limit: int = 50) -> list[dict]:
        try:
            raw = self.yt.get_library_songs(limit=limit)
        except Exception:
            raw = []
        return map_items(raw, limit=limit)

    def library_albums(self, limit: int = 50) -> list[dict]:
        try:
            raw = self.yt.get_library_albums(limit=limit)
        except Exception:
            raw = []
        return map_items(raw, limit=limit)

    def library_artists(self, limit: int = 50) -> list[dict]:
        try:
            raw = self.yt.get_library_artists(limit=limit)
        except Exception:
            raw = []
        return map_items(raw, limit=limit)

    def search(self, query: str, filter_name: str = "", limit: int = 24) -> dict:
        query = _text(query)
        if not query:
            return {"items": [], "sections": []}
        filter_name = _text(filter_name).lower()
        if filter_name in ("track", "song", "songs"):
            filter_name = "songs"
        if filter_name in ("album",):
            filter_name = "albums"
        if filter_name in ("artist",):
            filter_name = "artists"
        if filter_name in ("playlist",):
            filter_name = "playlists"
        if filter_name in ("songs", "albums", "artists", "playlists", "videos"):
            try:
                raw = self.yt.search(query, filter=filter_name, limit=limit)
            except Exception:
                raw = []
            items = map_items(raw, limit=limit)
            title = {
                "songs": "Songs",
                "albums": "Albums",
                "artists": "Artists",
                "playlists": "Playlists",
                "videos": "Videos",
            }[filter_name]
            return {"items": items, "sections": [{"title": title, "items": items}]}

        sections = []
        all_items = []
        for name, title in (("songs", "Songs"), ("albums", "Albums"),
                            ("artists", "Artists"), ("playlists", "Playlists")):
            try:
                raw = self.yt.search(query, filter=name, limit=min(8, limit))
            except Exception:
                raw = []
            items = map_items(raw, limit=min(8, limit))
            if items:
                sections.append({"title": title, "items": items})
                all_items.extend(items)
        return {"items": all_items, "sections": sections}

    def playlist(self, playlist_id: str, limit: int = 200) -> dict:
        playlist_id = _text(playlist_id)
        try:
            raw = self.yt.get_playlist(playlist_id, limit=limit)
        except Exception as exc:
            raise CatalogError(str(exc)) from exc
        header = context_item(raw, "playlist") or {
            "kind": "context",
            "type": "playlist",
            "id": playlist_id,
            "uri": playlist_uri(playlist_id),
            "name": _text(raw.get("title")) or "Playlist",
            "subtitle": "",
            "imageUrl": thumbnail_url(raw),
            "externalUrl": playlist_url(playlist_id),
            "playlistId": playlist_id,
        }
        tracks = map_items(raw.get("tracks"), limit=limit)
        header["tracks"] = tracks
        return header

    def album(self, album_id: str) -> dict:
        album_id = _text(album_id)
        try:
            raw = self.yt.get_album(album_id)
        except Exception as exc:
            raise CatalogError(str(exc)) from exc
        header = context_item(raw, "album") or {
            "kind": "context",
            "type": "album",
            "id": album_id,
            "uri": album_uri(album_id),
            "name": _text(raw.get("title")) or "Album",
            "subtitle": artist_names(raw),
            "imageUrl": thumbnail_url(raw),
        }
        tracks = map_items(raw.get("tracks"))
        for track in tracks:
            if not track.get("imageUrl"):
                track["imageUrl"] = header.get("imageUrl") or ""
            if not track.get("album"):
                track["album"] = header.get("name") or ""
            if not track.get("albumItem"):
                track["albumItem"] = {
                    "kind": "context",
                    "type": "album",
                    "id": album_id,
                    "uri": album_uri(album_id),
                    "name": header.get("name") or "",
                }
        header["tracks"] = tracks
        header["playlistId"] = _text(raw.get("audioPlaylistId") or raw.get("playlistId"))
        return header

    def artist(self, artist_id: str) -> dict:
        artist_id = _text(artist_id)
        try:
            raw = self.yt.get_artist(artist_id)
        except Exception as exc:
            raise CatalogError(str(exc)) from exc
        header = context_item(raw, "artist") or {
            "kind": "context",
            "type": "artist",
            "id": artist_id,
            "uri": artist_uri(artist_id),
            "name": _text(raw.get("name")) or "Artist",
            "subtitle": _text(raw.get("subscribers")),
            "imageUrl": thumbnail_url(raw),
            "description": _text(raw.get("description")),
        }
        songs = map_items((raw.get("songs") or {}).get("results") or [], limit=20)
        albums = map_items((raw.get("albums") or {}).get("results") or [], limit=20)
        singles = map_items((raw.get("singles") or {}).get("results") or [], limit=12)
        header["tracks"] = songs
        header["albums"] = albums
        header["singles"] = singles
        header["shuffleId"] = _text(raw.get("shuffleId"))
        header["radioId"] = _text(raw.get("radioId"))
        return header

    def watch_playlist(self, video_id: str, limit: int = 50) -> list[dict]:
        video_id = _text(video_id)
        try:
            raw = self.yt.get_watch_playlist(videoId=video_id, limit=limit)
        except Exception:
            return []
        return map_items((raw or {}).get("tracks"), limit=limit)

    def lyrics_browse_id(self, video_id: str) -> str:
        try:
            raw = self.yt.get_watch_playlist(videoId=video_id, limit=1)
        except Exception:
            return ""
        return _text((raw or {}).get("lyrics"))

    def rate_song(self, video_id: str, liked: bool) -> None:
        rating = "LIKE" if liked else "INDIFFERENT"
        self.yt.rate_song(video_id, rating)

    def create_playlist(self, name: str) -> dict:
        name = _text(name) or "New playlist"
        playlist_id = self.yt.create_playlist(name, "")
        playlist_id = _text(playlist_id)
        return {
            "kind": "context",
            "type": "playlist",
            "id": playlist_id,
            "uri": playlist_uri(playlist_id),
            "name": name,
            "subtitle": "Your playlist",
            "playlistId": playlist_id,
            "externalUrl": playlist_url(playlist_id),
        }

    def add_to_playlist(self, playlist_id: str, video_id: str) -> None:
        self.yt.add_playlist_items(playlist_id, [video_id])


class CatalogError(RuntimeError):
    pass
