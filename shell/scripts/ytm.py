#!/usr/bin/env python3
"""YouTube Music: Mediathek, Playlists, Suche.

Dieselbe Arbeitsteilung wie bei LocalSend (scripts/nearby.py): hier steht
alles, was mit dem fremden Dienst redet, und heraus kommt JSON. Die Shell
zeigt nur an. Wer das Skript von Hand aufruft, sieht genau das, was die
Oberflaeche sieht -- das ist bei einer Schnittstelle, die sich ohne
Vorwarnung aendern kann, die halbe Fehlersuche.

Gesprochen wird ueber `ytmusicapi`. Das ist KEINE offizielle Schnittstelle:
sie ahmt nach, was die Weboberflaeche tut. Alles andere in nbshell steht auf
Systemprotokollen (MPRIS, PipeWire, ext-idle-notify) und bricht nicht; das
hier kann brechen, wenn Google etwas umbaut. Deshalb hat jeder Fehler einen
lesbaren Grund und keinen Stapelabzug.

ANMELDUNG. ytmusicapi meldet sich mit den Cookies eines angemeldeten
Browsers an, nicht mit Benutzername und Passwort -- YouTube Music hat keinen
Weg fuer fremde Programme. Einmal einrichten:

    1. music.youtube.com im Browser oeffnen, angemeldet sein
    2. Entwicklerwerkzeuge (F12) -> Netzwerk
    3. irgendeine Anfrage an music.youtube.com anklicken
    4. Rechtsklick -> Copy -> Copy request headers
    5.  nbshell music login     und den Text einfuegen, dann Strg-D

Das Ergebnis landet in ~/.config/nbshell/ytmusic.json, Rechte 600. Die Datei
ist ein Passwort-Aequivalent: wer sie hat, ist in deinem Konto. Sie gehoert
NICHT ins Dotfiles-Repo (dort steht sie in .gitignore).

Cookies laufen ab -- nach Wochen bis Monaten. Dann meldet `status` "nicht
angemeldet", und der Weg oben wird einmal wiederholt. Das ist der wunde
Punkt der ganzen Sache; es gibt keinen besseren.
"""

import json
import os
import sys

KONFIG = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "nbshell"
)
ANMELDUNG = os.path.join(KONFIG, "ytmusic.json")


def raus(**werte):
    """Erfolg: JSON auf stdout, Schluss."""
    print(json.dumps({"ok": True, **werte}, ensure_ascii=False))
    sys.exit(0)


def fehler(grund, code=1):
    """Misserfolg mit lesbarem Grund -- den zeigt die Oberflaeche unveraendert an."""
    print(json.dumps({"ok": False, "grund": grund}, ensure_ascii=False))
    sys.exit(code)


def api(pflicht=True):
    """Die Verbindung. Fehlt etwas, ist der Grund die Anleitung."""
    try:
        from ytmusicapi import YTMusic
    except ImportError:
        fehler("ytmusicapi fehlt — sudo pacman -S python-ytmusicapi")

    if not pflicht:
        return YTMusic()

    if not os.path.exists(ANMELDUNG):
        fehler("nicht angemeldet — nbshell music login")
    try:
        return YTMusic(ANMELDUNG)
    except Exception as e:
        fehler(f"Anmeldung unbrauchbar ({e}) — nbshell music login")


# ── Umformen ─────────────────────────────────────────────────────────────
#
# ytmusicapi liefert je nach Aufruf unterschiedlich geformte Titel: mal steht
# der Interpret in `artists`, mal in `author`, mal gar nicht. Die Oberflaeche
# soll davon nichts wissen, also wird hier einmal geradegezogen.


def namen(eintrag, schluessel="artists"):
    liste = eintrag.get(schluessel) or []
    if isinstance(liste, dict):
        liste = [liste]
    return ", ".join(a.get("name", "") for a in liste if isinstance(a, dict) and a.get("name"))


def titel_von(t):
    album = t.get("album")
    return {
        "id": t.get("videoId") or "",
        # setVideoId ist die Nummer des Titels IN DIESER Playlist. Zum Entfernen
        # ist sie Pflicht -- dieselbe Aufnahme kann mehrfach drinstehen, und ohne
        # sie wuesste YouTube nicht, welche gemeint ist.
        "slot": t.get("setVideoId") or "",
        "titel": t.get("title") or "",
        "interpret": namen(t) or t.get("author") or "",
        "album": (album or {}).get("name", "") if isinstance(album, dict) else (album or ""),
        "dauer": t.get("duration") or "",
        "sekunden": t.get("duration_seconds") or 0,
    }


