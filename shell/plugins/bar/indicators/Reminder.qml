import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property int reminderCount: 0
  property string tooltip: "Set Reminder"

  active: reminderCount > 0
  activeText: "󰢌"
  inactiveText: "󰢌"
  activeTooltipText: tooltip
  inactiveTooltipText: tooltip

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function update(raw) {
    var data = extractData(raw)
    reminderCount = Number(data.count || 0)
    tooltip = String(data.tooltip || "Set Reminder")
  }

  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: statusProc
    command: ["quattro-reminder", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.reminderCount = 0
        root.tooltip = "Set Reminder"
      }
    }
  }

  onPressed: function() {
    if (!root.bar) return
    root.bar.run(root.reminderCount > 0
      ? "quattro-launch-floating-terminal-with-presentation quattro-reminder manage"
      : "quattro-launch-floating-terminal-with-presentation quattro-reminder")
  }
}
