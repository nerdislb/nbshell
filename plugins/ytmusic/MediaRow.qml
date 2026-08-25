import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

BorderSurface {
  id: root

  required property var itemData
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool selected: false
  property bool playing: false
  property real areaRadius: Math.max(Style.space(14), Style.cornerRadius)
  property bool showPlay: true
  property bool showQueue: false
  property bool showPlaylist: true
  property bool showSave: false
  property bool saved: false
  property bool browseOnActivate: false
  property bool reorderEnabled: false
  property bool trackDragEnabled: false
  property bool reorderDragging: false
  property bool trackDragging: false
  property int reorderDropIndicator: 0
  property bool hovered: hoverHandler.hovered
  property bool actionsExpanded: false

  readonly property bool durationActionVisible: itemData
    && itemData.kind === "item" && Number(itemData.durationMs) > 0
  readonly property bool saveActionVisible: showSave && itemData
    && itemData.type === "track" && !!itemData.videoId
  readonly property bool playlistActionVisible: showPlaylist && itemData
    && itemData.type === "track"
  readonly property bool queueActionVisible: showQueue && itemData
    && itemData.type === "track"
  readonly property bool playActionVisible: showPlay && itemData
    && itemData.type !== ""
  readonly property int fullActionCount: (durationActionVisible ? 1 : 0)
    + (saveActionVisible ? 1 : 0) + (playlistActionVisible ? 1 : 0)
    + (queueActionVisible ? 1 : 0) + (playActionVisible ? 1 : 0)
  readonly property real fullActionWidth:
    (durationActionVisible ? durationLabel.implicitWidth : 0)
    + (saveActionVisible ? saveButton.implicitWidth : 0)
    + (playlistActionVisible ? playlistButton.implicitWidth : 0)
    + (queueActionVisible ? queueButton.implicitWidth : 0)
    + (playActionVisible ? playButton.implicitWidth : 0)
    + Math.max(0, fullActionCount - 1) * Style.space(2)
  readonly property real titleWidthWithFullActions: Math.max(0,
    contentRow.width - artworkSurface.width - fullActionWidth
      - contentRow.spacing * 2)
  readonly property bool compactActions: Api.mediaRowShouldCompact(
    titleMetrics.advanceWidth, titleWidthWithFullActions, fullActionCount)

  signal activated(var item)
  signal openRequested(var item)
  signal queueRequested(var item)
  signal playlistRequested(var item)
  signal saveRequested(var item)
  signal artistRequested(var item)
  signal albumRequested(var item)
  signal contextRequested(var item, real sceneX, real sceneY)
  signal reorderDragStarted(real sceneY)
  signal reorderDragMoved(real sceneY)
  signal reorderDragFinished(real sceneY)
  signal reorderDragCanceled()
  signal trackDragStarted(real sceneY)
  signal trackDragMoved(real sceneY)
  signal trackDragFinished(real sceneY)
  signal trackDragCanceled()

  function triggerPrimary() {
    if (browseOnActivate) openRequested(itemData)
    else activated(itemData)
  }

  function triggerPlay() { activated(itemData) }

  onItemDataChanged: actionsExpanded = false
  onCompactActionsChanged: if (!compactActions) actionsExpanded = false

  width: parent ? parent.width : implicitWidth
  implicitWidth: Style.space(420)
  implicitHeight: Style.space(66)
  height: implicitHeight
  radius: root.areaRadius
  Accessible.role: Accessible.ListItem
  Accessible.name: root.itemData ? String(root.itemData.name || "Untitled") : "Untitled"
  Accessible.description: root.itemData ? String(root.itemData.subtitle || "") : ""
  Accessible.onPressAction: root.triggerPrimary()
  color: root.playing || reorderDragging
    ? Style.normalFillFor(foreground, accent)
    : (root.selected || reorderDropIndicator !== 0 || hovered
      ? Style.hoverFillFor(foreground, accent) : "transparent")
  borderSpec: Border.none()
  opacity: reorderDragging || trackDragging ? 0.55 : 1
  clip: true

  HoverHandler { id: hoverHandler }

  PanelToolTip {
    visible: titleHover.hovered && titleText.text !== ""
    text: titleText.text
  }

  TextMetrics {
    id: titleMetrics
    text: root.itemData ? String(root.itemData.name || "Untitled") : "Untitled"
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: root.selected
  }

  MouseArea {
    id: rowMouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: root.reorderEnabled || root.trackDragEnabled
    cursorShape: root.reorderEnabled || root.trackDragEnabled
      ? (dragGesture ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
      : Qt.PointingHandCursor

    property bool dragCandidate: false
    property bool dragGesture: false
    property bool dragUsesTrack: false
    property bool suppressActivation: false
    property real pressSceneY: 0

    function pointerSceneY(mouse) {
      return mapToItem(null, mouse.x, mouse.y).y
    }

    onPressed: function(mouse) {
      suppressActivation = false
      dragUsesTrack = mouse.button === Qt.LeftButton && root.trackDragEnabled
        && !root.reorderEnabled
      dragCandidate = mouse.button === Qt.LeftButton
        && (root.reorderEnabled || dragUsesTrack)
      dragGesture = false
      if (dragCandidate) pressSceneY = pointerSceneY(mouse)
    }

    onPositionChanged: function(mouse) {
      if (!dragCandidate || !pressed) return
      var sceneY = pointerSceneY(mouse)
      if (!dragGesture
          && Math.abs(sceneY - pressSceneY) >= Style.space(6)) {
        dragGesture = true
        suppressActivation = true
        if (dragUsesTrack) root.trackDragStarted(pressSceneY)
        else root.reorderDragStarted(pressSceneY)
      }
      if (dragGesture) {
        if (dragUsesTrack) root.trackDragMoved(sceneY)
        else root.reorderDragMoved(sceneY)
      }
    }

    onReleased: function(mouse) {
      if (dragGesture) {
        if (dragUsesTrack) root.trackDragFinished(pointerSceneY(mouse))
        else root.reorderDragFinished(pointerSceneY(mouse))
      }
      dragCandidate = false
      dragGesture = false
      dragUsesTrack = false
    }

    onCanceled: {
      if (dragGesture) {
        if (dragUsesTrack) root.trackDragCanceled()
        else root.reorderDragCanceled()
      }
      dragCandidate = false
      dragGesture = false
      dragUsesTrack = false
      suppressActivation = false
    }

    onClicked: function(mouse) {
      if (suppressActivation) {
        suppressActivation = false
        return
      }
      if (mouse.button === Qt.RightButton) {
        var scenePoint = root.mapToItem(null, mouse.x, mouse.y)
        root.contextRequested(root.itemData, scenePoint.x, scenePoint.y)
      } else {
        root.triggerPrimary()
      }
    }
  }

  Row {
    id: contentRow
    anchors.fill: parent
    anchors.margins: Style.space(6)
    spacing: Style.space(9)

    Artwork {
      id: artworkSurface
      width: parent.height
      height: width
      radius: root.areaRadius
      foreground: root.foreground
      accent: root.accent
      source: root.itemData && root.itemData.imageUrl ? root.itemData.imageUrl : ""
      sourceSize: 112
      altText: Api.artworkAltText(
        root.itemData ? root.itemData.name : "",
        root.itemData ? root.itemData.subtitle : "")
      placeholderText: !root.itemData ? "󰝚"
        : (root.itemData.type === "playlist" ? "󰲸"
        : (root.itemData.type === "artist" ? "󰠃"
        : (root.itemData.type === "album" ? "󰀥" : "󰝚")))
    }

    Column {
      width: Math.max(20, parent.width - artworkSurface.width - actionRow.width
        - parent.spacing * 2)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        id: titleText
        objectName: "media-row-title"
        width: parent.width
        text: root.itemData ? String(root.itemData.name || "Untitled") : "Untitled"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.selected
        elide: Text.ElideRight
        Accessible.role: Accessible.StaticText
        Accessible.name: text
        HoverHandler { id: titleHover }
      }

      MediaByline {
        width: parent.width
        itemData: root.itemData
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontPixelSize: Style.font.bodySmall
        onArtistRequested: function(item) { root.artistRequested(item) }
        onAlbumRequested: function(item) { root.albumRequested(item) }
        onContextRequested: function(item) { root.openRequested(item) }
      }
    }

    Row {
      id: actionRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        id: durationLabel
        objectName: "media-row-duration"
        visible: root.durationActionVisible
          && (!root.compactActions || root.actionsExpanded)
        anchors.verticalCenter: parent.verticalCenter
        text: Api.millisecondsToClock(root.itemData ? root.itemData.durationMs : 0)
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Accessible.name: "Duration " + text
      }

      Chicklet {
        id: saveButton
        objectName: "media-row-save"
        visible: root.saveActionVisible
          && (!root.compactActions || root.actionsExpanded)
        iconText: root.saved ? "󰋑" : "󰋕"
        foreground: root.foreground
        selected: root.saved
        tooltipText: Api.controlTooltip(root.saved ? "Unlike" : "Like this song", "L")
        chickletSize: Style.space(30)
        onClicked: root.saveRequested(root.itemData)
      }

      Chicklet {
        id: playlistButton
        objectName: "media-row-playlist"
        visible: root.playlistActionVisible
          && (!root.compactActions || root.actionsExpanded)
        iconText: "󱁐"
        foreground: root.foreground
        tooltipText: "Add to playlist"
        chickletSize: Style.space(30)
        onClicked: root.playlistRequested(root.itemData)
      }

      Chicklet {
        id: queueButton
        objectName: "media-row-queue"
        visible: root.queueActionVisible
          && (!root.compactActions || root.actionsExpanded)
        iconText: "󰐕"
        foreground: root.foreground
        tooltipText: Api.controlTooltip("Add to queue", "Q")
        chickletSize: Style.space(30)
        onClicked: root.queueRequested(root.itemData)
      }

      Chicklet {
        id: playButton
        objectName: "media-row-play"
        visible: root.playActionVisible
          && (!root.compactActions || root.actionsExpanded)
        iconText: "󰐊"
        foreground: root.foreground
        tooltipText: Api.controlTooltip("Play", "Enter")
        chickletSize: Style.space(30)
        onClicked: root.triggerPlay()
      }

      Chicklet {
        id: actionToggle
        objectName: "media-row-actions-toggle"
        visible: root.compactActions
        iconText: root.actionsExpanded ? "󰅖" : "󰇙"
        foreground: root.foreground
        tooltipText: root.actionsExpanded
          ? "Hide row actions" : "Show duration and actions"
        chickletSize: Style.space(30)
        onClicked: root.actionsExpanded = !root.actionsExpanded
      }
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(2, Style.space(2))
    y: root.reorderDropIndicator < 0 ? 0 : parent.height - height
    visible: root.reorderDropIndicator !== 0
    color: root.accent
    z: 5
  }
}
