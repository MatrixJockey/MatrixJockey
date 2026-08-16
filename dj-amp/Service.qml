import QtQuick
import Quickshell
import Quickshell.Io

// The booth. One instance per shell, no UI.
//
// Everything DJ Amp knows about the deck comes off `cliamp status --json` over
// cliamp's IPC socket, and everything it does to the deck goes back the same
// way. The DJ itself — the part that decides what to play — lives in
// bin/dj-amp-brain, which prints a set of moves as JSON and touches nothing.
// This file is what applies them, and it only applies moves it recognizes:
// the brain hands over an intention, never a command line.
Item {
  id: root
  visible: false

  // ------------------------------------------------------------- injected
  //
  // The shell sets these when the service mounts.
  property var shell: null
  property var manifest: null

  // Panel.qml pushes these across. The settings live on the bar-widget's
  // shell.json entry — the widget is the half of the plugin that is handed
  // them, so it is the half that forwards them.
  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string brainPath: sourceDir === "" ? "" : sourceDir + "/bin/dj-amp-brain"

  readonly property bool autopilot: setting("autopilot", true) === true
  readonly property string vibe: String(setting("vibe", ""))
  readonly property string crate: String(setting("crate", "Playlists + search"))
  readonly property string agent: String(setting("agent", "auto"))
  readonly property int handoffSeconds: clampNumber(setting("handoffSeconds", 25), 0, 120)
  readonly property int pollMs: clampNumber(setting("pollMs", 1000), 250, 10000)
  readonly property bool announce: setting("announce", true) === true

  function clampNumber(value, lo, hi) {
    var n = Number(value)
    if (!isFinite(n)) return lo
    return Math.max(lo, Math.min(hi, Math.round(n)))
  }

  // ----------------------------------------------------------- deck state
  //
  // `probed` separates "we have not asked yet" from "we asked and cliamp is
  // not running", so the bar can stay empty on a fresh login instead of
  // flashing a dead turntable for one poll interval.
  property bool probed: false
  property bool live: false
  property bool installed: true

  property string playState: "stopped"
  property string trackTitle: ""
  property string trackArtist: ""
  property string trackPath: ""
  property real position: 0
  property real duration: 0
  property real volume: 0
  property string playlistName: ""
  property int trackIndex: 0
  property int trackTotal: 0
  property string visualizer: ""

  readonly property bool playing: live && playState === "playing"
  readonly property bool hasTrack: live && (trackTitle !== "" || trackArtist !== "")
  readonly property real remaining: duration > 0 ? Math.max(0, duration - position) : -1
  readonly property real progress: duration > 0 ? Math.max(0, Math.min(1, position / duration)) : 0
  readonly property string nowPlaying: {
    if (!hasTrack) return ""
    if (trackArtist === "") return trackTitle
    if (trackTitle === "") return trackArtist
    return trackTitle + " · " + trackArtist
  }

  // -------------------------------------------------------------- the DJ
  property bool thinking: false
  property string djSay: ""
  property string djReason: ""
  property string djSource: ""
  property string djError: ""
  property double djAt: 0

  // Newest first, capped. This is what the panel shows as the set list and
  // what the brain gets handed back as "what you already played", so the DJ
  // stops reaching for the same record twice.
  property var setList: []
  readonly property int setListCap: 12

  signal called(string say)

  // ----------------------------------------------------------------- poll
  //
  // Two cadences: the configured one while a record is on, and a lazy 5s while
  // the deck is idle. A paused player does not need to be asked every second
  // where it is, and an unconfigured machine should not spawn a process a
  // second forever.
  Timer {
    id: pollTimer
    interval: root.playing ? root.pollMs : Math.max(root.pollMs, 5000)
    running: root.installed
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.running = true
  }

  Process {
    id: statusProcess
    running: false
    command: ["cliamp", "status", "--json"]

    stdout: StdioCollector { id: statusOut }
    stderr: StdioCollector { id: statusErr }

    onExited: function(exitCode, exitStatus) {
      root.probed = true

      // Exit 127 (and a "not found" from the shell) means cliamp is not on the
      // machine at all, which is a different thing from cliamp not running:
      // one is worth saying out loud once, the other is just a quiet bar.
      var stderrText = String(statusErr.text || "")
      if (exitCode === 127 || stderrText.indexOf("executable file not found") >= 0) {
        // The poll timer is bound to `installed`, so clearing it here is what
        // stops us spawning a process a second on a machine without cliamp.
        root.installed = false
        root.live = false
        return
      }

      root.installed = true

      var text = String(statusOut.text || "").trim()
      if (exitCode !== 0 || text === "") {
        root.goDark()
        return
      }

      var payload = null
      try {
        payload = JSON.parse(text)
      } catch (e) {
        root.goDark()
        return
      }
      if (!payload || payload.ok !== true) {
        root.goDark()
        return
      }

      root.applyStatus(payload)
    }
  }

  function goDark() {
    live = false
    playState = "stopped"
    trackTitle = ""
    trackArtist = ""
    trackPath = ""
    position = 0
    duration = 0
    playlistName = ""
    trackIndex = 0
    trackTotal = 0
  }

  function applyStatus(payload) {
    var track = payload.track || {}
    var previousPath = trackPath
    var previousState = playState

    live = true
    playState = String(payload.state || "stopped")
    trackTitle = String(track.title || "")
    trackArtist = String(track.artist || "")
    trackPath = String(track.path || "")
    position = Number(payload.position) || 0
    duration = Number(payload.duration) || 0
    volume = Number(payload.volume) || 0
    playlistName = String(payload.playlist || "")
    trackIndex = Number(payload.index) || 0
    trackTotal = Number(payload.total) || 0
    visualizer = String(payload.visualizer || "")

    // A new record is on: the DJ gets to cue the next one again.
    if (trackPath !== previousPath) handoffKey = ""

    considerHandoff(previousState)
  }

  // ------------------------------------------------------------ autopilot
  //
  // The DJ is asked for the next record once per track, `handoffSeconds`
  // before the end, and once more if the deck falls silent — cliamp reaching
  // the end of a playlist with nothing queued behind it.
  property string handoffKey: ""
  property bool deckRanOut: false

  function considerHandoff(previousState) {
    if (!autopilot || thinking || !live) return

    if (playState === "stopped") {
      // Only on the transition. A deck that has been stopped since login is
      // someone choosing silence, not a set that ran dry.
      if (previousState === "playing" && !deckRanOut) {
        deckRanOut = true
        callTheDJ("deck-empty", "")
      }
      return
    }

    deckRanOut = false
    if (playState !== "playing") return
    if (handoffSeconds <= 0) return
    if (duration <= 0 || remaining < 0) return
    if (remaining > handoffSeconds) return

    var key = trackPath !== "" ? trackPath : (trackTitle + "|" + trackArtist)
    if (key === "" || key === handoffKey) return
    handoffKey = key
    callTheDJ("handoff", "")
  }

  // ------------------------------------------------------------- the call
  //
  // `reason` is why we are asking (handoff / deck-empty / request / manual),
  // `request` is the listener's own words when there are any.
  function callTheDJ(reason, request) {
    if (thinking) return
    if (brainPath === "") {
      djError = "DJ Amp could not find its own plugin directory."
      return
    }
    djError = ""
    thinking = true

    brainProcess.command = [
      brainPath,
      "--reason", String(reason || "manual"),
      "--request", String(request || ""),
      "--vibe", vibe,
      "--crate", crate,
      "--agent", agent,
      "--recent", recentTitles().join("\n")
    ]
    brainProcess.running = true
  }

  function recentTitles() {
    var out = []
    for (var i = 0; i < setList.length; i++) {
      var entry = setList[i]
      if (entry && entry.playing) out.push(String(entry.playing))
    }
    return out
  }

  Process {
    id: brainProcess
    running: false

    stdout: StdioCollector { id: brainOut }
    stderr: StdioCollector { id: brainErr }

    onExited: function(exitCode, exitStatus) {
      root.thinking = false

      var text = String(brainOut.text || "").trim()
      if (text === "") {
        root.djError = String(brainErr.text || "").trim() || "The DJ said nothing."
        return
      }

      var plan = null
      try {
        plan = JSON.parse(text)
      } catch (e) {
        root.djError = "The DJ's answer was not JSON."
        return
      }

      if (!plan || plan.ok !== true) {
        root.djError = plan && plan.error ? String(plan.error) : "The DJ passed."
        return
      }

      root.applyPlan(plan)
    }
  }

  // ---------------------------------------------------------- apply moves
  //
  // The brain returns intentions, not commands. Each move names a cliamp verb
  // from this table and at most one argument, and the argument is passed as
  // its own argv element — there is no shell in the path, so nothing the model
  // writes can turn into a second command. A verb that isn't in the table is
  // dropped and reported rather than guessed at.
  readonly property var allowedMoves: ({
    "play": 0, "pause": 0, "toggle": 0, "stop": 0, "next": 0, "prev": 0,
    "load": 1, "queue": 1, "search": 1, "volume": 1, "seek": 1,
    "shuffle": 1, "repeat": 1, "speed": 1, "eq": 1
  })

  function applyPlan(plan) {
    djSay = String(plan.say || "")
    djReason = String(plan.reason || "")
    djSource = String(plan.source || "")
    djAt = Date.now()

    var moves = Array.isArray(plan.moves) ? plan.moves : []
    var applied = []
    var rejected = []

    for (var i = 0; i < moves.length; i++) {
      var move = moves[i]
      if (!move) continue
      var cmd = String(move.cmd || "").trim()
      if (!(cmd in allowedMoves)) {
        rejected.push(cmd === "" ? "(empty)" : cmd)
        continue
      }

      var argv = ["cliamp", cmd]
      if (allowedMoves[cmd] === 1) {
        var arg = move.arg === undefined || move.arg === null ? "" : String(move.arg)
        if (arg === "") {
          rejected.push(cmd + " (no argument)")
          continue
        }
        argv.push(arg)
        applied.push(cmd + " " + arg)
      } else {
        applied.push(cmd)
      }
      queueMove(argv)
    }

    if (rejected.length > 0)
      djError = "Ignored: " + rejected.join(", ")

    if (applied.length === 0 && djSay === "") return

    var entry = {
      say: djSay,
      reason: djReason,
      source: djSource,
      moves: applied.join(" · "),
      playing: String(plan.playing || ""),
      at: djAt
    }
    var next = [entry]
    for (var j = 0; j < setList.length && next.length < setListCap; j++) next.push(setList[j])
    setList = next

    if (applied.length > 0) {
      // A move only just landed on the deck; give cliamp a beat to act on it
      // before we ask it what's playing, or the panel shows the old record.
      settleTimer.restart()
      if (announce && djSay !== "") notify(djSay, djReason)
      called(djSay)
    }
  }

  // Moves are applied one at a time and in order. `cliamp load` followed
  // immediately by `cliamp play` from two concurrent processes is a race over
  // one socket; a queue makes the order the DJ asked for the order it gets.
  property var moveQueue: []

  function queueMove(argv) {
    var next = moveQueue.slice()
    next.push(argv)
    moveQueue = next
    pumpMoves()
  }

  function pumpMoves() {
    if (moveProcess.running || moveQueue.length === 0) return
    var next = moveQueue.slice()
    var argv = next.shift()
    moveQueue = next
    moveProcess.command = argv
    moveProcess.running = true
  }

  Process {
    id: moveProcess
    running: false
    stderr: StdioCollector { id: moveErr }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        var message = String(moveErr.text || "").trim()
        if (message !== "") root.djError = message
      }
      // Deferred: `running` is not guaranteed to have gone false by the time
      // this handler runs, and pumpMoves() reads it to decide whether the deck
      // is free. Draining the queue from inside the handler would see the
      // process it is reacting to and stall the rest of the plan forever.
      Qt.callLater(root.pumpMoves)
    }
  }

  Timer {
    id: settleTimer
    interval: 700
    repeat: false
    onTriggered: root.refresh()
  }

  Process {
    id: notifyProcess
    running: false
  }

  function notify(title, body) {
    if (notifyProcess.running) return
    notifyProcess.command = ["notify-send", "-a", "DJ Amp", "-i", "multimedia-volume-control",
                             "DJ Amp — " + title, String(body || "")]
    notifyProcess.running = true
  }

  // ------------------------------------------------------ hands on the deck
  //
  // What the panel and the bar button call. These bypass the DJ entirely:
  // when you press skip, you skip.
  function deck(cmd, arg) {
    var argv = ["cliamp", cmd]
    if (arg !== undefined && arg !== null && String(arg) !== "") argv.push(String(arg))
    queueMove(argv)
    settleTimer.restart()
  }

  function playPause() { deck("toggle") }
  function skip() { deck("next") }
  function back() { deck("prev") }
  function nudgeVolume(deltaDb) { deck("volume", String(deltaDb)) }

  function request(text) {
    var trimmed = String(text || "").trim()
    if (trimmed === "") return
    callTheDJ("request", trimmed)
  }

  function takeOver() { callTheDJ("manual", "") }

  function setAutopilot(on) {
    if (!shell || typeof shell.updateEntryInline !== "function") return
    var next = {}
    for (var k in settings) next[k] = settings[k]
    next.autopilot = on === true
    shell.updateEntryInline("matrixjockey.dj-amp", next)
  }

  // Terminal and hotkey surface: `omarchy-shell dj-amp <method>`.
  IpcHandler {
    target: "dj-amp"

    function status(): string {
      return JSON.stringify({
        live: root.live,
        installed: root.installed,
        state: root.playState,
        nowPlaying: root.nowPlaying,
        autopilot: root.autopilot,
        thinking: root.thinking,
        say: root.djSay,
        reason: root.djReason
      })
    }
    function request(text: string): string { root.request(text); return "ok" }
    function mix(): string { root.takeOver(); return "ok" }
    function skip(): string { root.skip(); return "ok" }
    function back(): string { root.back(); return "ok" }
    function playPause(): string { root.playPause(); return "ok" }
    function autopilot(on: string): string {
      root.setAutopilot(String(on) === "true")
      return root.autopilot ? "on" : "off"
    }
  }
}