def liste_von(p):
    zahl = p.get("count")
    return {
        "id": p.get("playlistId") or "",
        "titel": p.get("title") or "",
        "anzahl": int(zahl) if str(zahl).isdigit() else 0,
        "beschreibung": p.get("description") or "",
    }


# ── Befehle ──────────────────────────────────────────────────────────────


def cmd_login(_):
    """Kopfzeilen von stdin lesen und daraus die Anmeldedatei bauen."""
    try:
        from ytmusicapi import setup
    except ImportError:
        fehler("ytmusicapi fehlt — sudo pacman -S python-ytmusicapi")

    roh = sys.stdin.read().strip()
    if not roh:
        fehler("nichts eingefuegt — die Kopfzeilen der Anfrage werden erwartet")
    if "ookie" not in roh:
        fehler("darin steht kein Cookie — es muessen die REQUEST-Kopfzeilen sein")

    os.makedirs(KONFIG, exist_ok=True)
    try:
        setup(filepath=ANMELDUNG, headers_raw=roh)
    except Exception as e:
        fehler(f"ging nicht: {e}")
    os.chmod(ANMELDUNG, 0o600)

    # Sofort ausprobieren: eine Datei, die erst beim naechsten Start auffaellt,
    # ist schlimmer als gar keine.
    try:
        from ytmusicapi import YTMusic

        YTMusic(ANMELDUNG).get_library_playlists(limit=1)
    except Exception as e:
        fehler(f"angelegt, aber unbrauchbar: {e}")
    raus(datei=ANMELDUNG)


def cmd_status(_):
    # api() prueft in der richtigen Reihenfolge: erst das Paket, dann die
    # Anmeldung. Andersherum schickte man jemanden zum Anmelden, das dann am
    # fehlenden Paket scheitert.
    y = api()
    try:
        n = len(y.get_library_playlists(limit=50))
    except Exception as e:
        fehler(f"Anmeldung abgelaufen ({e}) — nbshell music login")
    raus(angemeldet=True, playlists=n)


def cmd_playlists(_):
    y = api()
    # „Liked Music" (id LM) liefert die Schnittstelle selbst mit -- ein eigener
    # Eintrag dafuer stand einmal hier und war schlicht doppelt.
    raus(playlists=[liste_von(p) for p in y.get_library_playlists(limit=100)])


def cmd_playlist(args):
    if not args:
        fehler("welche Playlist?")
    y = api()
    if args[0] == "LM":
        titel = y.get_liked_songs(limit=500).get("tracks", [])
        raus(titel=[titel_von(t) for t in titel], name="Meine Titel")
    p = y.get_playlist(args[0], limit=500)
    raus(titel=[titel_von(t) for t in p.get("tracks", [])], name=p.get("title", ""))


def cmd_search(args):
    if not args:
        fehler("wonach?")
    art = "songs"
    if args[0].startswith("--"):
        art, args = args[0][2:], args[1:]
    # Ohne Anmeldung geht Suchen auch -- praktisch, solange die Cookies fehlen.
    y = api(pflicht=os.path.exists(ANMELDUNG))
    treffer = y.search(" ".join(args), filter=art, limit=25)
    raus(treffer=[titel_von(t) for t in treffer if t.get("videoId")], art=art)


def cmd_add(args):
    if len(args) < 2:
        fehler("nbshell music add <playlist> <titel-id> …")
    y = api()
    y.add_playlist_items(args[0], args[1:], duplicates=True)
    raus(hinzugefuegt=len(args) - 1)


def cmd_remove(args):
    if len(args) != 3:
        fehler("nbshell music remove <playlist> <titel-id> <slot>")
    y = api()
    y.remove_playlist_items(args[0], [{"videoId": args[1], "setVideoId": args[2]}])
    raus(entfernt=args[1])


def cmd_create(args):
    if not args:
        fehler("wie soll sie heissen?")
    y = api()
    neu = y.create_playlist(" ".join(args), "", privacy_status="PRIVATE")
    raus(id=neu if isinstance(neu, str) else str(neu))


def cmd_delete(args):
    if not args:
        fehler("welche Playlist?")
    api().delete_playlist(args[0])
    raus(geloescht=args[0])


def cmd_rename(args):
    if len(args) < 2:
        fehler("nbshell music rename <playlist> <neuer name>")
    api().edit_playlist(args[0], title=" ".join(args[1:]))
    raus(umbenannt=args[0])


