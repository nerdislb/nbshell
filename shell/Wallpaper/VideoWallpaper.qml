import QtQuick
import QtMultimedia

Item {
    id: root
    property url source
    signal failed(string message)
    // No AudioOutput: wallpaper media must never play sound.
    MediaPlayer {
        id: player
        source: root.source
        loops: MediaPlayer.Infinite
        videoOutput: output
        onErrorOccurred: (error, errorString) => root.failed(errorString)
        autoPlay: true
    }
    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: player.mediaStatus === MediaPlayer.BufferedMedia || player.playbackState === MediaPlayer.PlayingState
    }
    Component.onDestruction: player.stop()
}
