import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Common
import qs.Services

// Steuerung von aussen: Geraet.
//
// Leerlauf, Akku, Sitzung, Wiedergabe, Helligkeit, Ton.
//
// Aufrufbar als `nbshell <ziel> <befehl>`, siehe bin/nbshell. Diese Handler
// standen frueher alle in shell.qml -- 945 von 1088 Zeilen, sodass die
// eigentliche Frage "woraus besteht diese Shell?" unter der Fernsteuerung
// begraben lag. Sie sprechen ausschliesslich mit Singletons, also war der
// Schnitt schmerzlos.
Scope {
    // Leerlauf und Wachhalten.
    IpcHandler {
        target: "idle"

        function status(): string {
            return JSON.stringify({
                "automatik": Idle.enabled,
                "wach": Idle.caffeine,
                "zustand": Idle.state,
                "dimmen": Idle.dimAfter,
                "bildschirmAus": Idle.offAfter,
                "sperren": Idle.lockAfter
            });
        }

        // `caffeine` ohne Argument schaltet um -- das ist die Geste, die man
        // auf eine Taste legt.
        function caffeine(value: string): string {
            if (value === "on" || value === "an")
                Idle.setCaffeine(true);
            else if (value === "off" || value === "aus")
                Idle.setCaffeine(false);
            else
                Idle.toggleCaffeine();
            return Idle.caffeine ? "bleibt wach" : "Automatik laeuft";
        }

        function on(): string {
            Config.set("idle", true);
            return "Automatik an";
        }

        function off(): string {
            Config.set("idle", false);
            return "Automatik aus";
        }

        // Von Hand starten -- zum Ansehen, und fuer eine Taste in niri.
        function saver(): string {
            Idle.startSaver();
            return "Bildschirmschoner laeuft";
        }
    }

    IpcHandler {
        target: "battery"

        function status(): string {
            if (!PowerService.available)
                return "kein Akku";
            return JSON.stringify({
                "prozent": PowerService.percent,
                "zustand": PowerService.stateText,
                "restzeit": PowerService.timeText,
                "gesundheit": PowerService.health,
                "profil": PowerService.activeProfile
            });
        }

        function profile(name: string): string {
            if (!name)
                return PowerService.activeProfile;
            PowerService.setProfile(name);
            return name;
        }
    }

    IpcHandler {
        target: "power"

        function menu(): string {
            Runtime.powerOpen = !Runtime.powerOpen;
            return Runtime.powerOpen ? "offen" : "zu";
        }

        // Einzeln aufrufbar, damit ein Tastenkuerzel direkt sperren kann.
        function lock(): string {
            Session.run("lock");
            return "gesperrt";
        }

        function logout(): string {
            Session.run("logout");
            return "abgemeldet";
        }

        function suspend(): string {
            Session.run("suspend");
            return "Bereitschaft";
        }
    }

    IpcHandler {
        target: "media"

        function playpause(): string {
            MediaService.playPause();
            return MediaService.playing ? "spielt" : "pausiert";
        }

        function next(): string {
            MediaService.next();
            return MediaService.label;
        }

        function previous(): string {
            MediaService.previous();
            return MediaService.label;
        }

        function status(): string {
            return JSON.stringify({
                "spielt": MediaService.playing,
                "position": MediaService.zeit(MediaService.position),
                "laenge": MediaService.zeit(MediaService.length),
                "lautstaerke": Math.round(MediaService.volume * 100),
                "titel": MediaService.title,
                "interpret": MediaService.artist,
                "player": MediaService.players.map(p => p.identity)
            });
        }
    }

    IpcHandler {
        target: "brightness"

        function up(): string {
            return String(Brightness.step(5));
        }

        function down(): string {
            return String(Brightness.step(-5));
        }

        function set(percent: string): string {
            return String(Brightness.set(parseInt(percent, 10)));
        }
    }

    IpcHandler {
        target: "audio"

        // Fuer die Multimediatasten: XF86AudioRaiseVolume -> `nbshell audio up`
        function up(): string {
            return String(Audio.step(5));
        }

        function down(): string {
            return String(Audio.step(-5));
        }

        function set(percent: string): string {
            return String(Audio.setVolume(parseInt(percent, 10)));
        }

        function mute(): string {
            Audio.toggleMute();
            return Audio.muted ? "stumm" : String(Audio.volume);
        }

        function micmute(): string {
            Audio.setMicMuted(!Audio.micMuted);
            return Audio.micMuted ? "stumm" : String(Audio.micVolume);
        }

        function panel(): string {
            Runtime.islandOpen = true;
            Runtime.audioPanelOpen = !Runtime.audioPanelOpen;
            return Runtime.audioPanelOpen ? "offen" : "zu";
        }

        function status(): string {
            return JSON.stringify({
                "volume": Audio.volume,
                "muted": Audio.muted,
                "sink": Audio.label(Audio.sink),
                "mic": Audio.micVolume,
                "micMuted": Audio.micMuted,
                "sinks": Audio.sinks.map(n => Audio.label(n))
            });
        }
    }
}
