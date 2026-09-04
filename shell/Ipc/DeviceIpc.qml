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
                "lock": Idle.lockAfter
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
            return Idle.caffeine ? "bleibt wach" : "automation active";
        }

        function on(): string {
            Config.set("idle", true);
            return "automation on";
        }

        function off(): string {
            Config.set("idle", false);
            return "automation off";
        }

        // Start manually for preview or from an Umbriel key binding.
        function saver(): string {
            Idle.startSaver();
            return "screen saver running";
        }
    }

    IpcHandler {
        target: "battery"

        function status(): string {
            if (!PowerService.available)
                return "no battery";
            return JSON.stringify({
                "prozent": PowerService.percent,
                "zustand": PowerService.stateText,
                "restzeit": PowerService.timeText,
                "leistung_watt": Number(PowerService.rate.toFixed(1)),
                "leistung_typ": PowerService.powerLabel,
                "gesundheit": PowerService.health,
                "profil": PowerService.activeProfile,
                "modus": PowerService.activeProfileLabel
            });
        }

        function profile(name: string): string {
            if (!name)
                return PowerService.activeProfileLabel;
            if (!PowerService.setProfile(name))
                return "unknown mode; use powersaver, balanced, or performance";
            return PowerService.profileLabel(name);
        }
    }

    IpcHandler {
        target: "power"

        function menu(): string {
            Runtime.powerOpen = !Runtime.powerOpen;
            return Runtime.powerOpen ? "open" : "closed";
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
            return "suspend";
        }
    }

    IpcHandler {
        target: "media"

        function playpause(): string {
            MediaService.playPause();
            return MediaService.playing ? "playing" : "paused";
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
            MediaService.refreshPositions();
            return JSON.stringify({
                "spielt": MediaService.playing,
                "position": MediaService.zeit(MediaService.position),
                "laenge": MediaService.zeit(MediaService.length),
                "volume": Math.round(MediaService.volume * 100),
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

        // Ton zurueck auf die Bluetooth-Hoerer, nachdem das Telefon sie
        // uebernommen hatte.
        function zurueck(): string {
            Audio.tonZurueck();
            return "hole …";
        }

        function tonstatus(): string {
            return Audio.tonStatus === "" ? "nothing to report" : Audio.tonStatus;
        }

        // Welcher Bluetooth-Codec laeuft -- und umschalten. Ohne Argument nur
        // die Auskunft; `beste` nimmt den, den PipeWire selbst vorn einsortiert.
        function codec(wunsch: string): string {
            Audio.codecsLesen();
            if (!Audio.btGelesen)
                return "checking — run the command again";
            if (wunsch === "")
                return Audio.btDa ? (Audio.btCodec + (Audio.btSchlechter ? "  (es ginge " + (Audio.btCodecs.length > 0 ? Audio.btCodecs[0].codec : "?") + ")" : "")) : "no Bluetooth audio device";
            if (!Audio.btDa)
                return "no Bluetooth audio device";

            if (wunsch === "beste" || wunsch === "best") {
                Audio.setzeCodec(Audio.btBeste);
                return "schalte auf " + (Audio.btCodecs.length > 0 ? Audio.btCodecs[0].codec : Audio.btBeste);
            }
            const treffer = Audio.btCodecs.find(c => c.codec.toLowerCase() === wunsch.toLowerCase() || c.profil === wunsch);
            if (!treffer)
                return "kenne ich nicht: " + wunsch + " — da waeren: " + Audio.btCodecs.map(c => c.codec).join(", ");
            Audio.setzeCodec(treffer.profil);
            return "schalte auf " + treffer.codec;
        }

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
            if (Runtime.audioPanelOpen) {
                Runtime.closeAll();
                return "closed";
            }
            Runtime.revealIslandTemporarily();
            Runtime.requestPopout("volume", Compositor.focusedOutput);
            return "open";
        }

        function tools(): string {
            Runtime.audioToolsOpen = !Runtime.audioToolsOpen;
            return Runtime.audioToolsOpen ? "open" : "closed";
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
