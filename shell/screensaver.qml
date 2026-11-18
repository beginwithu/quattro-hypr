import Quickshell
import QtQuick
import qs.Commons

ShellRoot {
  id: standaloneRoot

  readonly property string quattroPath: Util.quattroPath

  Loader {
    id: screensaverLoader
    source: Qt.resolvedUrl("plugins/screensaver/Screensaver.qml")
    onLoaded: {
      item.quattroPath = standaloneRoot.quattroPath
      item.standalone = true
      item.open("{}")
    }
  }
}
