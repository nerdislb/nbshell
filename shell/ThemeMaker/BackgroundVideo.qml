import QtQuick
import QtMultimedia

Item {
    id: root
    property url source
    signal failed(string message)
    MediaPlayer {
        id: player
        source: root.source
        loops: MediaPlayer.Infinite
        autoPlay: true
        videoOutput: video
        // Deliberately no AudioOutput: background previews are silent.
        onErrorOccurred: (error,message) => root.failed(message)
    }
    VideoOutput { id: video; anchors.fill:parent;fillMode:VideoOutput.PreserveAspectCrop }
    Component.onDestruction:player.stop()
}
