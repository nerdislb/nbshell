import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

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
  readonly property string pluginDir: {
    var root = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    var sub = manifest && manifest.pluginRoot ? String(manifest.pluginRoot) : ""
    if (!root) return ""
    if (!sub || sub.indexOf("..") >= 0 || sub.charAt(0) === "/") return root
    return root + "/" + sub
  }

  readonly property var defaultSettingValues: ({
    idleShutdownMinutes: 15,
    showMiniPlayer: "On",
    shortcutPlayer: "Full player",
    audioQuality: "320 kbps",
    searchHistory: "[]",
    sessionState: "{}",
    eqPreset: "Flat",
    eqBands: "[0,0,0,0,0,0,0,0,0,0]"
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
  property int backendRecoveries: 0
  property bool loginStalled: false
  readonly property bool waitingOnBackend: uiVisible
    && daemonManager.playbackReady && !backendClient.ready
    && !daemonManager.setupBusy
  onWaitingOnBackendChanged: if (!waitingOnBackend) loginStalled = false
  readonly property bool loginBusy: daemonManager.setupBusy || daemonManager.busy
    || authBusy || !daemonManager.requirementsChecked
    || (waitingOnBackend && !loginStalled)
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
  // True while the backend waits on yt-dlp. The first resolve against a new
  // YouTube player build is slow, so the UI says so instead of looking stuck.
  readonly property bool resolving: backendState && backendState.resolving === true
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
  readonly property real volume: Api.unitVolume(backendState
    ? backendState.volume : undefined)
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
  readonly property int homeShelfCount: Array.isArray(homeShelves) ? homeShelves.length : 0
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
  signal signInRequested(string reason)
  signal lyricsPluginPromptRequested(string surface, string availability)
  signal lyricsPluginOpened(string surface)

  function loginProgressText() {
    if (daemonManager.setupBusy) return "Installing playback"
    if (!daemonManager.playbackReady) return "Preparing YouTube Music"
    if (daemonManager.busy) return "Starting playback"
    if (loginStalled) return "Could not connect"
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
      root.pushSavedEq()
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
    next.eqPreset = Api.eqPresetName(next.eqPreset)
    next.eqBands = Api.eqBandsText(next.eqBands)
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
    var text = Api.redact(String(reason || "YouTube Music operation failed"))
    lastError = Api.isSignInError(text) ? Api.signInErrorMessage(text) : text
    statusMessage = ""
    operationFailed(lastError)
    if (Api.isSignInError(lastError)) signInRequested(lastError)
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
    // A new resolve is under way, so a previous failure is no longer current.
    else if (state.resolving === true) lastError = ""
    if (Array.isArray(state.play_history))
      history = Api.mergeHistory(state.play_history, history)
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

  function markDisconnected() {
    homeLoading = false
    searchLoading = false
    libraryLoading = false
    playlistsLoading = false
    detailLoading = false
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
        // Catalog payloads (home, history, like) must not replace playback state.
        // Doing that wipes the current track and can leave Home empty.
        if (Api.isPlaybackState(result)) root.applyBackendState(result)
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
      backendClient.wanted = true
      ensureBackend()
      if (daemonManager.playbackReady) daemonManager.start()
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

  function reorderQueue(sourceIndex, destinationIndex) {
    command("reorder_queue", {
      source_index: Math.max(0, Math.floor(Number(sourceIndex) || 0)),
      destination_index: Math.max(0, Math.floor(Number(destinationIndex) || 0))
    })
  }

  readonly property var eqBands: backendState && backendState.eq
    && Array.isArray(backendState.eq.bands) && backendState.eq.bands.length
    ? backendState.eq.bands : Api.eqBandsList(settings.eqBands)
  readonly property string eqPreset: backendState && backendState.eq
    ? Api.eqPresetName(backendState.eq.preset) : Api.eqPresetName(settings.eqPreset)
  readonly property var eqLabels: backendState && backendState.eq
    ? (backendState.eq.labels || []) : ["70", "180", "320", "600", "1k", "3k", "6k", "12k", "14k", "16k"]
  property var pendingEqPersist: null

  function pushSavedEq() {
    if (!backendClient.ready) return
    backendClient.sendCommand("restore_eq", {
      preset: Api.eqPresetName(settings.eqPreset),
      bands: Api.eqBandsList(settings.eqBands)
    })
  }

  function persistEqFromSnapshot(snapshot) {
    if (!snapshot || typeof snapshot !== "object") return
    pendingEqPersist = {
      eqPreset: Api.eqPresetName(snapshot.preset),
      eqBands: Api.eqBandsText(snapshot.bands)
    }
    eqPersistTimer.restart()
  }

  function setEqBand(index, gain) {
    command("set_eq_band", {
      index: Math.max(0, Math.min(9, Math.floor(Number(index) || 0))),
      gain: Math.max(-12, Math.min(12, Number(gain) || 0))
    }, "", function(ok, result) {
      if (ok) root.persistEqFromSnapshot(result)
    })
  }

  function setEqPreset(name) {
    command("set_eq_preset", { name: String(name || "Flat") }, "EQ: " + name,
      function(ok, result) {
        if (ok) root.persistEqFromSnapshot(result)
      })
  }

  function cycleEqPreset() {
    command("cycle_eq_preset", {}, "", function(ok, result) {
      if (ok) root.persistEqFromSnapshot(result)
    })
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
    if (!accountConnected) {
      fail("Sign in to like songs")
      login()
      return
    }
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
      searchLoading = false
      searchResults = []
      searchSections = []
      return
    }
    searchLoading = true
    rememberSearch(term)
    // Do not go through command(): that applies the catalog payload as
    // playback state. Songs-only keeps the response small enough for QML.
    ensureBackend(function(ok) {
      if (!ok || !backendClient.ready) {
        root.searchLoading = false
        root.fail(root.lastError || "YouTube Music is not ready")
        return
      }
      backendClient.sendCommand("search", {
        query: term,
        filter: "songs",
        limit: 16
      }, function(succeeded, result, error) {
        if (term !== root.searchQuery) return
        root.searchLoading = false
        if (!succeeded) {
          root.searchResults = []
          root.searchSections = []
          root.fail(error)
          return
        }
        var items = result && result.items ? result.items : []
        root.searchResults = items
        root.searchSections = result && result.sections ? result.sections : []
        root.succeed(items.length ? (items.length + " songs") : "No matching songs")
      })
    })
  }

  function clearSearch() {
    searchQuery = ""
    searchResults = []
    searchSections = []
  }

  function cancelSearch() {}

  function homeShelfAt(index) {
    var rows = homeShelves || []
    var i = Math.floor(Number(index) || 0)
    if (i < 0 || i >= rows.length) return null
    return rows[i]
  }

  function openView(view, force) {
    if (view === "home") loadHome(!!force || homeShelfCount === 0, !!force)
    else if (view === "history") loadHistory()
    else if (view === "library") loadLibrary(libraryType, false, force)
    else if (view === "playlists") loadPlaylists()
    else if (view === "search" && searchQuery) search(searchQuery)
    else if (view === "queue") {}
  }

  function loadHistory() {
    command("browse", { view: "history" }, "", function(ok, result) {
      if (ok && result) root.history = result.items || root.history
    })
  }

  function currentTrackUrl() {
    return Api.trackShareUrl(currentTrackItem) || Api.watchUrl(currentTrackId)
  }

  function copyTrackLink(item) {
    var url = Api.trackShareUrl(item) || currentTrackUrl()
    if (!url) {
      fail("Nothing to share")
      return
    }
    Quickshell.execDetached(["wl-copy", "--", url])
    succeed("Copied link")
  }

  function refreshView(view) {
    if (view === "home") loadHome(true, true)
    else openView(view, true)
  }

  function loadHome(force, bypassCache) {
    if (homeLoading && !force) return
    homeLoading = true
    command("browse", { view: "home", force: !!bypassCache }, "", function(ok, result) {
      root.homeLoading = false
      if (!ok || !result) {
        if (force) root.homeShelves = []
        return
      }
      root.homeShelves = Api.arrayValues(result.home)
    })
    command("browse", { view: "history" }, "", function(ok, result) {
      if (ok && result) root.history = result.items || []
    })
    if (accountConnected) {
      command("browse", { view: "liked" }, "", function(ok, result) {
        if (ok && result) root.liked = result.items || []
      })
      loadPlaylists()
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
    // `id` belongs to BackendClient's request correlation. Keep media IDs in
    // their own field or the response callback can never be matched.
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
    lyricsPluginError = "Lyrics are an optional external plugin and are not installed by nbshell."
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
      || "The lyrics extension is installed, but its window could not be opened.")
    lyricsPluginPromptRequested(lyricsPluginRequestSurface, lyricsPluginAvailability)
  }

  BackendClient {
    id: backendClient
    wanted: daemonManager.running || root.uiVisible
    onStateReceived: function(state) { root.applyBackendState(state) }
    onConnectedChanged: {
      if (connected) return
      root.markDisconnected()
      if (root.uiVisible) daemonManager.start()
    }
    onReadyChanged: {
      if (ready) {
        root.flushReadyWaiters(true)
        if (root.lastError === "YouTube Music is not ready"
            || root.lastError === "Installing playback on this computer…")
          root.succeed("")
        sendCommand("set_idle_minutes", { minutes: root.idleShutdownMinutes })
        sendCommand("set_quality", { kbps: root.bitrateKbps })
        root.pushSavedEq()
        root.backendRecoveries = 0
        root.loginStalled = false
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
    onRestarted: {
      backendClient.wanted = true
      daemonManager.refreshStatus()
    }
    onRestartFailed: function(reason) {
      root.fail(reason)
    }
    onSetupSucceeded: start()
  }

  Timer {
    id: backendRecoverTimer
    interval: 3500
    running: root.waitingOnBackend && root.backendRecoveries < 2
      && !daemonManager.busy
    onTriggered: {
      root.backendRecoveries += 1
      daemonManager.restart()
    }
  }

  Timer {
    id: loginStallTimer
    interval: 12000
    running: root.waitingOnBackend
    onTriggered: {
      root.loginStalled = true
      if (!root.lastError)
        root.fail("Playback did not connect. Try Use Chromium session again.")
    }
  }

  Timer {
    id: eqPersistTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (!root.pendingEqPersist) return
      var next = root.pendingEqPersist
      root.pendingEqPersist = null
      if (Api.eqPresetName(root.settings.eqPreset) === next.eqPreset
          && String(root.settings.eqBands) === String(next.eqBands))
        return
      root.persistSettings(next)
    }
  }

  Timer {
    id: readyWaitTimer
    interval: 200
    repeat: true
    onTriggered: {
      root.readyWaitTicks++
      if (backendClient.ready) {
        root.flushReadyWaiters(true)
      } else if (root.readyWaitTicks >= 150) {
        root.fail("YouTube Music is not ready")
        root.flushReadyWaiters(false)
      }
    }
  }

  Timer {
    interval: 2000
    running: root.uiVisible && !backendClient.ready && daemonManager.playbackReady
    repeat: true
    onTriggered: daemonManager.start()
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
          || "The lyrics extension could not be enabled.")
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
