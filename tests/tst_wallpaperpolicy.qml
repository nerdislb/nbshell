import QtQuick
import QtTest
import "../shell/Wallpaper/WallpaperPolicy.js" as Policy

TestCase {
    name: "WallpaperPolicy"
    function test_time_boundaries() {
        var settings = Policy.defaults();
        compare(Policy.phaseAt(settings.phases, 0).name, "Night");
        compare(Policy.phaseAt(settings.phases, 359).name, "Night");
        compare(Policy.phaseAt(settings.phases, 360).name, "Morning");
        compare(Policy.phaseAt(settings.phases, 600).name, "Day");
        compare(Policy.phaseAt(settings.phases, 1080).name, "Evening");
        compare(Policy.phaseAt(settings.phases, 1320).name, "Night");
        settings.phases[0].time = "23:30";
        compare(Policy.phaseAt(settings.phases, 0).name, "Morning");
    }
    function test_invalid_config() {
        compare(Policy.minutes("24:00"), -1);
        compare(Policy.minutes("6:00"), -1);
        compare(Policy.minutes("12:60"), -1);
        compare(Policy.normalize(null).videoEnabled, false);
        var s = Policy.defaults();
        s.phases[0].time = s.phases[1].time;
        compare(Policy.normalize(s).phases[0].time, "06:00");
    }
    function test_independent_modes_and_fallback() {
        var s = Policy.defaults();
        s.video = "/all.mp4";
        s.phases[0].image = "/morning.png";
        s.phases[0].video = "/morning.mp4";
        compare(Policy.sources(s, 400, "/theme.png").image, "/theme.png");
        compare(Policy.sources(s, 400, "/theme.png").video, "/all.mp4");
        s.daytimeEnabled = true;
        compare(Policy.sources(s, 400, "/theme.png").image, "/morning.png");
        compare(Policy.sources(s, 400, "/theme.png").video, "/morning.mp4");
        compare(Policy.sources(s, 700, "/theme.png").image, "/theme.png");
        compare(Policy.sources(s, 700, "/theme.png").video, "");
    }
    function test_workspace_visibility() {
        var ws = [{id: 1, output: "eDP-1", is_active: true}, {id: 2, output: "eDP-1", is_active: false},
            {id: 3, output: "DP-1", is_active: true}];
        verify(Policy.desktopClear("eDP-1", ws, [{workspace: 2}, {workspace: 3}]));
        verify(!Policy.desktopClear("DP-1", ws, [{workspace: 3}]));
        verify(!Policy.desktopClear("eDP-1", ws, [{workspace: "1"}]));
        verify(!Policy.desktopClear("eDP-1", [], []));
        verify(!Policy.desktopClear("eDP-1", ws, [{}]));
    }
    function test_playback_gates() {
        verify(Policy.playbackReason(true, "/v.mp4", false, false, false, true, true).startsWith("Video ready"));
        verify(Policy.playbackReason(true, "/v.mp4", true, false, false, true, true).includes("battery"));
        verify(Policy.playbackReason(true, "/v.mp4", false, true, false, true, true).includes("Reduced Motion"));
        verify(Policy.playbackReason(true, "/v.mp4", false, false, true, true, true).includes("resting"));
        verify(Policy.playbackReason(true, "/v.mp4", false, false, false, false, true).includes("compositor"));
        verify(Policy.playbackReason(true, "/v.mp4", false, false, false, true, false).includes("window"));
        compare(Policy.playbackReason(false, "/v.mp4", false, false, false, true, true), "Video disabled");
    }
    function test_local_paths() {
        compare(Policy.localUrl("/home/a #b?.png"), "file:///home/a%20%23b%3F.png");
        compare(Policy.localUrl("https://example.org/a.mp4"), "");
        compare(Policy.localUrl(""), "");
    }
}
