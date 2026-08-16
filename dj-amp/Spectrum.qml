import QtQuick
import Quickshell.Io

// A Winamp-style segmented analyzer driven by cliamp's own spectrum.
//
// `cliamp visstream` holds one IPC connection open and prints one JSON line
// per frame — the same ten bands cliamp's built-in visualizers draw from. We
// read the lines as they land instead of polling, so the bars move with the
// music rather than with a timer of our own.
Item {
  id: root

  // Held open only while something is watching. This is a process and an open
  // socket for as long as it runs; a closed panel should cost neither.
  property bool active: false
  property int fps: 30
  property color foreground: "#cacccc"
  property color accent: "#cacccc"

  readonly property int bandCount: 10
  property var bands: zeros()
  property var peaks: zeros()
  property string mode: ""

  function zeros() {
    var out = []
    for (var i = 0; i < 10; i++) out.push(0)
    return out
  }

  Process {
    id: stream
    // The frame rate is read when the stream starts. Changing it takes effect
    // the next time the panel opens, which is the only time the process is
    // started anyway.
    command: ["cliamp", "visstream", "--fps", String(Math.max(1, Math.min(60, root.fps)))]
    running: root.active

    stdout: SplitParser {
      onRead: function(line) { root.consume(line) }
    }

    onExited: {
      root.bands = root.zeros()
      root.peaks = root.zeros()
    }
  }

  function consume(line) {
    var text = String(line || "").trim()
    if (text === "") return

    var frame = null
    try {
      frame = JSON.parse(text)
    } catch (e) {
      return
    }
    if (!frame || frame.ok !== true || !Array.isArray(frame.bands)) return

    root.mode = String(frame.visualizer || "")

    var next = []
    var nextPeaks = []
    for (var i = 0; i < bandCount; i++) {
      var value = Number(frame.bands[i])
      if (!isFinite(value)) value = 0
      value = Math.max(0, Math.min(1, value))
      next.push(value)
      // Peak caps rise instantly and fall on their own, the way Winamp's did.
      var previous = Number(peaks[i]) || 0
      nextPeaks.push(value > previous ? value : previous)
    }
    bands = next
    peaks = nextPeaks
  }

  // The caps fall on a fixed cadence rather than per frame, so they drop at
  // the same speed whether the stream is running at 30fps or 60.
  Timer {
    interval: 60
    running: root.active
    repeat: true
    onTriggered: {
      var next = []
      var moved = false
      for (var i = 0; i < root.bandCount; i++) {
        var value = Math.max(Number(root.bands[i]) || 0, (Number(root.peaks[i]) || 0) - 0.025)
        if (value !== root.peaks[i]) moved = true
        next.push(Math.max(0, value))
      }
      if (moved) root.peaks = next
    }
  }

  Row {
    id: bars
    anchors.fill: parent
    spacing: Math.max(1, Math.round(root.width / 90))

    readonly property real barWidth: (root.width - spacing * (root.bandCount - 1)) / root.bandCount

    Repeater {
      model: root.bandCount

      Item {
        id: cell
        required property int index
        width: bars.barWidth
        height: root.height

        readonly property real level: Number(root.bands[index]) || 0
        readonly property real peak: Number(root.peaks[index]) || 0

        // Low end in the accent, high end fading out — the eye reads the
        // shape of the mix faster than it reads ten identical bars.
        readonly property color barColor: Qt.rgba(
          root.accent.r + (root.foreground.r - root.accent.r) * (index / (root.bandCount - 1)),
          root.accent.g + (root.foreground.g - root.accent.g) * (index / (root.bandCount - 1)),
          root.accent.b + (root.foreground.b - root.accent.b) * (index / (root.bandCount - 1)),
          1.0)

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(1, cell.height * cell.level)
          radius: Math.min(width, height) / 3
          color: cell.barColor

          Behavior on height {
            NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
          }
        }

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Math.min(cell.height - height, cell.height * cell.peak)
          width: parent.width
          height: Math.max(1, Math.round(root.height / 28))
          color: cell.barColor
          opacity: 0.55
          visible: cell.peak > 0.02
        }

        // The floor line, so an idle analyzer still reads as an analyzer
        // rather than as empty space.
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: 1
          color: cell.barColor
          opacity: 0.25
        }
      }
    }
  }
}
