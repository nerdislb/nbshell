import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false
  property bool escapeCloseArmed: false
  property real volumeBeforeMute: 0.5
  property string currentTab: "home"
  property bool openedForLogin: false

  property string searchText: ""
  property string libraryType: "tracks"
  property string libraryFilter: ""
  property string librarySort: "default"
  property string playlistFilter: ""
  property string playlistSort: "default"
  property string detailFilter: ""
  property string detailSort: "default"
  property string homeFilter: ""
  property string queueFilter: ""
  property bool searchInContext: true
  property bool universalSearchActive: false
  property var scrollPositions: ({})
  property var navigationStack: []
  property string lastContentTab: "home"
  property string headerDraft: ""
  property bool showHeaderPaste: false

  property string draftIdleMinutes: "15"
  property bool draftShowMiniPlayer: true
  property string draftShortcutPlayer: "Full player"
  property string draftAudioQuality: "320 kbps"
  property var contextItem: null
  property var contextSourceItems: []
  property string newPlaylistName: ""

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "ytmusic"
  readonly property string lyricsRequestKey: "ytmusic-panel-lyrics"
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family
  readonly property bool accountConnected: service && service.accountConnected
  readonly property bool sessionPending: service && service.sessionPending
  readonly property bool compactHeight: window.height < Style.space(620)
  readonly property bool compactWidth: window.width < Style.space(760)
  readonly property var activeSearchScope: Api.searchScope(currentTab,
    service ? service.detailItem : null,
    service ? service.selectedPlaylist : null, "recent", libraryType)
  readonly property bool showingUniversalSearch: Api.universalSearchVisible(
    currentTab, universalSearchActive)
  readonly property bool shortcutsBlocked: mediaContextMenu.opened
    || playlistPicker.opened || createPlaylistPopup.opened || sleepPopup.opened
    || shortcutHelpPopup.opened || lyricsInstallPopup.opened
  readonly property var panelBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 28
  }

  function syncDraftSettings() {
    if (!service) return
    draftIdleMinutes = String(service.idleShutdownMinutes)
    draftShowMiniPlayer = service.showMiniPlayer
    draftShortcutPlayer = service.shortcutPlayer
    draftAudioQuality = service.audioQuality
    libraryType = service.libraryType || "tracks"
  }

  function saveSettings(showStatus) {
    if (!service) return
    service.persistSettings({
      idleShutdownMinutes: Math.max(0, Math.min(1440,
        Math.floor(Number(draftIdleMinutes) || 0))),
      showMiniPlayer: draftShowMiniPlayer ? "On" : "Off",
      shortcutPlayer: draftShortcutPlayer,
      audioQuality: draftAudioQuality
    })
    syncDraftSettings()
    if (showStatus !== false) service.succeed("Settings saved")
  }

  function persistDraftSettings() { saveSettings(false) }

  function open(payloadJson) {
    var payload = Api.parseJson(payloadJson, ({})) || ({})
    var requestedTab = String(payload.tab || "")
    var requestedDetail = payload.detailItem || null
    if (requestedDetail) {
      currentTab = "detail"
      navigationStack = []
    } else if (["home", "search", "library", "playlists", "queue", "setup", "login"].indexOf(requestedTab) >= 0)
      currentTab = requestedTab
    if (accountConnected) openedForLogin = false
    else if (!sessionPending) {
      currentTab = "login"
      openedForLogin = true
    }
    closingFromHost = false
    opened = true
    syncDraftSettings()
    if (service) {
      service.setUiVisible("full-panel", true)
      service.openView(currentTab === "login" ? "home" : currentTab, false)
      if (currentTab === "detail" && requestedDetail)
        service.openDetail(requestedDetail)
    }
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  function close() {
    persistUiState()
    closingFromHost = true
    opened = false
    if (service) service.setUiVisible("full-panel", false)
    closingFromHost = false
  }

  function requestClose() {
    escapeCloseArmed = false
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function persistUiState() {
    if (!service) return
    service.persistSession({
      tab: currentTab === "login" ? "home" : currentTab,
      searchText: searchText,
      libraryType: libraryType,
      libraryFilter: libraryFilter,
      detailFilter: detailFilter,
      detailItem: currentTab === "detail" && service.detailItem ? service.detailItem : null
    })
  }

  function chooseTab(tab) {
    if (!accountConnected && tab !== "home" && tab !== "search" && tab !== "login" && tab !== "setup") {
      currentTab = "login"
      openedForLogin = true
      return
    }
    escapeCloseArmed = false
    if (tab !== "search") universalSearchActive = false
    if (tab !== "detail") navigationStack = []
    lastContentTab = Api.rememberContentTab(currentTab) || lastContentTab
    currentTab = tab
    openedForLogin = false
    if (service) service.openView(tab, false)
  }

  function openItem(item) {
    if (!item) return
    if (item.kind !== "context" && item.type === "track") {
      activateMedia(item, [item], "")
      return
    }
    var stack = navigationStack.slice()
    stack.push({ tab: currentTab, item: currentTab === "detail" && service ? service.detailItem : null })
    navigationStack = stack
    currentTab = "detail"
    if (service) service.openDetail(item)
  }

  function goBack() {
    if (!navigationStack.length) {
      chooseTab("home")
      return
    }
    var stack = navigationStack.slice()
    var destination = stack.pop()
    navigationStack = stack
    currentTab = destination.tab || "home"
    if (currentTab === "detail" && destination.item && service)
      service.openDetail(destination.item)
    else if (service) service.openView(currentTab, false)
  }

  function activateMedia(item, sourceItems, contextUri) {
    if (!item || !service) return
    service.playItem(item, sourceItems, contextUri)
  }

  function textInputFocused() {
    var item = window.activeFocusItem
    return !!item && ("acceptableInput" in item || "echoMode" in item)
  }

  function shortcutHint(label, keys) {
    return String(label || "") + (keys ? " · " + keys : "")
  }

  function seekBy(seconds) {
    if (!service || !service.playbackControllable) return
    service.seekSeconds(Api.seekPosition(service.positionSeconds, seconds,
      service.lengthSeconds))
  }

  function adjustVolume(delta) {
    if (!service || !service.volumeSupported) return
    var next = Api.nextVolume(service.volume, delta)
    if (Api.shouldRememberVolume(next)) volumeBeforeMute = next
    service.setVolume(next)
  }

  function toggleMute() {
    if (!service || !service.volumeSupported) return
    var current = Api.nextVolume(service.volume, 0)
    if (Api.shouldRememberVolume(current)) {
      volumeBeforeMute = current
      service.setVolume(0)
    } else service.setVolume(Api.unmuteVolume(volumeBeforeMute))
  }

  function openLyrics() {
    if (!service || !service.currentLyricsSong) return
    var result = service.requestLyrics(lyricsRequestKey)
    if (result !== "opening") lyricsInstallPopup.open()
  }

  function toggleShortcutHelp() {
    if (shortcutHelpPopup.opened) shortcutHelpPopup.close()
    else shortcutHelpPopup.open()
  }

  function dismissTransientPopup() {
    if (lyricsInstallPopup.opened && (!service || !service.lyricsPluginBusy)) {
      lyricsInstallPopup.close(); return true
    }
    if (shortcutHelpPopup.opened) { shortcutHelpPopup.close(); return true }
    if (mediaContextMenu.opened) { mediaContextMenu.close(); return true }
    if (playlistPicker.opened) { playlistPicker.close(); return true }
    if (createPlaylistPopup.opened) { createPlaylistPopup.close(); return true }
    if (sleepPopup.opened) { sleepPopup.close(); return true }
    return false
  }

  function openMediaContext(item, sceneX, sceneY, sourceItems) {
    if (!item) return
    contextItem = item
    contextSourceItems = Array.isArray(sourceItems) ? sourceItems : []
    mediaContextMenu.x = Math.max(Style.space(6), Math.min(
      window.width - mediaContextMenu.width - Style.space(6), Number(sceneX) || 0))
    mediaContextMenu.y = Math.max(Style.space(6), Math.min(
      window.height - mediaContextMenu.height - Style.space(6), Number(sceneY) || 0))
    mediaContextMenu.open()
  }

  function pageTitle() {
    if (currentTab === "login") return "Connect YouTube Music"
    if (currentTab === "home") return "Home"
    if (currentTab === "search") return "Search"
    if (currentTab === "library") return "Library"
    if (currentTab === "playlists") return "Playlists"
    if (currentTab === "queue") return "Queue"
    if (currentTab === "setup") return "Settings"
    if (currentTab === "detail" && service && service.detailItem)
      return service.detailItem.name || "Details"
    return "YouTube Music"
  }

  function pageSubtitle() {
    if (currentTab === "login") return "Use the YouTube Music session already in Chromium"
    if (currentTab === "home") return accountConnected ? "Your mix" : "Public shelves"
    if (currentTab === "library") return Api.typeLabel(libraryType === "tracks" ? "track" : libraryType, true)
    if (currentTab === "detail" && service && service.detailItem)
      return service.detailItem.subtitle || ""
    if (currentTab === "queue") return service && service.backendState
      ? ((service.backendState.queue || []).length + " songs") : ""
    if (currentTab === "setup") return service && service.accountName
      ? service.accountName : (accountConnected ? "Signed in" : "Guest")
    return ""
  }

  function pageComponent() {
    if (currentTab === "login") return loginPage
    if (currentTab === "setup") return setupPage
    if (currentTab === "search" || showingUniversalSearch) return searchPage
    if (currentTab === "library") return libraryPage
    if (currentTab === "playlists") return playlistsPage
    if (currentTab === "detail") return detailPage
    if (currentTab === "queue") return queuePage
    return homePage
  }

  function runSearch() {
    if (!service) return
    service.search(searchText)
    if (currentTab !== "search") {
      universalSearchActive = true
    }
  }

  function focusSearch() {
    unifiedSearchField.forceActiveFocus()
    unifiedSearchField.selectAll()
  }

  function primaryNavigationItems() {
    return [
      { id: "home", label: "Home", icon: "󰎆" },
      { id: "search", label: "Search", icon: "󰍉" },
      { id: "queue", label: "Queue", icon: "󰐕" }
    ]
  }

  function updateLoginGate() {
    if (!opened || sessionPending) return
    if (!accountConnected && currentTab !== "home" && currentTab !== "search"
        && currentTab !== "setup") {
      currentTab = "login"
      openedForLogin = true
      return
    }
    if ((openedForLogin || currentTab === "login") && accountConnected) {
      openedForLogin = false
      currentTab = "home"
      if (service) service.openView("home", false)
    }
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onAccountConnectedChanged() { root.updateLoginGate() }
    function onLyricsPluginPromptRequested(surface) {
      if (String(surface) === root.lyricsRequestKey) lyricsInstallPopup.open()
    }
    function onLyricsPluginOpened(surface) {
      if (String(surface) === root.lyricsRequestKey) lyricsInstallPopup.close()
    }
  }

  Popup {
    id: mediaContextMenu
    modal: false
    width: Style.space(220)
    padding: Style.space(8)
    background: BorderSurface {
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.flat(Color.popups.border, 1)
    }
    Column {
      width: parent.width
      spacing: Style.space(2)
      Button {
        width: parent.width
        text: "Play"
        iconText: "󰐊"
        leftAlign: true
        foreground: root.foreground
        onClicked: {
          root.activateMedia(root.contextItem, root.contextSourceItems, "")
          mediaContextMenu.close()
        }
      }
      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.type === "track"
        text: "Add to queue"
        iconText: "󰐕"
        leftAlign: true
        foreground: root.foreground
        onClicked: {
          if (root.service) root.service.queueItem(root.contextItem)
          mediaContextMenu.close()
        }
      }
      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.type === "track"
        text: "Start radio"
        iconText: "󰐹"
        leftAlign: true
        foreground: root.foreground
        onClicked: {
          if (root.service) root.service.startRadio(root.contextItem)
          mediaContextMenu.close()
        }
      }
      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.type === "track"
        text: "Add to playlist"
        iconText: "󱁐"
        leftAlign: true
        foreground: root.foreground
        onClicked: {
          mediaContextMenu.close()
          playlistPicker.open()
        }
      }
      Button {
        width: parent.width
        visible: root.contextItem && root.contextItem.externalUrl
        text: "Open in browser"
        iconText: "󰖟"
        leftAlign: true
        foreground: root.foreground
        onClicked: {
          if (root.contextItem && root.contextItem.externalUrl)
            Quickshell.execDetached(["xdg-open", root.contextItem.externalUrl])
          mediaContextMenu.close()
        }
      }
    }
  }

  Popup {
    id: playlistPicker
    modal: true
    anchors.centerIn: parent
    width: Style.space(320)
    padding: Style.space(12)
    background: BorderSurface {
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.flat(Color.popups.border, 1)
    }
    Column {
      width: parent.width
      spacing: Style.space(8)
      Text {
        text: "Add to playlist"
        color: root.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Repeater {
        model: root.service ? root.service.playlists : []
        Button {
          required property var modelData
          width: playlistPicker.width - Style.space(24)
          text: modelData.name || "Playlist"
          iconText: "󰲸"
          leftAlign: true
          foreground: root.foreground
          onClicked: {
            if (root.service) root.service.addToPlaylist(modelData, root.contextItem)
            playlistPicker.close()
          }
        }
      }
      Button {
        width: parent.width
        text: "New playlist"
        iconText: "󰐕"
        foreground: root.foreground
        onClicked: {
          playlistPicker.close()
          createPlaylistPopup.open()
        }
      }
    }
  }

  Popup {
    id: createPlaylistPopup
    modal: true
    anchors.centerIn: parent
    width: Style.space(320)
    padding: Style.space(12)
    background: BorderSurface {
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.flat(Color.popups.border, 1)
    }
    Column {
      width: parent.width
      spacing: Style.space(8)
      Text {
        text: "Create playlist"
        color: root.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      TextField {
        id: newPlaylistField
        width: parent.width
        foreground: root.foreground
        placeholderText: "Playlist name"
        text: root.newPlaylistName
        onTextEdited: root.newPlaylistName = text
        onAccepted: createButton.clicked()
      }
      Row {
        spacing: Style.space(6)
        Button {
          text: "Cancel"
          foreground: root.foreground
          onClicked: createPlaylistPopup.close()
        }
        Button {
          id: createButton
          text: "Create"
          foreground: root.foreground
          selected: true
          onClicked: {
            if (!root.service) return
            root.service.createPlaylist(root.newPlaylistName, function(created) {
              if (created && root.contextItem)
                root.service.addToPlaylist(created, root.contextItem)
            })
            root.newPlaylistName = ""
            createPlaylistPopup.close()
          }
        }
      }
    }
  }

  Popup {
    id: sleepPopup
    modal: true
    anchors.centerIn: parent
    width: Style.space(280)
    padding: Style.space(12)
    background: BorderSurface {
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.flat(Color.popups.border, 1)
    }
    Column {
      width: parent.width
      spacing: Style.space(6)
      Text {
        text: "Sleep timer"
        color: root.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Repeater {
        model: [15, 30, 45, 60]
        Button {
          required property int modelData
          width: parent.width
          text: modelData + " minutes"
          leftAlign: true
          foreground: root.foreground
          onClicked: {
            if (root.service) root.service.sleepIn(modelData)
            sleepPopup.close()
          }
        }
      }
      Button {
        width: parent.width
        text: "After this song"
        leftAlign: true
        foreground: root.foreground
        onClicked: { if (root.service) root.service.sleepAfterTrack(); sleepPopup.close() }
      }
      Button {
        width: parent.width
        text: "After this album or playlist"
        leftAlign: true
        foreground: root.foreground
        onClicked: { if (root.service) root.service.sleepAfterContext(); sleepPopup.close() }
      }
      Button {
        width: parent.width
        visible: root.service && root.service.sleepActive
        text: "Cancel timer"
        leftAlign: true
        foreground: root.foreground
        onClicked: { if (root.service) root.service.cancelSleepTimer(); sleepPopup.close() }
      }
    }
  }

  Popup {
    id: shortcutHelpPopup
    modal: true
    anchors.centerIn: parent
    width: Style.space(420)
    padding: Style.space(16)
    background: BorderSurface {
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.flat(Color.popups.border, 1)
    }
    Column {
      width: parent.width
      spacing: Style.space(6)
      Text {
        text: "Keyboard shortcuts"
        color: root.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Repeater {
        model: [
          { keys: "Ctrl+K / /", action: "Jump to search" },
          { keys: "Space", action: "Play or pause" },
          { keys: "Ctrl+Left / Right", action: "Previous or next" },
          { keys: "Shift+Left / Right", action: "Seek 10 seconds" },
          { keys: "Ctrl+Up / Down", action: "Volume" },
          { keys: "M", action: "Mute" },
          { keys: "Ctrl+S / Ctrl+R", action: "Shuffle / repeat" },
          { keys: "Ctrl+Shift+L", action: "Lyrics" },
          { keys: "Alt+Left", action: "Back" },
          { keys: "Ctrl+,", action: "Settings" },
          { keys: "Esc", action: "Close popups, then the player" }
        ]
        Row {
          required property var modelData
          width: shortcutHelpPopup.width - Style.space(32)
          spacing: Style.space(10)
          Text {
            width: Style.space(160)
            text: modelData.keys
            color: root.foreground
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Text {
            text: modelData.action
            color: Qt.darker(root.foreground, 1.35)
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  Popup {
    id: lyricsInstallPopup
    modal: true
    anchors.centerIn: parent
    width: Style.space(360)
    padding: Style.space(12)
    background: BorderSurface {
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.flat(Color.popups.border, 1)
    }
    LyricsInstallPrompt {
      width: parent.width
      service: root.service
      foreground: root.foreground
      surfaceKey: root.lyricsRequestKey
      onCanceled: lyricsInstallPopup.close()
    }
  }

  Component {
    id: loginPage
    Flickable {
      clip: true
      contentHeight: loginColumn.implicitHeight
      Column {
        id: loginColumn
        width: parent.width
        spacing: Style.space(12)

        Text {
          width: parent.width
          text: "YouTube Music has no official desktop API. If Chromium on this computer is already signed in at music.youtube.com, copy that session. No DevTools paste."
          color: Qt.darker(root.foreground, 1.3)
          wrapMode: Text.WordWrap
          font.pixelSize: Style.font.body
        }
        Row {
          spacing: Style.space(8)
          Button {
            text: root.service && root.service.loginBusy ? "Working…" : "Use Chromium session"
            iconText: "󰍂"
            selected: true
            foreground: root.foreground
            enabled: !!root.service && !(root.service && root.service.loginBusy)
            onClicked: root.service.importBrowserAuth()
          }
          Button {
            text: "Open YouTube Music"
            iconText: "󰖟"
            foreground: root.foreground
            onClicked: Quickshell.execDetached(["xdg-open", "https://music.youtube.com"])
          }
        }
        Button {
          text: root.showHeaderPaste ? "Hide header paste" : "Paste headers instead"
          foreground: root.foreground
          onClicked: root.showHeaderPaste = !root.showHeaderPaste
        }
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.showHeaderPaste
          Text {
            width: parent.width
            text: "1. Open music.youtube.com and sign in.\n2. DevTools → Network → click Library.\n3. Copy the request headers of a browse call (must include Cookie).\n4. Paste them below."
            color: Qt.darker(root.foreground, 1.4)
            wrapMode: Text.WordWrap
            font.pixelSize: Style.font.bodySmall
          }
          ScrollView {
            width: parent.width
            height: Style.space(180)
            TextArea {
              id: headersField
              wrapMode: TextEdit.Wrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              placeholderText: "cookie: …\nx-goog-authuser: 0\n…"
              onTextChanged: root.headerDraft = text
            }
          }
          Button {
            text: root.service && root.service.loginBusy ? "Working…" : "Save headers and continue"
            iconText: "󰍂"
            foreground: root.foreground
            enabled: root.headerDraft.trim() !== "" && root.service
            onClicked: root.service.setupAuth(root.headerDraft)
          }
        }
        Text {
          width: parent.width
          visible: root.service && root.service.statusMessage !== ""
          text: root.service ? root.service.statusMessage : ""
          color: root.foreground
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          visible: root.service && root.service.lastError !== ""
          text: root.service ? root.service.lastError : ""
          color: Color.urgent
          wrapMode: Text.WordWrap
        }
        Button {
          text: "Continue without signing in"
          foreground: root.foreground
          onClicked: {
            root.openedForLogin = false
            root.currentTab = "home"
            if (root.service) root.service.openView("home", false)
          }
        }
      }
    }
  }

  Component {
    id: homePage
    Flickable {
      clip: true
      contentHeight: homeColumn.implicitHeight
      Column {
        id: homeColumn
        width: parent.width
        spacing: Style.space(10)
      MediaCollection {
        width: parent.width
        height: Style.space(220)
        service: root.service
        sourceItems: root.service ? root.service.history : []
        showFilter: false
        showSort: false
        emptyMessage: "No recent tracks yet."
        visible: (root.service ? root.service.history : []).length > 0
        onActivated: function(item, items) { root.activateMedia(item, items, "") }
        onOpened: function(item) { root.openItem(item) }
        onQueued: function(item) { if (root.service) root.service.queueItem(item) }
        onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
        onPlaylistRequested: function(item) {
          root.contextItem = item
          playlistPicker.open()
        }
        onContextRequested: function(item, x, y, index, items) {
          root.openMediaContext(item, x, y, items)
        }
      }
      Repeater {
        model: root.service ? root.service.homeShelves : []
        MediaCollection {
          required property var modelData
          width: parent.width
          height: Style.space(240)
          service: root.service
          sourceItems: modelData.tracks || []
          showFilter: false
          showSort: false
          emptyMessage: ""
          onActivated: function(item, items) { root.activateMedia(item, items, "") }
          onOpened: function(item) { root.openItem(item) }
          onQueued: function(item) { if (root.service) root.service.queueItem(item) }
          onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
          onPlaylistRequested: function(item) {
            root.contextItem = item
            playlistPicker.open()
          }
          onContextRequested: function(item, x, y, index, items) {
            root.openMediaContext(item, x, y, items)
          }
        }
      }
      Text {
        width: parent.width
        visible: (!root.service || ((root.service.homeShelves || []).length === 0
          && (root.service.history || []).length === 0))
        text: root.service && root.service.homeLoading
          ? "Loading home…" : "Nothing on Home yet. Search for a song to start."
        color: Qt.darker(root.foreground, 1.4)
        horizontalAlignment: Text.AlignHCenter
      }
      }
    }
  }

  Component {
    id: searchPage
    MediaCollection {
      service: root.service
      sourceItems: root.service ? root.service.searchResults : []
      loading: root.service && root.service.searchLoading
      emptyMessage: root.searchText.trim() === ""
        ? "Search YouTube Music." : "No matching songs."
      onActivated: function(item, items) { root.activateMedia(item, items, "") }
      onOpened: function(item) { root.openItem(item) }
      onQueued: function(item) { if (root.service) root.service.queueItem(item) }
      onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
      onPlaylistRequested: function(item) {
        root.contextItem = item
        playlistPicker.open()
      }
      onContextRequested: function(item, x, y, index, items) {
        root.openMediaContext(item, x, y, items)
      }
    }
  }

  Component {
    id: libraryPage
    Column {
      spacing: Style.space(8)
      Row {
        spacing: Style.space(6)
        Repeater {
          model: [
            { id: "tracks", label: "Songs" },
            { id: "albums", label: "Albums" },
            { id: "artists", label: "Artists" }
          ]
          Button {
            required property var modelData
            text: modelData.label
            foreground: root.foreground
            selected: root.libraryType === modelData.id
            onClicked: {
              root.libraryType = modelData.id
              if (root.service) root.service.loadLibrary(modelData.id, false, true)
            }
          }
        }
      }
      MediaCollection {
        width: parent.width
        height: Math.max(80, parent.height - Style.space(48))
        service: root.service
        sourceItems: root.service ? root.service.libraryItems() : []
        filterText: root.libraryFilter
        sortKey: root.librarySort
        loading: root.service && root.service.libraryLoading
        browseContexts: true
        emptyMessage: root.accountConnected
          ? "Your library is empty." : "Sign in to see your library."
        onActivated: function(item, items) { root.activateMedia(item, items, "") }
        onOpened: function(item) { root.openItem(item) }
        onQueued: function(item) { if (root.service) root.service.queueItem(item) }
        onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
        onPlaylistRequested: function(item) {
          root.contextItem = item
          playlistPicker.open()
        }
        onContextRequested: function(item, x, y, index, items) {
          root.openMediaContext(item, x, y, items)
        }
        onViewStateChanged: function(filterText, sortKey) {
          root.libraryFilter = filterText
          root.librarySort = sortKey
        }
      }
    }
  }

  Component {
    id: playlistsPage
    MediaCollection {
      service: root.service
      sourceItems: root.service ? root.service.playlists : []
      filterText: root.playlistFilter
      sortKey: root.playlistSort
      loading: root.service && root.service.playlistsLoading
      browseContexts: true
      showQueue: false
      showSave: false
      emptyMessage: root.accountConnected
        ? "No playlists yet." : "Sign in to see playlists."
      onActivated: function(item) { root.openItem(item) }
      onOpened: function(item) { root.openItem(item) }
      onViewStateChanged: function(filterText, sortKey) {
        root.playlistFilter = filterText
        root.playlistSort = sortKey
      }
    }
  }

  Component {
    id: detailPage
    Column {
      spacing: Style.space(8)
      Row {
        width: parent.width
        spacing: Style.space(12)
        BorderSurface {
          width: Style.space(92)
          height: width
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground, root.accent)
          Image {
            anchors.fill: parent
            anchors.margins: Style.space(3)
            source: root.service && root.service.detailItem
              ? (root.service.detailItem.imageUrl || "") : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }
        }
        Column {
          width: parent.width - Style.space(104)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: root.service && root.service.detailItem
              ? (root.service.detailItem.description || root.service.detailItem.subtitle || "") : ""
            color: Qt.darker(root.foreground, 1.35)
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.pixelSize: Style.font.bodySmall
          }
          Row {
            spacing: Style.space(6)
            Button {
              text: "Play"
              iconText: "󰐊"
              selected: true
              foreground: root.foreground
              enabled: root.service && root.service.detailItem
              onClicked: if (root.service) root.service.playItem(root.service.detailItem)
            }
            Button {
              visible: root.service && root.service.detailItem
                && root.service.detailItem.type === "track"
              text: "Radio"
              iconText: "󰐹"
              foreground: root.foreground
              onClicked: if (root.service) root.service.startRadio(root.service.detailItem)
            }
          }
        }
      }
      MediaCollection {
        width: parent.width
        height: Math.max(80, parent.height - Style.space(130))
        service: root.service
        sourceItems: root.service ? root.service.detailTracks : []
        filterText: root.detailFilter
        sortKey: root.detailSort
        loading: root.service && root.service.detailLoading
        emptyMessage: root.service && root.service.detailLoading
          ? "Loading…" : "No songs on this page."
        onActivated: function(item, items) { root.activateMedia(item, items, "") }
        onOpened: function(item) { root.openItem(item) }
        onQueued: function(item) { if (root.service) root.service.queueItem(item) }
        onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
        onPlaylistRequested: function(item) {
          root.contextItem = item
          playlistPicker.open()
        }
        onContextRequested: function(item, x, y, index, items) {
          root.openMediaContext(item, x, y, items)
        }
        onViewStateChanged: function(filterText, sortKey) {
          root.detailFilter = filterText
          root.detailSort = sortKey
        }
      }
    }
  }

  Component {
    id: queuePage
    MediaCollection {
      service: root.service
      sourceItems: root.service && root.service.backendState
        ? (root.service.backendState.queue || []) : []
      filterText: root.queueFilter
      emptyMessage: "The queue is empty."
      onActivated: function(item, items) { root.activateMedia(item, items, "") }
      onOpened: function(item) { root.openItem(item) }
      onQueued: function(item) { if (root.service) root.service.queueItem(item) }
      onSaveToggled: function(item) { if (root.service) root.service.toggleSaved(item) }
      onContextRequested: function(item, x, y, index, items) {
        root.openMediaContext(item, x, y, items)
      }
      onViewStateChanged: function(filterText) { root.queueFilter = filterText }
    }
  }

  Component {
    id: setupPage
    Flickable {
      clip: true
      contentHeight: setupColumn.implicitHeight
      Column {
        id: setupColumn
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: root.accountConnected
            ? ("Signed in" + (root.service && root.service.backendState
              && root.service.backendState.account_name
              ? " as " + root.service.backendState.account_name : ""))
            : "Browsing without an account"
          color: root.foreground
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Row {
          spacing: Style.space(8)
          Button {
            text: root.accountConnected ? "Sign out" : "Sign in"
            foreground: root.foreground
            onClicked: {
              if (root.accountConnected && root.service) root.service.logout()
              else root.chooseTab("login")
            }
          }
          Button {
            text: "Open music.youtube.com"
            foreground: root.foreground
            onClicked: Quickshell.execDetached(["xdg-open", "https://music.youtube.com"])
          }
        }

        PanelSeparator { foreground: root.foreground }

        Text {
          text: "Bar and shortcuts"
          color: root.foreground
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
        Button {
          text: "Mini-player from bar: " + (root.draftShowMiniPlayer ? "On" : "Off")
          foreground: root.foreground
          onClicked: {
            root.draftShowMiniPlayer = !root.draftShowMiniPlayer
            root.persistDraftSettings()
          }
        }
        Button {
          text: "Shortcut opens: " + root.draftShortcutPlayer
          foreground: root.foreground
          onClicked: {
            root.draftShortcutPlayer = root.draftShortcutPlayer === "Full player"
              ? "Mini player" : "Full player"
            root.persistDraftSettings()
          }
        }
        Button {
          text: "Local quality: " + root.draftAudioQuality
          foreground: root.foreground
          onClicked: {
            root.draftAudioQuality = root.draftAudioQuality === "96 kbps" ? "160 kbps"
              : (root.draftAudioQuality === "160 kbps" ? "320 kbps" : "96 kbps")
            root.persistDraftSettings()
          }
        }
        Row {
          spacing: Style.space(8)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Stop when idle (minutes)"
            color: root.foreground
            font.pixelSize: Style.font.bodySmall
          }
          TextField {
            width: Style.space(72)
            foreground: root.foreground
            text: root.draftIdleMinutes
            onTextEdited: root.draftIdleMinutes = text
            onEditingFinished: root.persistDraftSettings()
          }
        }
        Text {
          width: parent.width
          text: "Playback uses mpv and yt-dlp on this computer. There is no Chromium and no official YouTube Music desktop client."
          color: Qt.darker(root.foreground, 1.45)
          wrapMode: Text.WordWrap
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "YouTube Music"
    color: root.background
    implicitWidth: 980
    implicitHeight: 720
    minimumSize: Qt.size(700, 560)

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: function(event) {
        if (root.dismissTransientPopup()) {
          root.escapeCloseArmed = false
          event.accepted = true
          return
        }
        if (root.currentTab === "detail" || root.navigationStack.length) {
          root.escapeCloseArmed = false
          root.goBack()
        } else if (root.escapeCloseArmed) root.requestClose()
        else {
          root.escapeCloseArmed = true
          escapeTimer.restart()
        }
        event.accepted = true
      }

      Timer {
        id: escapeTimer
        interval: 1600
        onTriggered: root.escapeCloseArmed = false
      }

      Shortcut { sequence: "Ctrl+K"; enabled: !root.shortcutsBlocked; onActivated: root.focusSearch() }
      Shortcut { sequence: "/"; enabled: !root.shortcutsBlocked && !root.textInputFocused(); onActivated: root.focusSearch() }
      Shortcut { sequence: "Alt+Left"; enabled: !root.shortcutsBlocked; onActivated: root.goBack() }
      Shortcut { sequence: "Ctrl+,"; enabled: !root.shortcutsBlocked; onActivated: root.chooseTab("setup") }
      Shortcut { sequence: "Alt+Shift+H"; enabled: !root.shortcutsBlocked; onActivated: root.chooseTab("home") }
      Shortcut { sequence: "Alt+Shift+Q"; enabled: !root.shortcutsBlocked; onActivated: root.chooseTab("queue") }
      Shortcut {
        sequence: "Ctrl+Shift+L"
        enabled: !root.shortcutsBlocked && !root.textInputFocused() && root.service && root.service.lyricsAvailable
        onActivated: root.openLyrics()
      }
      Shortcut {
        sequence: "Space"
        enabled: !root.shortcutsBlocked && !root.textInputFocused() && root.service
        onActivated: root.service.togglePlayback()
      }
      Shortcut {
        sequence: "Ctrl+Right"
        enabled: !root.shortcutsBlocked && !root.textInputFocused() && root.service
        onActivated: root.service.next()
      }
      Shortcut {
        sequence: "Ctrl+Left"
        enabled: !root.shortcutsBlocked && !root.textInputFocused() && root.service
        onActivated: root.service.previous()
      }
      Shortcut {
        sequence: "M"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
        onActivated: root.toggleMute()
      }
      Shortcut {
        sequence: "Ctrl+S"
        enabled: !root.shortcutsBlocked && !root.textInputFocused() && root.service
        onActivated: root.service.setShuffle(!root.service.shuffle)
      }
      Shortcut {
        sequence: "Ctrl+R"
        enabled: !root.shortcutsBlocked && !root.textInputFocused() && root.service
        onActivated: root.service.cycleRepeat()
      }
      Shortcut {
        sequence: "Shift+Left"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
        onActivated: root.seekBy(-10)
      }
      Shortcut {
        sequence: "Shift+Right"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
        onActivated: root.seekBy(10)
      }
      Shortcut {
        sequence: "Ctrl+Up"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
        onActivated: root.adjustVolume(0.05)
      }
      Shortcut {
        sequence: "Ctrl+Down"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
        onActivated: root.adjustVolume(-0.05)
      }
      Shortcut {
        sequence: "Ctrl+/"
        enabled: !root.textInputFocused()
        onActivated: root.toggleShortcutHelp()
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(14)

        Row {
          id: workspace
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: footerSeparator.top
          anchors.bottomMargin: Style.space(10)
          spacing: sidebar.visible ? Style.space(10) : 0

          BorderSurface {
            id: sidebar
            visible: root.currentTab !== "login"
            width: visible
              ? (root.compactWidth ? Style.space(54)
                : Math.min(Style.space(214), Math.max(Style.space(176), workspace.width * 0.225)))
              : 0
            height: parent.height
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, root.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

            Row {
              id: brandRow
              visible: !root.compactHeight
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: visible ? Style.space(11) : 0
              height: visible ? Style.space(42) : 0
              spacing: Style.space(9)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰝚"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
              }
              Column {
                visible: !root.compactWidth
                width: Math.max(40, parent.width - Style.space(38))
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  width: parent.width
                  text: "Music"
                  color: root.foreground
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
                Text {
                  width: parent.width
                  text: "for YouTube"
                  color: Qt.darker(root.foreground, 1.4)
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Column {
              id: primaryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: brandRow.visible ? brandRow.bottom : parent.top
              anchors.margins: Style.space(8)
              spacing: Style.space(2)

              PanelSeparator { width: parent.width; foreground: root.foreground }

              Repeater {
                model: root.primaryNavigationItems()
                Button {
                  required property var modelData
                  width: primaryNavigation.width
                  text: root.compactWidth ? "" : modelData.label
                  iconText: modelData.icon
                  foreground: root.foreground
                  selected: root.currentTab === modelData.id
                  leftAlign: !root.compactWidth
                  onClicked: root.chooseTab(modelData.id)
                }
              }

              PanelSeparator { width: parent.width; foreground: root.foreground }
            }

            Column {
              id: libraryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: primaryNavigation.bottom
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              anchors.topMargin: Style.space(6)
              spacing: Style.space(2)

              Button {
                width: parent.width
                text: root.compactWidth ? "" : "Liked Songs"
                iconText: "󰋑"
                foreground: root.foreground
                selected: root.currentTab === "library"
                leftAlign: !root.compactWidth
                onClicked: {
                  root.libraryType = "tracks"
                  root.chooseTab("library")
                }
              }
              Row {
                width: parent.width
                spacing: Style.space(2)
                Button {
                  width: Math.max(20, parent.width - createPlaylistShortcut.width - parent.spacing)
                  text: root.compactWidth ? "" : "Playlists"
                  iconText: "󱁐"
                  foreground: root.foreground
                  selected: root.currentTab === "playlists"
                  leftAlign: !root.compactWidth
                  onClicked: root.chooseTab("playlists")
                }
                Button {
                  id: createPlaylistShortcut
                  text: "+"
                  foreground: root.foreground
                  enabled: root.accountConnected
                  onClicked: createPlaylistPopup.open()
                }
              }
            }

            ListView {
              id: playlistShortcuts
              visible: !root.compactWidth
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: libraryNavigation.bottom
              anchors.bottom: setupNavButton.top
              anchors.margins: Style.space(8)
              model: root.service ? root.service.playlists : []
              clip: true
              spacing: Style.space(1)
              delegate: Button {
                required property var modelData
                width: ListView.view.width
                text: modelData.name || "Playlist"
                iconText: "󰲸"
                foreground: root.foreground
                leftAlign: true
                selected: root.currentTab === "detail" && root.service
                  && root.service.selectedPlaylist
                  && root.service.selectedPlaylist.id === modelData.id
                onClicked: {
                  root.chooseTab("playlists")
                  if (root.service) root.service.openPlaylist(modelData)
                  root.currentTab = "detail"
                }
              }
            }

            Button {
              id: setupNavButton
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(8)
              text: root.compactWidth ? "" : "Settings"
              iconText: "󰒓"
              foreground: root.foreground
              selected: root.currentTab === "setup"
              leftAlign: !root.compactWidth
              onClicked: root.chooseTab("setup")
            }
          }

          Item {
            id: contentPane
            width: Math.max(220, parent.width - sidebar.width - workspace.spacing)
            height: parent.height

            Row {
              id: pageHeader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Style.space(52)
              spacing: Style.space(5)

              Button {
                id: backButton
                visible: root.currentTab === "detail" || root.navigationStack.length > 0
                iconText: "󰁍"
                foreground: root.foreground
                tooltipText: root.shortcutHint("Back", "Alt+Left")
                onClicked: root.goBack()
              }
              Column {
                width: Math.max(80, parent.width
                  - (backButton.visible ? backButton.width + parent.spacing : 0)
                  - shortcutHelpButton.width - refreshButton.width - closeButton.width
                  - parent.spacing * 3)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  width: parent.width
                  text: root.pageTitle()
                  color: root.foreground
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: root.pageSubtitle()
                  color: Qt.darker(root.foreground, 1.4)
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
              Button {
                id: shortcutHelpButton
                text: "?"
                foreground: root.foreground
                tooltipText: root.shortcutHint("Keyboard shortcuts", "Ctrl+/")
                onClicked: root.toggleShortcutHelp()
              }
              Button {
                id: refreshButton
                visible: root.currentTab !== "login" && root.currentTab !== "setup"
                iconText: "󰑐"
                foreground: root.foreground
                tooltipText: "Refresh"
                onClicked: {
                  if (!root.service) return
                  if (root.currentTab === "search") root.runSearch()
                  else if (root.currentTab === "detail" && root.service.detailItem)
                    root.service.openDetail(root.service.detailItem)
                  else root.service.refreshView(root.currentTab)
                }
              }
              Button {
                id: closeButton
                iconText: "󰅖"
                foreground: root.escapeCloseArmed ? Color.urgent : root.foreground
                tooltipText: root.escapeCloseArmed ? "Press Esc again to close"
                  : root.shortcutHint("Close", "Esc, Esc")
                onClicked: root.requestClose()
              }
            }

            BorderSurface {
              id: statusBanner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: pageHeader.bottom
              anchors.topMargin: visible ? Style.space(6) : 0
              implicitHeight: visible ? messageText.implicitHeight + Style.space(12) : 0
              height: implicitHeight
              visible: root.service && (root.service.lastError !== "" || root.service.statusMessage !== "")
              color: root.service && root.service.lastError !== ""
                ? Style.selectedFillFor(root.foreground, Color.urgent)
                : Style.normalFillFor(root.foreground, root.accent)
              radius: Style.cornerRadius
              Text {
                id: messageText
                anchors.fill: parent
                anchors.margins: Style.space(6)
                text: !root.service ? "" : (root.service.lastError || root.service.statusMessage)
                color: root.foreground
                wrapMode: Text.WordWrap
                font.pixelSize: Style.font.bodySmall
              }
            }

            Row {
              id: unifiedSearchBar
              visible: root.currentTab !== "login" && root.currentTab !== "setup"
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: statusBanner.visible ? statusBanner.bottom : pageHeader.bottom
              anchors.topMargin: visible ? Style.space(8) : 0
              height: visible ? Style.space(38) : 0
              spacing: Style.space(6)

              TextField {
                id: unifiedSearchField
                width: parent.width
                height: parent.height
                foreground: root.foreground
                placeholderText: "Search YouTube Music"
                text: root.searchText
                onTextEdited: root.searchText = text
                onAccepted: root.runSearch()
              }
            }

            Loader {
              id: pageLoader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: unifiedSearchBar.visible ? unifiedSearchBar.bottom
                : (statusBanner.visible ? statusBanner.bottom : pageHeader.bottom)
              anchors.topMargin: Style.space(8)
              anchors.bottom: parent.bottom
              sourceComponent: root.pageComponent()
            }
          }
        }

        PanelSeparator {
          id: footerSeparator
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: playerFooter.top
          anchors.bottomMargin: Style.space(10)
          foreground: root.foreground
        }

        BorderSurface {
          id: playerFooter
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: visible ? Style.space(root.compactHeight ? 88 : 104) : 0
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

          Row {
            id: playerRow
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(12)

            Row {
              width: Math.max(Style.space(170), Math.min(Style.space(240), playerRow.width * 0.29))
              height: parent.height
              spacing: Style.space(9)

              BorderSurface {
                width: Math.min(parent.height, Style.space(68))
                height: width
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.cornerRadius
                Image {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  source: root.service ? root.service.artUrl : ""
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  visible: status === Image.Ready
                }
              }
              Column {
                width: Math.max(40, parent.width - parent.height - parent.spacing)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)
                Row {
                  width: parent.width
                  spacing: Style.space(3)
                  Text {
                    width: Math.max(20, parent.width - likeButton.width - parent.spacing)
                    text: root.service && root.service.title ? root.service.title : "Nothing playing"
                    color: root.foreground
                    font.bold: true
                    elide: Text.ElideRight
                    font.pixelSize: Style.font.body
                  }
                  Button {
                    id: likeButton
                    visible: root.service && !!root.service.currentTrackItem
                    iconText: root.service && root.service.currentTrackSaved ? "󰋑" : "󰋕"
                    selected: root.service && root.service.currentTrackSaved
                    foreground: root.foreground
                    onClicked: if (root.service) root.service.toggleCurrentTrackSaved()
                  }
                }
                Text {
                  width: parent.width
                  text: root.service ? root.service.artist : ""
                  color: Qt.darker(root.foreground, 1.38)
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            Column {
              width: Math.max(120, parent.width - Style.space(420))
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(3)
                Button {
                  iconText: "󰒟"
                  selected: root.service && root.service.shuffle
                  foreground: root.foreground
                  onClicked: if (root.service) root.service.setShuffle(!root.service.shuffle)
                }
                Button {
                  iconText: "󰒮"
                  foreground: root.foreground
                  onClicked: if (root.service) root.service.previous()
                }
                Button {
                  iconText: root.service && root.service.playing ? "󰏤" : "󰐊"
                  iconSize: Style.font.iconLarge
                  foreground: root.foreground
                  onClicked: if (root.service) root.service.togglePlayback()
                }
                Button {
                  iconText: "󰒭"
                  foreground: root.foreground
                  onClicked: if (root.service) root.service.next()
                }
                Button {
                  iconText: root.service && root.service.repeatMode === "track" ? "󰑘" : "󰑖"
                  selected: root.service && root.service.repeatMode !== "off"
                  foreground: root.foreground
                  onClicked: if (root.service) root.service.cycleRepeat()
                }
                Button {
                  iconText: "󰎈"
                  foreground: root.foreground
                  enabled: root.service && root.service.lyricsAvailable
                  onClicked: root.openLyrics()
                }
                Button {
                  iconText: "󰒲"
                  foreground: root.foreground
                  selected: root.service && root.service.sleepActive
                  tooltipText: "Sleep timer"
                  onClicked: sleepPopup.open()
                }
              }
              Row {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: Api.millisecondsToClock((root.service ? root.service.positionSeconds : 0) * 1000)
                  color: Qt.darker(root.foreground, 1.4)
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
                PlaybackSlider {
                  width: parent.width - Style.space(90)
                  bar: root.panelBar
                  minimum: 0
                  maximum: Math.max(1, root.service ? root.service.lengthSeconds : 1)
                  sourceValue: root.service ? root.service.positionSeconds : 0
                  sourcePending: root.service && root.service.pendingSeek !== null
                  acknowledgeTolerance: 2
                  contextKey: root.service ? root.service.currentUri : ""
                  onCommitted: function(value) {
                    if (root.service) root.service.seekSeconds(value)
                  }
                }
                Text {
                  text: Api.millisecondsToClock((root.service ? root.service.lengthSeconds : 0) * 1000)
                  color: Qt.darker(root.foreground, 1.4)
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            Row {
              width: Style.space(160)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              Text {
                text: root.service && root.service.volume <= 0.001 ? "󰝟" : "󰕾"
                color: root.foreground
                font.pixelSize: Style.font.icon
                anchors.verticalCenter: parent.verticalCenter
              }
              PlaybackSlider {
                width: parent.width - Style.space(28)
                bar: root.panelBar
                minimum: 0
                maximum: 1
                step: 0.05
                sourceValue: root.service ? root.service.volume : 0
                onCommitted: function(value) {
                  if (root.service) root.service.setVolume(value)
                }
              }
            }
          }
        }
      }
    }
  }
}
