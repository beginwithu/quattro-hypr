import Quickshell
import QtQuick
import qs.Commons

ShellRoot {
  id: standaloneRoot

  readonly property string quattroPath: Quickshell.env("QUATTRO_PATH")

  Loader {
    id: videoCutLoader
    source: Qt.resolvedUrl("plugins/video-cut/VideoCut.qml")
    onLoaded: {
      item.quattroPath = standaloneRoot.quattroPath
      item.standalone = true
      item.open(Quickshell.env("QUATTRO_VIDEO_CUT_PAYLOAD") || "{}")
    }
  }
}
