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
}
