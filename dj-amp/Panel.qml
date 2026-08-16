import QtQuick
import QtQuick.Controls
import qs.Commons
// Imported last on purpose: this file is itself Panel.qml, and the implicit
// import of its own directory would otherwise make the root element resolve to
// this file rather than to the qs.Ui base it extends.
import qs.Ui

// The face of the booth: one bar button and one panel.
//
// All the state lives in Service.qml; this file only draws it and forwards
// what you press. The one thing it owns is the settings, because the bar is
// what the shell hands them to — so it pushes them across to the service.
Panel {
  id: root
  moduleName: "matrixjockey.dj-amp"
  ipcTarget: ""
  manageIpc: false

  readonly property var dj: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("matrixjockey.dj-amp") : null

  // The service is mounted by the shell, not by us, and it has no settings of
  // its own to read — the shell.json entry belongs to this widget. Forward
  // them on every change and once at mount, since the service can finish
  // loading on either side of the first settings assignment.
  function pushSettings() {
    if (dj && "settings" in dj) dj.settings = root.settings
  }
  onSettingsChanged: pushSettings()
  onDjChanged: pushSettings()
  Component.onCompleted: pushSettings()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color dimmer: Qt.darker(foreground, 1.8)
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool live: !!dj && dj.live
  readonly property bool playing: !!dj && dj.playing
  readonly property bool hasTrack: !!dj && dj.hasTrack
  readonly property bool thinking: !!dj && dj.thinking
  readonly property bool autopilot: !!dj && dj.autopilot

  readonly property int maxLabelWidth: Math.max(0, Number(setting("maxLabelWidth", 200)))
  readonly property bool showSpectrum: setting("showSpectrum", true) === true
  readonly property int spectrumFps: Math.max(1, Math.min(60, Number(setting("spectrumFps", 30))))

  readonly property string label: hasTrack ? dj.nowPlaying : ""

  // A record on the deck, a record standing still, and the needle lighting up
  // while the DJ works out what goes on next.
  readonly property string glyph: thinking ? "󰧑" : (playing ? "󰓃" : "󰓄")

  // Nothing to show and nothing to control: stay out of the bar entirely
  // rather than sit there as a dead button. cliamp not being installed is the
  // clearest case, but so is cliamp simply not running — this is a widget
  // about a player, and with no player it has nothing to say.
  visible: !!dj && dj.probed && dj.installed && (live || root.opened)
  implicitWidth: visible ? faceRow.implicitWidth : 0
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  function fmtTime(seconds) {
    var s = Math.max(0, Math.floor(Number(seconds) || 0))
    var m = Math.floor(s / 60)
    var rest = s % 60
    return m + ":" + (rest < 10 ? "0" : "") + rest
  }

  function tooltip() {
    if (!live) return "cliamp is not running"
    if (!hasTrack) return "DJ Amp — nothing on the deck"
    return dj.nowPlaying + (autopilot ? "  ·  autopilot on" : "")
  }

  // ------------------------------------------------------------- bar face
  Row {
    id: faceRow
    anchors.centerIn: parent
    spacing: 0

    BarIconButton {
      id: button
      anchors.verticalCenter: parent.verticalCenter
      bar: root.bar
      text: root.glyph
      active: root.thinking
      slotSize: Style.bar.statusSlot
      tooltipText: root.opened ? "" : root.tooltip()

      onPressed: function(buttonCode) {
        if (!root.dj) return
        if (buttonCode === Qt.RightButton) root.dj.skip()
        else if (buttonCode === Qt.MiddleButton) root.dj.setAutopilot(!root.autopilot)
        else root.toggle()
      }
    }

    // A scrolling now-playing label, the way cliamp scrolls its own title when
    // it outgrows the width it has. Suppressed on a vertical bar, where there
    // is no width to scroll through.
    Item {
      id: labelClip
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? Math.min(root.maxLabelWidth, labelText.implicitWidth) : 0
      height: button.height
      clip: true
      visible: !(root.bar && root.bar.vertical) && root.maxLabelWidth > 0 && root.label !== ""

      Text {
        id: labelText
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.playing ? root.barForeground : Qt.darker(root.barForeground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body

        readonly property bool needsScroll: implicitWidth > labelClip.width

        NumberAnimation on x {
          running: labelText.needsScroll && labelClip.visible && !root.opened
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          from: labelClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }

        // Not scrolling means sitting at 0. Without this, a title that grows
        // long and then short again keeps whatever x the animation stopped at.
        onNeedsScrollChanged: if (!needsScroll) x = 0
      }
    }
  }

  // --------------------------------------------------------------- panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While the request line has the caret every key belongs to it,
      // including the j/k/a/m that would otherwise drive the deck.
      blocked: requestField.activeFocus

      onMoveRequested: function(dx, dy) {
        if (!root.dj) return
        if (dx > 0) root.dj.nudgeVolume(1)
        else if (dx < 0) root.dj.nudgeVolume(-1)
        if (dy > 0) root.dj.skip()
        else if (dy < 0) root.dj.back()
      }
      onActivateRequested: if (root.dj) root.dj.playPause()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (!root.dj) return
        if (t === "m" || t === "M") root.dj.takeOver()
        else if (t === "a" || t === "A") root.dj.setAutopilot(!root.autopilot)
        else if (t === "/") requestField.forceActiveFocus()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          // ---------- now playing ----------
          PanelHero {
            width: parent.width
            title: root.hasTrack ? (root.dj.trackTitle !== "" ? root.dj.trackTitle : root.dj.trackArtist)
                                 : "Nothing on the deck"
            meta: {
              if (!root.live) return "cliamp is not running"
              if (!root.hasTrack) return "Ask for something and the DJ will go find it"
              var parts = []
              if (root.dj.trackArtist !== "" && root.dj.trackTitle !== "") parts.push(root.dj.trackArtist)
              if (root.dj.playlistName !== "") parts.push(root.dj.playlistName)
              if (root.dj.trackTotal > 0) parts.push(root.dj.trackIndex + " of " + root.dj.trackTotal)
              return parts.join("  ·  ")
            }
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                id: heroGlyph
                text: root.glyph
                color: root.thinking ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display

                RotationAnimation on rotation {
                  running: root.playing
                  loops: Animation.Infinite
                  from: 0
                  to: 360
                  duration: 3600
                }

                // The animation leaves the platter wherever it stopped;
                // a paused record should sit square.
                Connections {
                  target: root
                  function onPlayingChanged() { if (!root.playing) heroGlyph.rotation = 0 }
                }
              }
            }
          }

          // ---------- position ----------
          Item {
            width: parent.width
            height: Style.space(20)
            visible: root.hasTrack && root.dj.duration > 0

            Rectangle {
              id: progressTrack
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Style.space(3)
              radius: height / 2
              color: Style.selectedFillFor(root.foreground, root.accent)

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * (root.dj ? root.dj.progress : 0)
                radius: parent.radius
                color: root.accent
              }
            }

            // Click anywhere along the track to seek there. cliamp takes an
            // absolute position in seconds, which is exactly what a click on a
            // known-length bar gives you.
            MouseArea {
              anchors.fill: progressTrack
              anchors.topMargin: -Style.space(6)
              anchors.bottomMargin: -Style.space(6)
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (!root.dj || root.dj.duration <= 0) return
                var ratio = Math.max(0, Math.min(1, mouse.x / width))
                root.dj.deck("seek", String(Math.round(ratio * root.dj.duration)))
              }
            }

            Text {
              anchors.left: parent.left
              anchors.top: progressTrack.bottom
              anchors.topMargin: Style.space(3)
              text: root.dj ? root.fmtTime(root.dj.position) : "0:00"
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              anchors.top: progressTrack.bottom
              anchors.topMargin: Style.space(3)
              text: root.dj ? "-" + root.fmtTime(root.dj.remaining) : ""
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- spectrum ----------
          Spectrum {
            width: parent.width
            height: Style.space(46)
            visible: root.showSpectrum && root.live
            // The stream is a process held open for as long as it runs, so it
            // only runs while someone is looking at it.
            active: root.opened && root.showSpectrum && root.playing
            fps: root.spectrumFps
            foreground: root.foreground
            accent: root.accent
          }

          // ---------- transport ----------
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)

            PanelActionButton {
              iconText: "󰒮"
              tooltipText: "Previous"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.live
              onClicked: if (root.dj) root.dj.back()
            }

            PanelActionButton {
              iconText: root.playing ? "󰏤" : "󰐊"
              tooltipText: root.playing ? "Pause" : "Play"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.iconLarge
              enabled: root.live
              onClicked: if (root.dj) root.dj.playPause()
            }

            PanelActionButton {
              iconText: "󰒭"
              tooltipText: "Next"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.live
              onClicked: if (root.dj) root.dj.skip()
            }

            PanelActionButton {
              iconText: "󰑖"
              tooltipText: "Have the DJ mix the next record now"
              foreground: root.foreground
              hoverColor: root.accent
              fontFamily: root.fontFamily
              enabled: root.live && !root.thinking
              onClicked: if (root.dj) root.dj.takeOver()
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // ---------- the DJ ----------
          Item {
            width: parent.width
            height: Math.max(djHeader.implicitHeight, autopilotToggle.height)

            PanelSectionHeader {
              id: djHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "THE DJ"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ToggleSwitch {
              id: autopilotToggle
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.autopilot
              busy: root.thinking
              foreground: root.foreground
              accent: root.accent
              onToggled: if (root.dj) root.dj.setAutopilot(!root.autopilot)
            }

            Text {
              anchors.right: autopilotToggle.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "Autopilot"
              color: root.autopilot ? root.foreground : root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // What the DJ said last, and why. The reason is the interesting
          // half: it is the whole difference between a shuffle and a DJ.
          BorderSurface {
            width: parent.width
            height: callColumn.implicitHeight + Style.space(16)
            radius: Style.spacing.labelGap
            visible: root.thinking || (!!root.dj && (root.dj.djSay !== "" || root.dj.djError !== ""))
            color: Style.normalFillFor(root.foreground, root.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

            Column {
              id: callColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(3)

              Text {
                width: parent.width
                text: root.thinking ? "Reading the room…" : (root.dj ? root.dj.djSay : "")
                visible: text !== ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                text: root.dj && !root.thinking ? root.dj.djReason : ""
                visible: text !== ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                text: root.dj ? root.dj.djError : ""
                visible: text !== ""
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          // ---------- requests ----------
          TextField {
            id: requestField
            width: parent.width
            placeholderText: root.thinking ? "The DJ is working…" : "Request something — \"nothing with words\""
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            enabled: root.live && !root.thinking

            onAccepted: {
              if (!root.dj) return
              root.dj.request(text)
              text = ""
              keyCatcher.forceActiveFocus()
            }

            Keys.onEscapePressed: function(event) {
              text = ""
              keyCatcher.forceActiveFocus()
              event.accepted = true
            }
          }

          // ---------- set list ----------
          PanelSeparator {
            width: parent.width
            foreground: root.foreground
            visible: setList.visible
          }

          PanelSectionHeader {
            text: "SET LIST"
            foreground: root.foreground
            fontFamily: root.fontFamily
            visible: setList.visible
          }

          Column {
            id: setList
            width: parent.width
            spacing: Style.space(5)
            visible: !!root.dj && root.dj.setList.length > 0

            Repeater {
              model: root.dj ? root.dj.setList : []

              Row {
                id: setRow
                required property var modelData
                width: setList.width
                spacing: Style.space(8)

                readonly property string saidIt: modelData ? String(modelData.say || "") : ""
                readonly property string didIt: modelData ? String(modelData.moves || "") : ""

                Text {
                  // Which DJ made the call: the agent, or the rules it falls
                  // back to when no agent answered.
                  width: Style.space(12)
                  text: setRow.modelData && setRow.modelData.source === "agent" ? "󰧑" : "󰙨"
                  color: root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Column {
                  width: setList.width - Style.space(20)
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: setRow.saidIt !== "" ? setRow.saidIt : setRow.didIt
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: setRow.didIt
                    visible: setRow.saidIt !== "" && setRow.didIt !== ""
                    color: root.dimmer
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }

          // ---------- keys ----------
          Text {
            width: parent.width
            topPadding: Style.space(2)
            text: "j/k skip · h/l volume · Enter play/pause · / request · m mix now · a autopilot"
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // Give the deck a look the moment the panel opens rather than waiting out
  // the idle poll — an idle cliamp is polled every five seconds, and that is a
  // visible lag on a panel someone just asked for.
  //
  // There is deliberately no IpcHandler here. A bar widget is instantiated
  // once per monitor, and an IPC target only ever routes to whichever instance
  // claimed it first; `omarchy-shell shell toggle matrixjockey.dj-amp` goes
  // through the bar instead and lands on the focused screen. The Panel base
  // supplies the open/close/opened the bar looks for.
  onOpenedChanged: if (opened && dj) dj.refresh()
}
