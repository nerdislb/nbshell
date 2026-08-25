import QtQuick
import QtTest

import "../Api.js" as Api

TestCase {
  name: "YtmusicApiLogic"

  function test_barTrackText_respectsIndependentTitleAndArtistSettings() {
    compare(Api.barTrackText("Blue in Green", "Miles Davis", true, false),
      "Blue in Green")
    compare(Api.barTrackText("Blue in Green", "Miles Davis", false, true),
      "Miles Davis")
    compare(Api.barTrackText("Blue in Green", "Miles Davis", true, true),
      "Miles Davis - Blue in Green")
    compare(Api.barTrackText("Blue in Green", "Miles Davis", false, false), "")
  }

  function test_scrollAvailability_requiresAtLeastOneBarLabel() {
    verify(Api.canScrollBarText(true, true))
    verify(Api.canScrollBarText(true, false))
    verify(Api.canScrollBarText(false, true))
    verify(!Api.canScrollBarText(false, false))
  }

  function test_normalizedScrollSpeed_defaultsClampsAndSnaps() {
    compare(Api.normalizedScrollSpeed(undefined), 1)
    compare(Api.normalizedScrollSpeed("not-a-speed"), 1)
    compare(Api.normalizedScrollSpeed(0), 0.25)
    compare(Api.normalizedScrollSpeed(4), 3)
    compare(Api.normalizedScrollSpeed(1.13), 1.25)
  }

  function test_eqPreset_and_bands_roundtrip() {
    compare(Api.eqPresetName("Rock"), "Rock")
    compare(Api.eqPresetName("nope"), "Flat")
    compare(Api.eqPresetName("Custom"), "Custom")
    compare(Api.eqBandsText([3, -1]),
      JSON.stringify([3, -1, 0, 0, 0, 0, 0, 0, 0, 0]))
    compare(Api.eqBandsList([-12, 99, "x"])[0], -12)
    compare(Api.eqBandsList([-12, 99, "x"])[1], 12)
  }

  function test_qualityKbps_mapsLabels() {
    compare(Api.qualityKbps("96 kbps"), 96)
    compare(Api.qualityKbps("160 kbps"), 160)
    compare(Api.qualityKbps("320 kbps"), 320)
    compare(Api.qualityLabel(96), "96 kbps")
  }

  function test_filteredSorted_reusesTheUnchangedDefaultList() {
    var rows = [{ name: "One" }, { name: "Two" }]
    verify(Api.filteredSorted(rows, "", "default") === rows)
    compare(Api.filteredSorted(rows, " two ", "default"), [rows[1]])
  }

  function test_millisecondsToClock() {
    compare(Api.millisecondsToClock(0), "0:00")
    compare(Api.millisecondsToClock(65000), "1:05")
    compare(Api.millisecondsToClock(3723000), "1:02:03")
  }

  function test_lyricsSong_requiresIdTitleArtist() {
    verify(Api.lyricsSong("", "Song", "Artist", "", 10, "", 0) === null)
    verify(Api.lyricsSong("abc", "Song", "Artist", "Album", 10, "", 3) !== null)
  }

  function test_redact_hidesCookies() {
    var text = Api.redact("cookie: SID=supersecret")
    verify(text.indexOf("supersecret") < 0)
  }

  function test_mergeHistory_and_shareUrl() {
    compare(Api.watchUrl("abc"), "https://music.youtube.com/watch?v=abc")
    compare(Api.trackShareUrl({ videoId: "xyz" }),
      "https://music.youtube.com/watch?v=xyz")
    var merged = Api.mergeHistory(
      [{ videoId: "aaa", name: "Local" }],
      [{ videoId: "bbb" }, { videoId: "aaa" }])
    compare(merged.length, 2)
    compare(merged[0].videoId, "aaa")
    compare(merged[1].videoId, "bbb")
  }

  function test_splitSocketBuffer_caps_missing_newlines() {
    var ok = Api.splitSocketBuffer("", '{"ok":true}\n{"id":1}', 64)
    verify(!ok.overflow)
    compare(ok.lines.length, 1)
    compare(ok.lines[0], '{"ok":true}')
    compare(ok.buffer, '{"id":1}')
    var pad = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    var overflow = Api.splitSocketBuffer("abc", pad + pad, 32)
    verify(overflow.overflow)
    compare(overflow.buffer, "")
    compare(overflow.lines.length, 0)
  }

  function test_requestPayload_protectsProtocolMetadata() {
    var payload = Api.requestPayload("get_album", {
      id: "media-id",
      v: 99,
      command: "wrong",
      item_id: "album-id"
    }, 7)
    compare(payload.v, 1)
    compare(payload.id, 7)
    compare(payload.command, "get_album")
    compare(payload.item_id, "album-id")
  }

  function test_isPlaybackState_ignoresCatalogPayloads() {
    verify(!Api.isPlaybackState(null))
    verify(!Api.isPlaybackState({ home: [], signed_in: true }))
    verify(!Api.isPlaybackState({ items: [], signed_in: true }))
    verify(Api.isPlaybackState({ lifecycle: "ready", signed_in: true }))
    verify(Api.isPlaybackState({ position_ms: 0, playing: false }))
  }

  function test_signInError_rewrites401() {
    verify(Api.isSignInError("Server returned HTTP 401: Unauthorized. You must be signed in to perform this operation."))
    compare(Api.signInErrorMessage("Server returned HTTP 401: Unauthorized."),
      "Sign in to like songs")
    verify(!Api.isSignInError("Preparing playback…"))
  }

  function test_unitVolume_acceptsPercentAndUnitScales() {
    compare(Api.unitVolume(80), 0.8)
    compare(Api.unitVolume(0), 0)
    compare(Api.unitVolume(100), 1)
    compare(Api.unitVolume(0.8), 0.8)
    compare(Api.unitVolume(undefined), 0.8)
  }

  function test_volumeCaption_showsPercentOrMuted() {
    compare(Api.volumePercent(0.8), 80)
    compare(Api.volumePercent(80), 80)
    compare(Api.volumeCaption(0), "Muted")
    compare(Api.volumeCaption(0.8), "80%")
  }

  function test_controlTooltip_joinsLabelAndShortcut() {
    compare(Api.controlTooltip("Play", "Space"), "Play · Space")
    compare(Api.controlTooltip("Volume 80%", ""), "Volume 80%")
  }

  function test_playerHintRows_coverPlaybackLikeAndQueue() {
    var keys = Api.playerHintRows().map(function(row) { return row.keys })
    var actions = Api.playerHintRows().map(function(row) { return row.action })
    verify(keys.indexOf("Space") >= 0)
    verify(keys.indexOf("L") >= 0)
    verify(keys.indexOf("Q") >= 0)
    verify(actions.join(" ").indexOf("pause") >= 0
      || actions.join(" ").indexOf("Pause") >= 0)
    verify(actions.join(" ").indexOf("Like") >= 0)
    verify(actions.join(" ").indexOf("queue") >= 0
      || actions.join(" ").indexOf("Queue") >= 0)
  }

  function test_artworkAltText_namesTheCover() {
    compare(Api.artworkAltText("Lazy Mary", "Lou Monte"),
      "Album artwork for Lazy Mary by Lou Monte")
    compare(Api.artworkAltText("", ""), "Album artwork")
  }
}
