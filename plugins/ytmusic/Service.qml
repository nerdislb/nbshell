import QtQuick
import Quickshell
import Quickshell.Io

import "Api.js" as Api

Item {
  id: root

  visible: false
  width: 0
  height: 0

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "ytmusic"
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""

  readonly property var defaultSettingValues: ({
    idleShutdownMinutes: 15,
    showMiniPlayer: "On",
    shortcutPlayer: "Full player",
    audioQuality: "320 kbps",
    searchHistory: "[]",
    sessionState: "{}"
  })
  property var settings: Api.shallowCopy(defaultSettingValues)

  readonly property int idleShutdownMinutes: Math.max(0, Math.min(1440,
    Math.floor(Number(settings.idleShutdownMinutes) || 0)))
  readonly property bool showMiniPlayer: String(settings.showMiniPlayer || "On") !== "Off"
  readonly property string shortcutPlayer: Api.normalizedShortcutPlayer(
    settings.shortcutPlayer)
  readonly property int bitrateKbps: Api.qualityKbps(settings.audioQuality)
  readonly property string audioQuality: Api.qualityLabel(bitrateKbps)
  readonly property var searchHistory: Api.parseStringList(settings.searchHistory, 12)
  readonly property var sessionState: {
    var parsed = Api.parseJson(String(settings.sessionState || "{}"), ({}))
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
  }

  readonly property alias daemon: daemonManager
  readonly property alias backend: backendClient
  readonly property bool accountConnected: backendClient.sessionConnected
    || (backendState && backendState.signed_in === true)
  readonly property string accountName: backendState
    ? String(backendState.account_name || "") : ""
  readonly property bool sessionPending: !daemonManager.requirementsChecked
  readonly property bool fullyConnected: daemonManager.playbackReady && backendClient.ready
  property bool authBusy: false
  readonly property bool loginBusy: daemonManager.setupBusy || daemonManager.busy
    || authBusy || !daemonManager.requirementsChecked
    || (uiVisible && daemonManager.playbackReady && !backendClient.ready)
  readonly property string loginProgress: loginProgressText()

  property var backendState: null
  property var visibleSurfaces: ({})
  readonly property bool uiVisible: {
    for (var key in visibleSurfaces)
      if (visibleSurfaces[key]) return true
    return false
  }

  readonly property var currentTrackItem: backendState && backendState.track
    ? backendState.track : null
  readonly property bool hasPlayer: backendClient.ready || daemonManager.running
  readonly property bool hasMedia: !!currentTrackItem
  readonly property bool playing: backendState && backendState.playing === true
  readonly property string title: currentTrackItem ? String(currentTrackItem.name || "") : ""
  readonly property string artist: currentTrackItem ? String(currentTrackItem.subtitle || "") : ""
  readonly property string album: currentTrackItem ? String(currentTrackItem.album || "") : ""
  readonly property string artUrl: currentTrackItem ? String(currentTrackItem.imageUrl || "") : ""
  readonly property string currentTrackId: currentTrackItem
    ? String(currentTrackItem.videoId || currentTrackItem.id || "") : ""
  readonly property string currentUri: currentTrackItem ? String(currentTrackItem.uri || "") : ""
  readonly property var currentArtists: currentTrackItem
    ? Api.arrayValues(currentTrackItem.artists) : []
  readonly property bool currentArtistContextAvailable: currentArtists.length > 0
    && !!(currentArtists[0] && currentArtists[0].id)
  readonly property var currentAlbumItem: currentTrackItem ? currentTrackItem.albumItem : null
  readonly property real volume: backendState
    ? Math.max(0, Math.min(1, (Number(backendState.volume) || 0) / 100)) : 0.8
  readonly property bool volumeSupported: hasPlayer
  readonly property bool shuffle: backendState && backendState.shuffle === true
  readonly property string repeatMode: backendState
    ? String(backendState.repeat || "off") : "off"
  readonly property bool playbackControllable: backendClient.ready && hasMedia
  readonly property bool currentTrackSaved: currentTrackItem && currentTrackItem.liked === true
  readonly property bool currentTrackSaveAvailable: accountConnected && currentTrackId !== ""
  property bool currentTrackSaveBusy: false
  property bool currentTrackSaveChecking: false
  readonly property var currentLyricsSong: Api.lyricsSong(currentTrackId,
    title, artist, album, lengthSeconds, artUrl, positionSeconds)
  readonly property bool lyricsAvailable: currentLyricsSong !== null
  readonly property string lyricsPluginId: "stappmus.lyrics"
  readonly property string lyricsPluginUrl: "https://github.com/stappmus/Omasing.git"
  readonly property string lyricsPluginAvailability: {
    var plugins = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins : ({})
    var installed = !!plugins[lyricsPluginId]
    var enabled = installed && pluginRegistry
      && typeof pluginRegistry.inBar === "function"
      && pluginRegistry.inBar(lyricsPluginId)
    return Api.optionalPluginState(installed, enabled)
  }
  property bool lyricsPluginBusy: false
  property string lyricsPluginOperation: ""
  property string lyricsPluginError: ""
  property string lyricsPluginRequestSurface: ""
  property var pendingLyricsSong: null
  property int lyricsPluginLaunchAttempts: 0

  property real interpolatedPosition: 0
  property double positionStamp: 0
  readonly property real backendPositionSeconds: backendState
    ? Math.max(0, Number(backendState.position_ms) || 0) / 1000 : 0
  readonly property real lengthSeconds: backendState
    ? Math.max(0, Number(backendState.duration_ms) || 0) / 1000 : 0
  readonly property real positionSeconds: {
    playbackPositionTick
    if (!playing) return backendPositionSeconds
    var elapsed = (Date.now() - positionStamp) / 1000
    var next = interpolatedPosition + elapsed
    return lengthSeconds > 0 ? Math.min(lengthSeconds, next) : next
  }
  property int playbackPositionTick: 0
  property var pendingSeek: null

  property string lastError: ""
  property string statusMessage: ""
  property var homeShelves: []
  property var history: []
  property var liked: []
  property var playlists: []
  property var librarySongs: []
  property var libraryAlbums: []
  property var libraryArtists: []
  property var searchResults: []
  property var searchSections: []
  property string searchQuery: ""
  property var detailItem: null
  property var detailTracks: []
  property var detailAlbums: []
  property var selectedPlaylist: null
  property bool homeLoading: false
  property bool libraryLoading: false
  property bool playlistsLoading: false
  property bool searchLoading: false
  property bool detailLoading: false
  property string libraryType: "tracks"
  property string lastRadioPlaylistId: ""
  property bool sleepActive: backendState && backendState.sleep_active === true

  signal operationFailed(string reason)
  signal lyricsPluginPromptRequested(string surface, string availability)
  signal lyricsPluginOpened(string surface)

  function loginProgressText() {
    if (daemonManager.setupBusy) return "Installing playback"
    if (!daemonManager.playbackReady) return "Preparing YouTube Music"
    if (daemonManager.busy) return "Starting playback"
    if (!backendClient.ready) return "Connecting"
    if (!accountConnected) return "Sign in to YouTube Music"
    return "Connected"
  }

  function applySettings(values) {
    var next = normalizedSettings(values)
    if (JSON.stringify(next) !== JSON.stringify(settings)) settings = next
    daemonManager.bitrateKbps = bitrateKbps
    daemonManager.idleMinutes = idleShutdownMinutes
    if (backendClient.ready) {
      backendClient.sendCommand("set_idle_minutes", { minutes: idleShutdownMinutes })
      backendClient.sendCommand("set_quality", { kbps: bitrateKbps })
    }
  }

  function normalizedSettings(values) {
    var source = values && typeof values === "object" ? values : ({})
    var next = Api.shallowCopy(defaultSettingValues)
    for (var key in source) {
      if (source[key] !== undefined && source[key] !== null)
        next[key] = source[key]
    }
    next.idleShutdownMinutes = Math.max(0, Math.min(1440,
      Math.floor(Number(next.idleShutdownMinutes) || 0)))
    next.shortcutPlayer = Api.normalizedShortcutPlayer(next.shortcutPlayer)
    next.audioQuality = Api.qualityLabel(Api.qualityKbps(next.audioQuality))
    if (typeof next.searchHistory !== "string")
      next.searchHistory = JSON.stringify(Api.parseStringList(next.searchHistory, 12))
    if (typeof next.sessionState !== "string")
      next.sessionState = JSON.stringify(next.sessionState || ({}))
    return next
  }

  function persistSettings(values) {
    var next = normalizedSettings(Api.assign(Api.shallowCopy(settings), values))
    applySettings(next)
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline(pluginId, next)
  }

  function persistSession(values) {
    persistSettings({ sessionState: values || ({}) })
  }

  function rememberSearch(term) {
    var next = Api.touchHistory(searchHistory, term, 12)
    if (JSON.stringify(next) !== JSON.stringify(searchHistory))
      persistSettings({ searchHistory: next })
  }

  function configuredEntry() {
    var config = shell && shell.shellConfig ? shell.shellConfig : null
    if (!config) return null
    var layout = config.bar && config.bar.layout ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    if (layout) {
      for (var s = 0; s < sections.length; s++) {
        var rows = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
        for (var i = 0; i < rows.length; i++)
          if (rows[i] && String(rows[i].id || "") === pluginId) return rows[i]
      }
    }
    var plugins = Array.isArray(config.plugins) ? config.plugins : []
    for (var p = 0; p < plugins.length; p++)
      if (plugins[p] && String(plugins[p].id || "") === pluginId) return plugins[p]
    return null
  }

  function syncSettings() {
    applySettings(configuredEntry() || {})
  }

  function fail(reason) {
    statusClearTimer.stop()
    lastError = Api.redact(String(reason || "YouTube Music operation failed"))
    statusMessage = ""
    operationFailed(lastError)
  }

  function succeed(message) {
    lastError = ""
    statusMessage = String(message || "")
    if (statusMessage) statusClearTimer.restart()
    else statusClearTimer.stop()
  }

  function applyBackendState(state) {
    if (!state || typeof state !== "object") return
    backendState = state
    interpolatedPosition = Math.max(0, Number(state.position_ms) || 0) / 1000
    positionStamp = Date.now()
    if (state.error) lastError = Api.redact(String(state.error))
    pendingSeek = null
  }

  property var readyWaiters: []
  property int readyWaitTicks: 0

  function flushReadyWaiters(ok) {
    readyWaitTimer.stop()
    readyWaitTicks = 0
    var waiters = readyWaiters
    readyWaiters = []
    for (var i = 0; i < waiters.length; i++)
      if (typeof waiters[i] === "function") waiters[i](ok === true)
  }

  function ensureBackend(callback) {
    function ready(ok) {
      if (typeof callback === "function") callback(ok === true)
    }
    if (backendClient.ready) {
      ready(true)
      return
    }
    if (!daemonManager.playbackReady) {
      daemonManager.setupPlayback()
      fail("Installing playback on this computer…")
      ready(false)
      return
    }
    daemonManager.start()
    backendClient.wanted = true
    readyWaiters = readyWaiters.concat([ready])
    readyWaitTicks = 0
    if (!readyWaitTimer.running) readyWaitTimer.start()
  }

  function command(name, fields, successMessage, done) {
    ensureBackend(function(ok) {
      if (!ok || !backendClient.ready) {
        if (!root.lastError) root.fail("YouTube Music is not ready")
        if (typeof done === "function") done(false)
        return
      }
      backendClient.sendCommand(name, fields || {}, function(succeeded, result, error) {
        if (!succeeded) {
          root.fail(error)
          if (typeof done === "function") done(false, null)
          return
        }
        lastError = ""
        if (result && typeof result === "object") root.applyBackendState(result)
        if (successMessage) root.succeed(successMessage)
        if (typeof done === "function") done(true, result)
      })
    })
  }

  function setUiVisible(key, value) {
    var name = String(key || "surface")
    var next = ({})
    for (var oldKey in visibleSurfaces)
      if (oldKey !== name && visibleSurfaces[oldKey]) next[oldKey] = true
    if (value) next[name] = true
    visibleSurfaces = next
    if (value) {
      ensureBackend()
      if (idleShutdownMinutes === 0 && daemonManager.playbackReady)
        daemonManager.start()
    }
  }

  function refreshPosition() {
    playbackPositionTick++
  }

  function login() {
    lastError = ""
    if (!daemonManager.playbackReady) daemonManager.setupPlayback()
    else {
      daemonManager.start()
      backendClient.wanted = true
    }
  }

  function cancelLogin() {
    lastError = ""
    statusMessage = ""
  }

  function setupAuth(headersRaw) {
    lastError = ""
    authBusy = true
    command("setup_auth", { headers_raw: String(headersRaw || "") },
      "Connected to YouTube Music", function(ok) {
        authBusy = false
        if (ok) root.refreshLibrary()
      })
  }

  function importBrowserAuth() {
    lastError = ""
    authBusy = true
    command("import_browser", {},
      "Connected to YouTube Music", function(ok) {
        authBusy = false
        if (ok) root.refreshLibrary()
      })
  }

  function logout() {
    command("logout", {}, "Signed out", function() {
      root.clearData()
    })
  }

  function clearData() {
    homeShelves = []
    history = []
    liked = []
    playlists = []
    librarySongs = []
    libraryAlbums = []
    libraryArtists = []
    searchResults = []
    searchSections = []
    detailItem = null
    detailTracks = []
    detailAlbums = []
    selectedPlaylist = null
  }

  function togglePlayback() { command("toggle") }
  function play() { command("play") }
  function pause() { command("pause") }
  function next() { command("next") }
  function previous() { command("previous") }
  function setShuffle(value) { command("set_shuffle", { shuffle: !!value }) }
  function cycleRepeat() {
    var nextMode = repeatMode === "off" ? "context"
      : (repeatMode === "context" ? "track" : "off")
    command("set_repeat", { mode: nextMode })
  }
  function setVolume(value) {
    command("set_volume", { volume: Math.round(Api.clampUnit(value) * 100) })
  }
  function seekSeconds(value) {
    pendingSeek = Number(value) || 0
    interpolatedPosition = pendingSeek
    positionStamp = Date.now()
    command("seek", { position_ms: Math.round(pendingSeek * 1000) })
  }

  function playItem(item, sourceItems, contextUri) {
    if (!item) return
    if (item.kind === "context" || (item.type && item.type !== "track")) {
      openDetail(item)
      var fields = {}
      if (item.type === "playlist") fields.playlist_id = item.id || item.playlistId
      else if (item.type === "album") fields.album_id = item.id
      else if (item.type === "artist") fields.artist_id = item.id
      if (!fields.playlist_id && !fields.album_id && !fields.artist_id) {
        fail("This YouTube Music item cannot be played")
        return
      }
      command("load", fields, "Playing " + (item.name || "selection"))
      return
    }
    var queue = []
    var source = Api.arrayValues(sourceItems)
    var index = 0
    if (source.length) {
      for (var i = 0; i < source.length; i++) {
        if (source[i] && source[i].type === "track" && source[i].videoId)
          queue.push(source[i])
      }
      for (var q = 0; q < queue.length; q++) {
        if (String(queue[q].videoId) === String(item.videoId)) {
          index = q
          break
        }
      }
    }
    if (!queue.length && item.videoId) queue = [item]
    if (!queue.length) {
      fail("This YouTube Music item cannot be played")
      return
    }
    command("load", { items: queue, index: index }, "Playing " + (item.name || "track"))
  }

  function startRadio(item) {
    var videoId = Api.videoIdOf(item)
    if (!videoId) {
      fail("Track radio is available for songs")
      return
    }
    command("load", { video_id: videoId, radio: true, name: item.name,
      subtitle: item.subtitle }, "Starting radio")
  }

  function queueItem(item) {
    if (!item || item.type !== "track") {
      fail("Only songs can be queued")
      return
    }
    command("add_to_queue", { item: item }, "Added to queue")
  }

  function isSaved(item) {
    if (!item || item.type !== "track") return false
    if (item.liked === true) return true
    if (currentTrackItem && String(currentTrackItem.videoId) === String(item.videoId))
      return currentTrackSaved
    return false
  }

  function toggleSaved(item) {
    var videoId = Api.videoIdOf(item) || currentTrackId
    if (!videoId) return
    var liked = !(item && item.liked === true)
    if (!item && currentTrackItem) liked = !currentTrackSaved
    currentTrackSaveBusy = true
    command("like", { video_id: videoId, liked: liked }, liked ? "Liked" : "Removed like",
      function() { root.currentTrackSaveBusy = false })
  }

  function toggleCurrentTrackSaved() {
    toggleSaved(currentTrackItem)
  }

  function addToPlaylist(playlist, item) {
    if (!playlist || !item) return
    command("add_to_playlist", {
      playlist_id: playlist.id || playlist.playlistId,
      video_id: Api.videoIdOf(item)
    }, "Added to " + (playlist.name || "playlist"))
  }

  function createPlaylist(name, done) {
    command("create_playlist", { name: name }, "Playlist created", function(ok, result) {
      if (ok) root.loadPlaylists()
      if (typeof done === "function") done(ok && result ? result.playlist : null)
    })
  }

  function sleepIn(minutes) {
    command("sleep", { minutes: minutes }, "Sleep timer set")
  }
  function sleepAfterTrack() { command("sleep", { after: "track" }, "Sleep after this song") }
  function sleepAfterContext() { command("sleep", { after: "context" }, "Sleep after this list") }
  function cancelSleepTimer() { command("cancel_sleep", {}, "Sleep timer canceled") }

  function search(query) {
    var term = String(query || "").trim()
    searchQuery = term
    if (!term) {
      searchResults = []
      searchSections = []
      return
    }
    searchLoading = true
    rememberSearch(term)
    command("search", { query: term }, "", function(ok, result) {
      root.searchLoading = false
      if (!ok || !result) return
      root.searchResults = result.items || []
      root.searchSections = result.sections || []
    })
  }

  function clearSearch() {
    searchQuery = ""
    searchResults = []
    searchSections = []
  }

  function cancelSearch() {}

  function openView(view, force) {
    if (view === "home") loadHome(force)
    else if (view === "library") loadLibrary(libraryType, false, force)
    else if (view === "playlists") loadPlaylists()
    else if (view === "search" && searchQuery) search(searchQuery)
    else if (view === "queue") {}
  }

  function refreshView(view) {
    openView(view, true)
  }

  function loadHome(force) {
    if (homeLoading && !force) return
    homeLoading = true
    command("browse", { view: "home" }, "", function(ok, result) {
      root.homeLoading = false
      if (!ok || !result) return
      root.homeShelves = result.home || []
    })
    command("browse", { view: "history" }, "", function(ok, result) {
      if (ok && result) root.history = result.items || []
    })
    if (accountConnected) {
      command("browse", { view: "liked" }, "", function(ok, result) {
        if (ok && result) root.liked = result.items || []
      })
      if (playlists.length === 0 && !playlistsLoading) loadPlaylists()
    }
  }

  function loadLibrary(kind, more, force) {
    libraryType = kind || libraryType
    libraryLoading = true
    var view = libraryType === "albums" ? "library_albums"
      : (libraryType === "artists" ? "library_artists" : "library_songs")
    command("browse", { view: view }, "", function(ok, result) {
      root.libraryLoading = false
      if (!ok || !result) return
      if (root.libraryType === "albums") root.libraryAlbums = result.items || []
      else if (root.libraryType === "artists") root.libraryArtists = result.items || []
      else root.librarySongs = result.items || []
    })
  }

  function libraryItems() {
    if (libraryType === "albums") return libraryAlbums
    if (libraryType === "artists") return libraryArtists
    return librarySongs
  }

  function loadPlaylists() {
    if (playlistsLoading) return
    playlistsLoading = true
    command("browse", { view: "playlists" }, "", function(ok, result) {
      root.playlistsLoading = false
      if (ok && result) root.playlists = result.items || []
    })
  }

  function sidebarPlaylists() {
    return playlists.slice(0, 24)
  }

  function playlistById(id) {
    var value = String(id || "")
    for (var i = 0; i < playlists.length; i++)
      if (String(playlists[i].id) === value) return playlists[i]
    return null
  }

  function refreshLibrary() {
    // Put the most visible navigation data first. The backend processes one
    // client stream in order, so loading Home before playlists made the
    // sidebar look empty while several slower requests completed.
    loadPlaylists()
    loadHome(true)
    loadLibrary(libraryType, false, true)
  }

  function openPlaylist(item) {
    selectedPlaylist = item
    openDetail(item)
  }

  function openDetail(item) {
    if (!item) return
    detailItem = item
    detailTracks = []
    detailAlbums = []
    detailLoading = true
    var commandName = item.type === "album" ? "get_album"
      : (item.type === "artist" ? "get_artist" : "get_playlist")
    var ident = item.id || item.playlistId
    if (!ident) {
      detailLoading = false
      fail("That page is not available")
      return
    }
    // `id` is reserved for the request/response correlation in BackendClient.
    // Using it for a media ID overwrote the callback key and left Details in
    // an endless loading state even though the backend had already replied.
    command(commandName, { item_id: ident }, "", function(ok, result) {
      root.detailLoading = false
      if (!ok || !result) return
      root.detailItem = result
      root.detailTracks = result.tracks || []
      root.detailAlbums = (result.albums || []).concat(result.singles || [])
      if (result.type === "playlist") root.selectedPlaylist = result
    })
  }

  function currentContext(kind, done) {
    if (kind === "album" && currentAlbumItem) {
      if (typeof done === "function") done(currentAlbumItem)
      return
    }
    if (kind === "artist" && currentArtists.length) {
      if (typeof done === "function") done(currentArtists[0])
      return
    }
    if (typeof done === "function") done(null)
  }

  function requestLyrics(surface) {
    if (!currentLyricsSong) return "unavailable"
    lyricsPluginRequestSurface = String(surface || "")
    pendingLyricsSong = currentLyricsSong
    lyricsPluginError = ""
    lyricsPluginLaunchAttempts = 0
    if (lyricsPluginAvailability === "ready") {
      launchLyricsPlugin()
      return "opening"
    }
    lyricsPluginPromptRequested(lyricsPluginRequestSurface, lyricsPluginAvailability)
    return lyricsPluginAvailability
  }

  function confirmLyricsPlugin(surface) {
    lyricsPluginError = "Lyrics integration is not available in the nbshell port yet."
    return false
  }

  function cancelLyricsPlugin(surface) {
    if (lyricsPluginBusy) return
    if (surface && String(surface) !== lyricsPluginRequestSurface) return
    lyricsPluginRequestSurface = ""
    pendingLyricsSong = null
    lyricsPluginError = ""
  }

  function launchLyricsPlugin() {
    if (!pendingLyricsSong || lyricsPluginLaunchProcess.running) return
    lyricsPluginLaunchAttempts++
    lyricsPluginLaunchProcess.command = ["omarchy-shell", lyricsPluginId,
      "lyrics", JSON.stringify(pendingLyricsSong)]
    lyricsPluginLaunchProcess.running = true
  }

  function finishLyricsPluginLaunch(exitCode) {
    if (Number(exitCode) === 0) {
      var openedSurface = lyricsPluginRequestSurface
      pendingLyricsSong = null
      lyricsPluginRequestSurface = ""
      lyricsPluginError = ""
      lyricsPluginLaunchAttempts = 0
      lyricsPluginOpened(openedSurface)
      return
    }
    if (lyricsPluginLaunchAttempts < 8) {
      lyricsPluginLaunchRetry.restart()
      return
    }
    var detail = String(lyricsPluginLaunchStderr.text || "").trim()
    lyricsPluginError = Api.redact(detail
      || "Omasing is installed, but its lyrics window could not be opened.")
    lyricsPluginPromptRequested(lyricsPluginRequestSurface, lyricsPluginAvailability)
  }

  BackendClient {
    id: backendClient
    wanted: daemonManager.running || root.uiVisible
    onStateReceived: function(state) { root.applyBackendState(state) }
    onReadyChanged: {
      if (ready) {
        root.flushReadyWaiters(true)
        sendCommand("set_idle_minutes", { minutes: root.idleShutdownMinutes })
        sendCommand("set_quality", { kbps: root.bitrateKbps })
        if (root.uiVisible) root.loadHome(true)
      }
    }
  }

  DaemonManager {
    id: daemonManager
    pluginDir: root.pluginDir
    bitrateKbps: root.bitrateKbps
    idleMinutes: root.idleShutdownMinutes
    onStarted: backendClient.wanted = true
    onStopped: if (!root.uiVisible) backendClient.wanted = false
    onSetupSucceeded: start()
  }

  Timer {
    id: readyWaitTimer
    interval: 120
    repeat: true
    onTriggered: {
      root.readyWaitTicks++
      if (backendClient.ready) {
        root.flushReadyWaiters(true)
      } else if (root.readyWaitTicks >= 40) {
        root.fail("YouTube Music is not ready")
        root.flushReadyWaiters(false)
      }
    }
  }

  Timer {
    id: statusClearTimer
    interval: 4000
    onTriggered: root.statusMessage = ""
  }

  Timer {
    interval: 250
    running: root.playing
    repeat: true
    onTriggered: root.playbackPositionTick++
  }

  Process {
    id: lyricsPluginSetupProcess
    running: false
    stderr: StdioCollector { }
    onExited: function(code) {
      root.lyricsPluginBusy = false
      root.lyricsPluginOperation = ""
      if (Number(code) === 0) {
        root.lyricsPluginLaunchAttempts = 0
        root.launchLyricsPlugin()
      } else {
        root.lyricsPluginError = Api.redact(String(stderr.text || "").trim()
          || "Omasing could not be installed.")
        root.lyricsPluginPromptRequested(root.lyricsPluginRequestSurface,
          root.lyricsPluginAvailability)
      }
    }
  }

  Process {
    id: lyricsPluginLaunchProcess
    running: false
    stderr: StdioCollector { id: lyricsPluginLaunchStderr }
    onExited: function(code) { root.finishLyricsPluginLaunch(code) }
  }

  Timer {
    id: lyricsPluginLaunchRetry
    interval: 400
    onTriggered: root.launchLyricsPlugin()
  }

  Component.onCompleted: {
    syncSettings()
    daemonManager.checkRequirements()
  }

  onShellChanged: syncSettings()
}
