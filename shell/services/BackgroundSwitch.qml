import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Sequence a background change around BackgroundIntro's cover. The outgoing
// frame is held under the cover, the link moves once that cover is on screen,
// the new still goes in beneath it, and the cover opens with the slanted cut.
Item {
  id: root

  property var intro: null
  readonly property var backgroundService: intro ? intro.backgroundService : null
  readonly property string home: Quickshell.env("HOME")
  readonly property string backgroundLink: home + "/.local/state/quattro/current/background"
  readonly property string transitionCache: home + "/.cache/quattro/background-transitions"
  readonly property string themeSetLock: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quattro-theme-set.lock"

  // The change in progress, named by its cover's token.
  property string token: ""
  property string still: ""
  property bool linked: false
  property bool started: false
  property int serial: 0
  // Snapshots this service or a theme switch made for a cover, removed once
  // nothing shows them.
  property var ownedCovers: []
  // A selection made while an earlier change is still covered or revealing
  // waits for it, since its outgoing frame would miss that change's cover.
  property string queuedPath: ""
  property bool reloadPending: false
  // The link's next target while an earlier ln still runs, so the link always
  // ends on the latest selection.
  property string pendingLink: ""

  // A theme switch waits while this is set, so it cannot capture a frame from
  // under a cover or take over from a change still being set up.
  readonly property bool busy: !!intro && (intro.themeToken !== "" || intro.revealing)

  // The background the latest selection names. The link only moves once a
  // change is under way, so a selection still queued or covered is not there
  // yet.
  function selected() {
    if (queuedPath) return queuedPath
    if (token && intro && token === intro.themeToken) return still
    return backgroundService ? backgroundService.currentBackground : ""
  }

  function displayedStill() {
    var path = backgroundService ? (backgroundService.displayedBackground || backgroundService.currentBackground) : ""
    return path && !Util.isVideoPath(path) ? path : ""
  }

  // quattro-theme-bg set's selection.
  function switchTo(path, _clipPath) {
    path = String(path || "").trim()
    if (!path || !intro || !backgroundService) return "unavailable"
    if (busy) {
      queuedPath = path
    } else if (path !== backgroundService.currentBackground) {
      if (backgroundService.suspended) {
        begin(path)
      } else {
        link(path)
        backgroundService.setBackground(path, false)
      }
    }
    return "ok"
  }

  function link(target) {
    pendingLink = target
    if (!linkProc.running) startLink()
  }

  function startLink() {
    linkProc.target = pendingLink
    pendingLink = ""
    linkProc.command = ["ln", "-nsf", linkProc.target, backgroundLink]
    linkProc.running = true
  }

  function begin(path) {
    serial += 1
    token = "background-" + serial
    still = path
    linked = false
    started = false
    cover(displayedStill())
  }

  function cover(path) {
    intro.prepareTheme(path, token, "", "")
    advance()
  }

  // A theme switch has put up its cover and repointed the link itself; the
  // rest is the same as a background change, plus Hyprland's reload.
  function play(tok, stillPath, _clipPath, _preparedFlag) {
    reloadPending = true
    if (!intro || tok !== intro.themeToken) return "superseded"
    token = tok
    still = stillPath
    linked = true
    started = false
    own(intro.themeBackground)
    advance()
    return "ok"
  }

  function own(path) {
    if (path && path.indexOf(transitionCache + "/") === 0 && ownedCovers.indexOf(path) === -1)
      ownedCovers = ownedCovers.concat([path])
  }

  function advance() {
    if (!token || !intro || token !== intro.themeToken) return
    var coverStatus = intro.themeCoverStatus(token)
    if (coverStatus === "loading") return
    if (!linked) {
      if (pendingLink !== still && !(linkProc.running && linkProc.target === still)) link(still)
      return
    }
    if (started) return
    started = true
    if (backgroundService) backgroundService.setBackground(still, true)
    intro.finishTheme(token, true)
  }

  function settle() {
    if (busy) return
    if (reloadPending && !reloadLock.running) reloadLock.running = true
    var kept = []
    for (var path of ownedCovers) {
      if (path === intro.themeBackground) kept.push(path)
      else Quickshell.execDetached(["rm", "-f", path])
    }
    ownedCovers = kept
    if (queuedPath) {
      Quickshell.execDetached(["quattro-theme-bg", "set", queuedPath])
      queuedPath = ""
    }
  }

  // A reveal clears its token just before its animation starts, so settling
  // waits until both have changed.
  Connections {
    target: root.intro
    function onCoverPresented() { root.advance() }
    function onThemeTokenChanged() {
      // A theme switch taking the cover brings its own background.
      if (root.intro.themeToken && root.intro.themeToken !== root.token) root.queuedPath = ""
      Qt.callLater(root.settle)
    }
    function onRevealingChanged() { Qt.callLater(root.settle) }
  }

  Process {
    id: reloadLock
    command: ["flock", root.themeSetLock, "bash", "-c", 'echo locked; read -r go; [[ $go != reload ]] || exec quattro-restart hyprctl']
    stdinEnabled: true
    stdout: SplitParser {
      onRead: {
        var go = !root.busy
        if (go) root.reloadPending = false
        reloadLock.write(go ? "reload\n" : "wait\n")
      }
    }
  }

  Process {
    id: linkProc
    property string target: ""
    onExited: {
      if (root.pendingLink) Qt.callLater(root.startLink)
      else if (root.token && target === root.still) root.linked = true
      root.advance()
    }
  }
}
