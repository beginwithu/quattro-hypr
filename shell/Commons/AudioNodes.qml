pragma Singleton
import QtQuick
import Quickshell
import "AudioNodesModel.js" as Model

// Which PipeWire nodes the audio panel and the microphone widget leave out:
// the shell's own level meters and any configured hidden/replaced nodes.
Singleton {
  id: root

  property var hints: ({ hidden: [], replaced: [] })

  function platformHides(name, nodeNames) {
    return Model.platformHidesNode(name, hints, nodeNames)
  }

  function isShellLevelMeter(name) {
    return Model.isShellLevelMeter(name)
  }
}
