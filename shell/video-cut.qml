import Quickshell
import QtQuick
import qs.Commons

ShellRoot {
  id: standaloneRoot

  readonly property string quattroPath: Util.quattroPath

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
