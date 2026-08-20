import QtQuick
import Quickshell
import Quickshell.Io

import "Api.js" as Api

Item {
  id: root

  visible: false
  width: 0
  height: 0

  property bool wanted: false
  readonly property var activeSocket: socketLoader.item
  readonly property bool connected: !!(activeSocket && activeSocket.connected)
  property string lifecycle: ""
  property bool sessionConnected: false
  property var lastState: null
  property int nextId: 1
  property var pending: ({})
  property int reconnectAttempt: 0

  readonly property string socketPath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return String(runtime || "/tmp") + "/omarchy-ytmusic/backend.sock"
  }
  readonly property bool ready: connected
    && (lifecycle === "ready" || lifecycle === "")

  signal stateReceived(var state)

  function resetPending(reason) {
    var waiters = pending
    pending = ({})
    var message = String(reason || "Playback on this computer is unavailable")
    for (var id in waiters) {
      var callback = waiters[id]
      if (typeof callback === "function") callback(false, null, message)
    }
  }

  function sendCommand(name, fields, callback) {
    var socket = activeSocket
    if (!socket || !socket.connected) {
      if (typeof callback === "function")
        callback(false, null, "YouTube Music is not ready")
      return 0
    }
    var id = nextId++
    var payload = { v: 1, id: id, command: String(name || "") }
    Api.assign(payload, fields || {})
    var nextPending = ({})
    for (var existing in pending) nextPending[existing] = pending[existing]
    nextPending[String(id)] = typeof callback === "function" ? callback : null
    pending = nextPending
    socket.write(JSON.stringify(payload) + "\n")
    socket.flush()
    return id
  }

  function handleLine(line) {
    var message = Api.parseJson(line, null)
    if (!message || typeof message !== "object") return
    if (message.type === "event" && message.state) {
      lastState = message.state
      lifecycle = String(message.state.lifecycle || "")
      sessionConnected = message.state.signed_in === true
      stateReceived(message.state)
      return
    }
    if (message.type !== "response") return
    var id = String(message.id || "")
    var callback = pending[id]
    if (callback === undefined) return
    var nextPending = ({})
    for (var key in pending) if (key !== id) nextPending[key] = pending[key]
    pending = nextPending
    if (typeof callback !== "function") return
    if (message.ok === true) {
      var result = message.result || ({})
      if (result && typeof result === "object" && result.signed_in !== undefined) {
        lastState = result
        lifecycle = String(result.lifecycle || lifecycle)
        sessionConnected = result.signed_in === true
      }
      callback(true, result, "")
    } else {
      var error = message.error || {}
      callback(false, null, Api.redact(String(error.message
        || "YouTube Music command failed")))
    }
  }

  onWantedChanged: {
    if (wanted) return
    reconnectTimer.stop()
    socketLoader.active = false
    lifecycle = ""
    sessionConnected = false
    lastState = null
    reconnectAttempt = 0
    resetPending("YouTube Music stopped")
  }

  onConnectedChanged: if (connected) reconnectAttempt = 0

  Component {
    id: socketComponent
    Socket {
      path: root.socketPath
      connected: true
      parser: SplitParser {
        splitMarker: "\n"
        onRead: function(line) { root.handleLine(line) }
      }
      onConnectionStateChanged: {
        if (connected) root.sendCommand("hello", null, null)
        else root.lifecycle = ""
      }
    }
  }

  Loader {
    id: socketLoader
    active: false
    sourceComponent: socketComponent
  }

  // A failed connect leaves Quickshell's Socket holding a dead QLocalSocket.
  // Setting connected=true again is a no-op, so each retry creates a new Socket.
  Timer {
    id: reconnectTimer
    interval: Math.min(1500, 180 + root.reconnectAttempt * 120)
    repeat: true
    triggeredOnStart: true
    running: root.wanted && !root.connected
    onTriggered: {
      root.reconnectAttempt = Math.min(12, root.reconnectAttempt + 1)
      socketLoader.active = false
      socketLoader.active = true
    }
  }
}
