import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property string quattroPath: Util.quattroPath
  property var shell: null
  property var manifest: null
  property bool standalone: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string userArtPath: home + "/.config/quattro/branding/screensaver.txt"
  readonly property string fallbackArtPath: (quattroPath ? quattroPath : home + "/.local/share/quattro") + "/icon.txt"

  property bool opened: false
  property bool armed: false
  property string userArtText: ""
  property string fallbackArtText: ""
  readonly property string artText: {
    var u = trimArt(userArtText)
    if (u.length > 0) return u
    var f = trimArt(fallbackArtText)
    if (f.length > 0) return f
    return "QUATTRO"
  }
  readonly property var blockArt: parseBlockArt(artText)

  property var palette: [Commons.Color.accent, Commons.Color.foreground]
  property string clockTime: ""
  property string clockDate: ""

  function trimArt(raw) {
    var s = String(raw || "").replace(/\r\n?/g, "\n").replace(/^\n+|\n+$/g, "")
    return s
  }

  // Parse pure Unicode block-element art (e.g. icon.txt / logo.txt / block-mode
  // transcoded images) into merged grid rectangles so it can be painted as a
  // single solid vector path without font-glyph subpixel seams between blocks.
  function parseBlockArt(text) {
    var s = String(text || "")
    if (s.length === 0) return null
    var rawLines = s.split("\n")
    if (rawLines.length === 0) return null

    // 2x2 sub-pixel bitmask per character cell:
    // bit 0 = top-left, bit 1 = top-right, bit 2 = bottom-left, bit 3 = bottom-right
    var masks = {
      " ": 0,
      "▘": 1, "▝": 2, "▀": 3,
      "▖": 4, "▌": 5, "▞": 6, "▛": 7,
      "▗": 8, "▚": 9, "▐": 10, "▜": 11,
      "▄": 12, "▙": 13, "▟": 14, "█": 15
    }

    var lines = []
    var minIndent = -1
    var hasFilled = false
    var usesHalfCol = false

    for (var r = 0; r < rawLines.length; r++) {
      var line = rawLines[r].replace(/ +$/, "")
      lines.push(line)
      var firstNonSpace = -1
      for (var c = 0; c < line.length; c++) {
        var m = masks[line.charAt(c)]
        if (m === undefined) return null
        if (m !== 0) {
          hasFilled = true
          if (firstNonSpace < 0) firstNonSpace = c
          if (((m & 1) !== ((m >> 1) & 1)) || (((m >> 2) & 1) !== ((m >> 3) & 1))) {
            usesHalfCol = true
          }
        }
      }
      if (firstNonSpace >= 0 && (minIndent < 0 || firstNonSpace < minIndent)) {
        minIndent = firstNonSpace
      }
    }

    if (!hasFilled) return null
    if (minIndent < 0) minIndent = 0

    var maxCols = 0
    for (var i = 0; i < lines.length; i++) {
      var trimmed = lines[i].length > minIndent ? lines[i].slice(minIndent) : ""
      lines[i] = trimmed
      if (trimmed.length > maxCols) maxCols = trimmed.length
    }
    if (maxCols === 0) return null

    var colMult = usesHalfCol ? 2 : 1
    var gridW = maxCols * colMult
    var gridH = lines.length * 2

    var rects = []
    var prevRuns = ({})

    for (var lr = 0; lr < lines.length; lr++) {
      var rowStr = lines[lr]
      for (var half = 0; half < 2; half++) {
        var gy = lr * 2 + half
        var curRuns = ({})
        var runStart = -1

        for (var gx = 0; gx <= gridW; gx++) {
          var filled = false
          if (gx < gridW) {
            var chIdx = usesHalfCol ? (gx >> 1) : gx
            if (chIdx < rowStr.length) {
              var mask = masks[rowStr.charAt(chIdx)]
              if (usesHalfCol) {
                var bit = half * 2 + (gx & 1)
                filled = ((mask >> bit) & 1) !== 0
              } else {
                filled = half === 0 ? ((mask & 1) !== 0) : ((mask & 4) !== 0)
              }
            }
          }

          if (filled) {
            if (runStart < 0) runStart = gx
          } else if (runStart >= 0) {
            var runW = gx - runStart
            var key = runStart + ":" + runW
            var prev = prevRuns[key]
            if (prev) {
              prev.h += 1
              curRuns[key] = prev
            } else {
              var rect = { x: runStart, y: gy, w: runW, h: 1 }
              rects.push(rect)
              curRuns[key] = rect
            }
            runStart = -1
          }
        }
        prevRuns = curRuns
      }
    }

    return {
      cols: maxCols,
      rows: lines.length,
      gridW: gridW,
      gridH: gridH,
      colMult: colMult,
      rects: rects
    }
  }

  function parsePalette(raw) {
    var keys = ["accent", "blue", "cyan", "green", "magenta", "orange", "yellow", "red", "color4", "color6", "color2", "color5", "color3", "color1"]
    var found = ({})
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) found[m[1]] = m[2]
    }
    var out = []
    for (var k = 0; k < keys.length; k++) {
      var c = found[keys[k]]
      if (c && out.indexOf(c) === -1) out.push(c)
    }
    if (out.length === 0) out = [Commons.Color.accent, Commons.Color.foreground]
    palette = out
  }

  function updateClock() {
    var now = new Date()
    clockTime = Qt.formatDateTime(now, "HH:mm")
    clockDate = Qt.formatDateTime(now, "dddd, d MMMM")
  }

  function open(_payloadJson) {
    userArtFile.reload()
    colorsFile.reload()
    updateClock()
    armed = false
    opened = true
    armTimer.restart()
  }

  function close() {
    if (!opened) return
    armTimer.stop()
    armed = false
    opened = false
    if (root.standalone) Qt.quit()
  }

  function dismiss() {
    if (!opened) return
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "quattro.screensaver")
    } else {
      close()
    }
  }

  Timer {
    id: armTimer
    interval: 450
    repeat: false
    onTriggered: root.armed = true
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: root.updateClock()
  }

  FileView {
    id: userArtFile
    path: root.userArtPath
    watchChanges: true
    printErrors: false
    onLoaded: root.userArtText = text()
    onLoadFailed: root.userArtText = ""
    onFileChanged: reload()
  }

  FileView {
    id: fallbackArtFile
    path: root.fallbackArtPath
    watchChanges: false
    printErrors: false
    onLoaded: root.fallbackArtText = text()
    onLoadFailed: root.fallbackArtText = ""
  }

  FileView {
    id: colorsFile
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.parsePalette(text())
  }

  Component.onCompleted: updateClock()

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: win
      required property var modelData

      readonly property bool isFocusedScreen: Hyprland.focusedMonitor && String(Hyprland.focusedMonitor.name || "") === String(modelData.name || "")

      visible: root.opened
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "org.quattro.screensaver"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: isFocusedScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

      onVisibleChanged: {
        contentRevealed = visible
        if (visible) {
          pointerArea.hasInitialPos = false
          canvas.resetMotion()
          if (isFocusedScreen) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
      }

      property bool contentRevealed: false

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (root.armed || event.key === Qt.Key_Escape || event.key === Qt.Key_Space) {
            event.accepted = true
            root.dismiss()
          }
        }
      }

      Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Commons.Color.background
        opacity: win.contentRevealed ? 1.0 : 0.0
        Behavior on opacity {
          NumberAnimation { duration: Style.duration(350); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
        }

        // Subtle ambient radial accent glow behind the artwork
        Rectangle {
          width: Math.max(artContainer.width * 1.9, Style.space(420))
          height: width
          radius: width / 2
          x: artContainer.x + artContainer.width / 2 - width / 2
          y: artContainer.y + artContainer.height / 2 - height / 2
          color: artContainer.displayColor
          opacity: 0.06
        }

        // Drifting / bouncing ASCII branding container
        Item {
          id: canvas
          anchors.fill: parent

          property real posX: 0
          property real posY: 0
          property real velX: 110
          property real velY: 82
          property int colorIndex: 0
          property bool initialized: false
          readonly property real edgeMargin: Style.space(36)

          function resetMotion() {
            var maxX = Math.max(edgeMargin, width - artContainer.width - edgeMargin)
            var maxY = Math.max(edgeMargin, height - artContainer.height - edgeMargin)
            posX = Math.max(edgeMargin, Math.min(maxX, (width - artContainer.width) / 2))
            posY = Math.max(edgeMargin, Math.min(maxY, (height - artContainer.height) / 2))
            // Offset velocity slightly per screen index so multi-monitor setups diverge organically
            var dirSign = (Quickshell.screens.indexOf(win.modelData) % 2 === 0) ? 1 : -1
            velX = 115 * dirSign
            velY = 84
            colorIndex = 0
            initialized = width > 0 && height > 0
          }

          onWidthChanged: if (root.opened && !initialized) resetMotion()
          onHeightChanged: if (root.opened && !initialized) resetMotion()

          FrameAnimation {
            running: root.opened && !Style.reduceMotion && win.width > 0 && win.height > 0
            onTriggered: {
              if (!canvas.initialized) canvas.resetMotion()
              var dt = Math.min(0.05, frameTime)
              var minX = canvas.edgeMargin
              var minY = canvas.edgeMargin
              var maxX = Math.max(minX, canvas.width - artContainer.width - canvas.edgeMargin)
              var maxY = Math.max(minY, canvas.height - artContainer.height - canvas.edgeMargin)

              var nx = canvas.posX + canvas.velX * dt
              var ny = canvas.posY + canvas.velY * dt
              var bounced = false

              if (nx <= minX) {
                nx = minX
                canvas.velX = Math.abs(canvas.velX)
                bounced = true
              } else if (nx >= maxX) {
                nx = maxX
                canvas.velX = -Math.abs(canvas.velX)
                bounced = true
              }

              if (ny <= minY) {
                ny = minY
                canvas.velY = Math.abs(canvas.velY)
                bounced = true
              } else if (ny >= maxY) {
                ny = maxY
                canvas.velY = -Math.abs(canvas.velY)
                bounced = true
              }

              canvas.posX = nx
              canvas.posY = ny
              if (bounced && root.palette.length > 0) {
                canvas.colorIndex = (canvas.colorIndex + 1) % root.palette.length
              }
            }
          }

          Item {
            id: artContainer
            readonly property color currentColor: root.palette.length > 0
              ? root.palette[canvas.colorIndex % root.palette.length]
              : Commons.Color.accent

            property color displayColor: currentColor
            Behavior on displayColor {
              ColorAnimation { duration: Style.duration(450); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
            }
            onDisplayColorChanged: if (artCanvas.visible) artCanvas.requestPaint()

            readonly property int blockBaseCell: {
              var art = root.blockArt
              if (!art || canvas.width <= 0 || canvas.height <= 0) return 0
              var maxW = canvas.width * 0.55
              var maxH = canvas.height * 0.55
              var preferred = Style.space(13)
              var raw = Math.min(preferred, maxW / art.cols, maxH / art.gridH)
              if (art.colMult === 2) {
                return Math.max(1, Math.floor(raw / 2)) * 2
              }
              return Math.max(1, Math.floor(raw))
            }
            readonly property int blockCellW: {
              var art = root.blockArt
              if (!art || blockBaseCell <= 0) return 0
              return art.colMult === 2 ? Math.round(blockBaseCell / 2) : blockBaseCell
            }
            readonly property int blockCellH: blockBaseCell

            readonly property real fitScale: {
              if (artTextItem.implicitWidth <= 0 || artTextItem.implicitHeight <= 0 || canvas.width <= 0 || canvas.height <= 0)
                return 1.0
              var maxW = canvas.width * 0.55
              var maxH = canvas.height * 0.55
              return Math.min(1.2, maxW / artTextItem.implicitWidth, maxH / artTextItem.implicitHeight)
            }

            width: root.blockArt
              ? Math.max(1, root.blockArt.gridW * blockCellW)
              : Math.max(1, Math.round(artTextItem.implicitWidth * fitScale))
            height: root.blockArt
              ? Math.max(1, root.blockArt.gridH * blockCellH)
              : Math.max(1, Math.round(artTextItem.implicitHeight * fitScale))
            x: Style.reduceMotion ? Math.round((canvas.width - width) / 2) : Math.round(canvas.posX)
            y: Style.reduceMotion ? Math.round((canvas.height - height) / 2) : Math.round(canvas.posY)

            Canvas {
              id: artCanvas
              visible: win.visible && root.blockArt !== null
              anchors.fill: parent
              antialiasing: false
              renderStrategy: Canvas.Cooperative

              readonly property var artData: root.blockArt
              onArtDataChanged: if (visible) requestPaint()
              onAvailableChanged: if (available && visible) requestPaint()
              onVisibleChanged: if (visible) requestPaint()
              onWidthChanged: if (visible) requestPaint()
              onHeightChanged: if (visible) requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.clearRect(0, 0, width, height)
                var art = artData
                if (!art || width <= 0 || height <= 0) return
                var cw = artContainer.blockCellW
                var ch = artContainer.blockCellH
                if (cw <= 0 || ch <= 0) return
                ctx.fillStyle = artContainer.displayColor
                ctx.beginPath()
                var rects = art.rects
                for (var i = 0; i < rects.length; i++) {
                  var r = rects[i]
                  ctx.rect(r.x * cw, r.y * ch, r.w * cw, r.h * ch)
                }
                ctx.fill()
              }
            }

            Text {
              id: artTextItem
              visible: root.blockArt === null
              anchors.centerIn: parent
              scale: artContainer.fitScale
              textFormat: Text.PlainText
              text: root.artText
              font.family: Style.font.family
              font.pixelSize: Style.space(18)
              font.bold: true
              lineHeight: 0.95
              color: artContainer.displayColor
            }
          }
        }

        // Subtle clock in bottom-right corner
        Column {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: Style.space(32)
          anchors.bottomMargin: Style.space(28)
          spacing: Style.spacing.xs
          opacity: 0.45

          Text {
            textFormat: Text.PlainText
            text: root.clockTime
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            anchors.right: parent.right
          }

          Text {
            textFormat: Text.PlainText
            text: root.clockDate
            color: Commons.Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
          }
        }

        MouseArea {
          id: pointerArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.BlankCursor
          property bool hasInitialPos: false
          property real startX: 0
          property real startY: 0

          onPressed: {
            if (root.armed) root.dismiss()
          }

          onPositionChanged: function(mouse) {
            if (!root.armed) {
              startX = mouse.x
              startY = mouse.y
              hasInitialPos = true
              return
            }
            if (!hasInitialPos) {
              startX = mouse.x
              startY = mouse.y
              hasInitialPos = true
              return
            }
            var dist = Math.abs(mouse.x - startX) + Math.abs(mouse.y - startY)
            if (dist > 16) root.dismiss()
          }
        }
      }
    }
  }
}