def cmd_like(args):
    if not args:
        fehler("welcher Titel?")
    api().rate_song(args[0], "LIKE")
    raus(geliked=args[0])


def cmd_unlike(args):
    if not args:
        fehler("welcher Titel?")
    api().rate_song(args[0], "INDIFFERENT")
    raus(entliked=args[0])


def cmd_sync(_):
    """Cookies aus Brave lesen und die Anmeldung erneuern -- kein manuelles
    Kopieren noetig.

    Braucht browser_cookie3 (paru -S python-browser-cookie3) und dass Brave bei
    music.youtube.com angemeldet ist. ytmusicapi rechnet den Auth-Hash bei jeder
    Anfrage neu aus dem SAPISID-Cookie aus -- das Cookie genuegt also, ein
    frisch abgelaufener 'authorization'-Header ist egal.
    """
    try:
        import browser_cookie3
    except ImportError:
        fehler("browser_cookie3 fehlt -- paru -S python-browser-cookie3")

    try:
        jar = browser_cookie3.brave(domain_name=".youtube.com")
    except Exception as e:
        fehler(f"Brave-Cookies nicht lesbar ({e}) -- Keyring entsperrt? Brave-Profil vorhanden?")

    paare = [(c.name, c.value) for c in jar if c.value]
    if not any(n in ("SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID") for n, _ in paare):
        fehler("keine YouTube-Anmelde-Cookies in Brave -- dort bei music.youtube.com einloggen")

    cookies = dict(paare)
    cookie = "; ".join(f"{n}={v}" for n, v in paare)

    # ytmusicapi erkennt Browser-Auth nur, wenn BEIDE Keys da sind: authorization
    # UND cookie (sonst haelt es die Datei faelschlich fuer OAuth). Der
    # SAPISIDHASH wird bei jeder Anfrage ohnehin neu gerechnet -- wir brauchen den
    # Key nur praesent. Trotzdem gleich korrekt aus dem SAPISID-Cookie bilden.
    import hashlib
    import time

    origin = "https://music.youtube.com"
    sapisid = (cookies.get("SAPISID") or cookies.get("__Secure-3PAPISID")
               or cookies.get("__Secure-1PAPISID") or "")
    ts = int(time.time())
    sha = hashlib.sha1(f"{ts} {sapisid} {origin}".encode()).hexdigest()
    auth = f"SAPISIDHASH {ts}_{sha}"

    kopf = "\n".join([
        "accept: */*",
        "accept-language: en-US,en;q=0.9",
        "authorization: " + auth,
        "content-type: application/json",
        "cookie: " + cookie,
        "origin: " + origin,
        "user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "x-goog-authuser: 0",
    ])

    try:
        from ytmusicapi import setup
        os.makedirs(KONFIG, exist_ok=True)
        setup(filepath=ANMELDUNG, headers_raw=kopf)
        os.chmod(ANMELDUNG, 0o600)
    except Exception as e:
        fehler(f"Anmeldung schreiben ging nicht: {e}")

    # Sofort testen -- eine unbrauchbare Datei faellt sonst erst spaeter auf.
    try:
        from ytmusicapi import YTMusic
        n = len(YTMusic(ANMELDUNG).get_library_playlists(limit=5))
    except Exception as e:
        fehler(f"angelegt, aber unbrauchbar ({e}) -- in Brave neu einloggen?")

    raus(quelle="brave", playlists=n)


BEFEHLE = {
    "login": cmd_login,
    "sync": cmd_sync,
    "status": cmd_status,
    "playlists": cmd_playlists,
    "playlist": cmd_playlist,
    "search": cmd_search,
    "add": cmd_add,
    "remove": cmd_remove,
    "create": cmd_create,
    "delete": cmd_delete,
    "rename": cmd_rename,
    "like": cmd_like,
    "unlike": cmd_unlike,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in BEFEHLE:
        fehler("Befehl fehlt — " + " | ".join(BEFEHLE))
    try:
        BEFEHLE[sys.argv[1]](sys.argv[2:])
    except SystemExit:
        raise
    except Exception as e:
        # Alles, was von der fremden Schnittstelle hochkommt, wird hier zu einer
        # Zeile. Ein Stapelabzug auf stdout waere kein JSON und wuerde die
        # Oberflaeche mit „Antwort unlesbar" abspeisen.
        fehler(f"{type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
