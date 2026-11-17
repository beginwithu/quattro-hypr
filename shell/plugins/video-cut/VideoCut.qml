import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtMultimedia
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string quattroPath: Quickshell.env("QUATTRO_PATH")
  property var shell: null
  property var manifest: null
  property bool standalone: false

  property bool opened: false
  property string videoPath: ""
  property string videoUrl: ""
  property int durationMs: 0
  property int startMs: 0
  property int endMs: 0
  property bool muted: false
  property bool cutting: false
  property string statusText: ""
  property string errorText: ""

  readonly property int effectiveDurationMs: Math.max(durationMs, player.duration > 0 ? player.duration : 0)
  readonly property int trimLengthMs: Math.max(0, endMs - startMs)
  readonly property bool isPlaying: player.playbackState === MediaPlayer.PlayingState

  readonly property var targetScreen: {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    var fm = Hyprland.focusedMonitor
    if (fm) {
      for (var i = 0; i < screens.length; i++) {
        if (String(screens[i].name || "") === String(fm.name || "")) return screens[i]
      }
    }
    return screens[0]
  }

  function formatTime(ms) {
    var clamped = Math.max(0, Math.round(Number(ms || 0)))
    var totalTenths = Math.floor(clamped / 100)
    var tenths = totalTenths % 10
    var totalSeconds = Math.floor(totalTenths / 10)
    var seconds = totalSeconds % 60
    var minutes = Math.floor(totalSeconds / 60) % 60
    var hours = Math.floor(totalSeconds / 3600)
    var mm = (minutes < 10 ? "0" : "") + minutes
    var ss = (seconds < 10 ? "0" : "") + seconds
    if (hours > 0) {
      return hours + ":" + mm + ":" + ss + "." + tenths
    }
    return mm + ":" + ss + "." + tenths
  }

  function fileUrlForPath(p) {
    if (!p) return ""
    var parts = String(p).split("/")
    var encoded = []
    for (var i = 0; i < parts.length; i++) {
      encoded.push(encodeURIComponent(parts[i]))
    }
    return "file://" + encoded.join("/")
  }

  function baseName(p) {
    if (!p) return ""
    var idx = String(p).lastIndexOf("/")
    return idx >= 0 ? String(p).slice(idx + 1) : String(p)
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    var path = String(payload.path || payload.file || "").trim()
    var dur = Math.max(0, Math.round(Number(payload.durationMs || 0)))

    root.cutting = false
    root.statusText = ""
    root.errorText = ""
    root.videoPath = path
    root.durationMs = dur
    root.startMs = 0
    root.endMs = dur > 0 ? dur : 1000
    root.videoUrl = fileUrlForPath(path)
    root.opened = true

    player.stop()
    player.source = root.videoUrl
    player.play()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (!root.opened) return
    player.stop()
    player.source = ""
    root.opened = false
    root.cutting = false
    if (root.standalone) Qt.quit()
  }

  function dismiss() {
    if (!root.opened) return
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "quattro.video-cut")
    } else {
      close()
    }
  }

  function togglePlay() {
    if (root.cutting) return
    if (root.isPlaying) {
      player.pause()
    } else {
      if (player.position < root.startMs || player.position >= root.endMs - 50) {
        player.position = root.startMs
      }
      player.play()
    }
  }

  function seekTo(ms) {
    var dur = root.effectiveDurationMs
    if (dur <= 0) return
    var target = Math.max(0, Math.min(dur, Math.round(ms)))
    player.position = target
  }

  function setStartMs(ms) {
    var dur = root.effectiveDurationMs
    if (dur <= 0) return
    var maxStart = Math.max(0, root.endMs - 200)
    var next = Math.max(0, Math.min(maxStart, Math.round(ms)))
    root.startMs = next
    if (player.position < next) player.position = next
  }

  function setEndMs(ms) {
    var dur = root.effectiveDurationMs
    if (dur <= 0) return
    var minEnd = Math.min(dur, root.startMs + 200)
    var next = Math.max(minEnd, Math.min(dur, Math.round(ms)))
    root.endMs = next
    if (player.position > next) player.position = next
  }

  function runCut(replaceInPlace) {
    if (root.cutting || !root.videoPath || root.endMs <= root.startMs) return
    var isReplace = replaceInPlace === true || replaceInPlace === "true"
    player.pause()
    root.cutting = true
    root.errorText = ""
    root.statusText = isReplace ? "Trimming original video..." : "Saving trimmed copy..."

    var startSec = (root.startMs / 1000.0).toFixed(3)
    var durationSec = Math.max(0.1, (root.endMs - root.startMs) / 1000.0).toFixed(3)
    var inQ = Util.shellQuote(root.videoPath)
    var modeFlag = isReplace ? "replace" : "copy"

    var script = "set -euo pipefail\n"
      + "in_file=" + inQ + "\n"
      + "mode=" + Util.shellQuote(modeFlag) + "\n"
      + "dir=$(dirname -- \"$in_file\")\n"
      + "base=$(basename -- \"$in_file\")\n"
      + "stem=\"${base%.*}\"\n"
      + "ext=\"${base##*.}\"\n"
      + "if [[ \"$stem\" == \"$base\" ]]; then ext=\"mp4\"; fi\n"
      + "if [[ \"$mode\" == \"replace\" ]]; then\n"
      + "  tmp_out=\"$dir/.${stem}.quattro-video-cut-$$.${ext}\"\n"
      + "  final_out=\"$in_file\"\n"
      + "else\n"
      + "  final_out=\"$dir/${stem}-cut.${ext}\"\n"
      + "  idx=2\n"
      + "  while [[ -e \"$final_out\" ]]; do\n"
      + "    final_out=\"$dir/${stem}-cut-${idx}.${ext}\"\n"
      + "    idx=$((idx + 1))\n"
      + "  done\n"
      + "  tmp_out=\"$final_out\"\n"
      + "fi\n"
      + "ffmpeg -y -ss " + Util.shellQuote(startSec)
      + " -i \"$in_file\" -t " + Util.shellQuote(durationSec)
      + " -c:v libx264 -preset veryfast -crf 18 -c:a aac -movflags +faststart \"$tmp_out\" -loglevel error\n"
      + "if [[ \"$mode\" == \"replace\" ]]; then\n"
      + "  mv -f \"$tmp_out\" \"$final_out\"\n"
      + "fi\n"
      + "quattro-notification-send \"Video Cut Saved\" \"$(basename -- \"$final_out\")\" -t 8000 --action \"$(quattro-i18n capture.recordingOpen 2>/dev/null || echo Open)\" mpv -- --with \"$final_out\" >/dev/null 2>&1 || true\n"

    cutProc.command = ["bash", "-c", script]
    cutProc.running = true
  }

  MediaPlayer {
    id: player
    audioOutput: AudioOutput {
      muted: root.muted
      volume: 1.0
    }
    videoOutput: videoSurface
    onDurationChanged: {
      if (player.duration > 0 && (root.durationMs <= 0 || root.endMs > player.duration)) {
        root.durationMs = player.duration
        if (root.endMs <= 1000 || root.endMs > player.duration) {
          root.endMs = player.duration
        }
      }
    }
    onPositionChanged: {
      if (root.isPlaying && root.endMs > root.startMs && player.position >= root.endMs) {
        player.position = root.startMs
      }
    }
  }

  Process {
    id: cutProc
    onExited: function(exitCode) {
      root.cutting = false
      if (exitCode === 0) {
        root.dismiss()
      } else {
        root.statusText = ""
        root.errorText = "Failed to trim video with ffmpeg."
      }
    }
  }

  PanelWindow {
    id: window
    screen: root.targetScreen
    visible: root.opened
    color: "transparent"

    anchors {
      top: true
      left: true
      right: true
      bottom: true
    }

    WlrLayershell.namespace: "quattro-video-cut"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Util.alpha("#000000", 0.56)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: if (!root.cutting) root.dismiss()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(860), parent.width - Style.space(48))
      height: Math.min(Style.space(580), parent.height - Style.space(48))
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Commons.Color.popups.border, Commons.Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      FocusScope {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.cutting) {
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Space) {
            root.togglePlay()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            player.pause()
            root.seekTo(player.position - (event.modifiers & Qt.ShiftModifier ? 100 : 1000))
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            player.pause()
            root.seekTo(player.position + (event.modifiers & Qt.ShiftModifier ? 100 : 1000))
            event.accepted = true
          } else if (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_I) {
            root.setStartMs(player.position)
            event.accepted = true
          } else if (event.key === Qt.Key_BracketRight || event.key === Qt.Key_O) {
            root.setEndMs(player.position)
            event.accepted = true
          } else if (event.key === Qt.Key_M) {
            root.muted = !root.muted
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.runCut(false)
            event.accepted = true
          }
        }

        Column {
          id: contentCol
          anchors.fill: parent
          spacing: Style.spacing.md

          // Header
          Item {
            width: parent.width
            height: Style.space(28)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Text {
                textFormat: Text.PlainText
                text: "ContentCut"
                visible: false
              }

              Text {
                textFormat: Text.PlainText
                text: "Cut Video — " + root.baseName(root.videoPath)
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.weight: Font.DemiBold
                color: Commons.Color.foreground
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, contentCol.width - Style.space(180))
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Clip length: " + root.formatTime(root.trimLengthMs)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              color: Commons.Color.accent
            }
          }

          // Video Preview Box
          Rectangle {
            id: previewBox
            width: parent.width
            height: Math.max(Style.space(220), contentCol.height - Style.space(188))
            radius: Style.cornerRadius
            color: Util.alpha("#000000", 0.65)
            border.width: Style.spacing.hairline
            border.color: Util.alpha(Commons.Color.border, 0.45)
            clip: true

            VideoOutput {
              id: videoSurface
              anchors.fill: parent
              anchors.margins: Style.space(4)
              fillMode: VideoOutput.PreserveAspectFit
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.togglePlay()
            }

            Rectangle {
              visible: !root.isPlaying && !root.cutting
              anchors.centerIn: parent
              width: Style.space(52)
              height: Style.space(52)
              radius: Style.space(26)
              color: Util.alpha("#000000", 0.62)
              border.width: Style.spacing.hairline
              border.color: Util.alpha(Commons.Color.foreground, 0.35)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: ""
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                color: Commons.Color.foreground
              }
            }
          }

          // Time readout + quick set buttons
          Item {
            width: parent.width
            height: Style.space(26)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                text: "Start: " + root.formatTime(root.startMs)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Commons.Color.muted
              }

              Text {
                textFormat: Text.PlainText
                text: "Playhead: " + root.formatTime(player.position)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Commons.Color.foreground
              }

              Text {
                textFormat: Text.PlainText
                text: "End: " + root.formatTime(root.endMs)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Commons.Color.muted
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              Rectangle {
                height: Style.space(24)
                width: setStartTxt.implicitWidth + Style.space(16)
                radius: Style.cornerRadius
                color: setStartArea.containsMouse
                  ? Util.alpha(Commons.Color.foreground, 0.14)
                  : Util.alpha(Commons.Color.foreground, 0.07)
                border.width: Style.spacing.hairline
                border.color: Util.alpha(Commons.Color.border, 0.45)

                Text {
                  id: setStartTxt
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "[ Set Start"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Commons.Color.foreground
                }

                MouseArea {
                  id: setStartArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setStartMs(player.position)
                }
              }

              Rectangle {
                height: Style.space(24)
                width: setEndTxt.implicitWidth + Style.space(16)
                radius: Style.cornerRadius
                color: setEndArea.containsMouse
                  ? Util.alpha(Commons.Color.foreground, 0.14)
                  : Util.alpha(Commons.Color.foreground, 0.07)
                border.width: Style.spacing.hairline
                border.color: Util.alpha(Commons.Color.border, 0.45)

                Text {
                  id: setEndTxt
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "Set End ]"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Commons.Color.foreground
                }

                MouseArea {
                  id: setEndArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setEndMs(player.position)
                }
              }
            }
          }

          // Interactive Trim Timeline
          Item {
            id: timelineContainer
            width: parent.width
            height: Style.space(36)

            readonly property real trackWidth: Math.max(1, width - Style.space(20))
            readonly property real trackX: Style.space(10)
            readonly property real startRatio: root.effectiveDurationMs > 0
              ? Math.max(0, Math.min(1, root.startMs / root.effectiveDurationMs))
              : 0
            readonly property real endRatio: root.effectiveDurationMs > 0
              ? Math.max(0, Math.min(1, root.endMs / root.effectiveDurationMs))
              : 1
            readonly property real posRatio: root.effectiveDurationMs > 0
              ? Math.max(0, Math.min(1, player.position / root.effectiveDurationMs))
              : 0

            property string dragTarget: ""

            function msFromMouseX(mx) {
              var ratio = Math.max(0, Math.min(1, (mx - trackX) / trackWidth))
              return Math.round(ratio * root.effectiveDurationMs)
            }

            // Full track background
            Rectangle {
              x: timelineContainer.trackX
              anchors.verticalCenter: parent.verticalCenter
              width: timelineContainer.trackWidth
              height: Style.space(10)
              radius: Style.space(5)
              color: Util.alpha(Commons.Color.foreground, 0.12)
            }

            // Active trim segment
            Rectangle {
              x: timelineContainer.trackX + timelineContainer.startRatio * timelineContainer.trackWidth
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(Style.space(4), (timelineContainer.endRatio - timelineContainer.startRatio) * timelineContainer.trackWidth)
              height: Style.space(10)
              radius: Style.space(5)
              color: Util.alpha(Commons.Color.accent, 0.55)
            }

            // Start handle
            Rectangle {
              id: startHandle
              width: Style.space(12)
              height: Style.space(26)
              radius: Style.cornerRadius
              x: timelineContainer.trackX + timelineContainer.startRatio * timelineContainer.trackWidth - width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Commons.Color.accent
              border.width: Style.spacing.hairline
              border.color: Commons.Color.background
            }

            // End handle
            Rectangle {
              id: endHandle
              width: Style.space(12)
              height: Style.space(26)
              radius: Style.cornerRadius
              x: timelineContainer.trackX + timelineContainer.endRatio * timelineContainer.trackWidth - width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Commons.Color.accent
              border.width: Style.spacing.hairline
              border.color: Commons.Color.background
            }

            // Playhead line
            Rectangle {
              width: Style.space(3)
              height: Style.space(32)
              radius: Style.space(1.5)
              x: timelineContainer.trackX + timelineContainer.posRatio * timelineContainer.trackWidth - width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Commons.Color.foreground
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPressed: function(mouse) {
                if (root.cutting) return
                var startX = startHandle.x + startHandle.width / 2
                var endX = endHandle.x + endHandle.width / 2
                var dStart = Math.abs(mouse.x - startX)
                var dEnd = Math.abs(mouse.x - endX)
                var threshold = Style.space(14)
                player.pause()
                if (dStart <= threshold && dStart <= dEnd) {
                  timelineContainer.dragTarget = "start"
                  var msS = timelineContainer.msFromMouseX(mouse.x)
                  root.setStartMs(msS)
                  root.seekTo(root.startMs)
                } else if (dEnd <= threshold) {
                  timelineContainer.dragTarget = "end"
                  var msE = timelineContainer.msFromMouseX(mouse.x)
                  root.setEndMs(msE)
                  root.seekTo(root.endMs)
                } else {
                  timelineContainer.dragTarget = "playhead"
                  root.seekTo(timelineContainer.msFromMouseX(mouse.x))
                }
              }
              onPositionChanged: function(mouse) {
                if (!pressed || root.cutting) return
                var ms = timelineContainer.msFromMouseX(mouse.x)
                if (timelineContainer.dragTarget === "start") {
                  root.setStartMs(ms)
                  root.seekTo(root.startMs)
                } else if (timelineContainer.dragTarget === "end") {
                  root.setEndMs(ms)
                  root.seekTo(root.endMs)
                } else {
                  root.seekTo(ms)
                }
              }
              onReleased: {
                timelineContainer.dragTarget = ""
              }
            }
          }

          // Footer controls
          Item {
            width: parent.width
            height: Style.space(36)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Rectangle {
                width: Style.space(76)
                height: Style.space(32)
                radius: Style.cornerRadius
                color: playBtnArea.containsMouse
                  ? Util.alpha(Commons.Color.foreground, 0.14)
                  : Util.alpha(Commons.Color.foreground, 0.08)
                border.width: Style.spacing.hairline
                border.color: Util.alpha(Commons.Color.border, 0.5)

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.isPlaying ? " Pause" : " Play"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  color: Commons.Color.foreground
                }

                MouseArea {
                  id: playBtnArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.togglePlay()
                }
              }

              Rectangle {
                width: Style.space(36)
                height: Style.space(32)
                radius: Style.cornerRadius
                color: muteBtnArea.containsMouse
                  ? Util.alpha(Commons.Color.foreground, 0.14)
                  : Util.alpha(Commons.Color.foreground, 0.08)
                border.width: Style.spacing.hairline
                border.color: Util.alpha(Commons.Color.border, 0.5)

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.muted ? "󰝟" : "󰕾"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Commons.Color.foreground
                }

                MouseArea {
                  id: muteBtnArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.muted = !root.muted
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.errorText !== "" ? root.errorText : root.statusText
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: root.errorText !== "" ? Commons.Color.urgent : Commons.Color.muted
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Rectangle {
                width: Style.space(80)
                height: Style.space(32)
                radius: Style.cornerRadius
                opacity: root.cutting ? 0.5 : 1.0
                color: cancelBtnArea.containsMouse
                  ? Util.alpha(Commons.Color.foreground, 0.12)
                  : Util.alpha(Commons.Color.foreground, 0.06)
                border.width: Style.spacing.hairline
                border.color: Util.alpha(Commons.Color.border, 0.5)

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "Cancel"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  color: Commons.Color.foreground
                }

                MouseArea {
                  id: cancelBtnArea
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !root.cutting
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.dismiss()
                }
              }

              Rectangle {
                width: Style.space(128)
                height: Style.space(32)
                radius: Style.cornerRadius
                opacity: root.cutting ? 0.5 : 1.0
                color: replaceBtnArea.containsMouse
                  ? Util.alpha(Commons.Color.foreground, 0.16)
                  : Util.alpha(Commons.Color.foreground, 0.09)
                border.width: Style.spacing.hairline
                border.color: Util.alpha(Commons.Color.border, 0.65)

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "Replace Original"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.Medium
                  color: Commons.Color.foreground
                }

                MouseArea {
                  id: replaceBtnArea
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !root.cutting
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.runCut(true)
                }
              }

              Rectangle {
                width: Style.space(104)
                height: Style.space(32)
                radius: Style.cornerRadius
                opacity: root.cutting ? 0.5 : 1.0
                color: saveCopyArea.containsMouse
                  ? Qt.lighter(Commons.Color.accent, 1.12)
                  : Commons.Color.accent

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "Save Copy"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.DemiBold
                  color: Commons.Color.background
                }

                MouseArea {
                  id: saveCopyArea
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !root.cutting
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.runCut(false)
                }
              }
            }
          }
        }
      }
    }
  }
}
