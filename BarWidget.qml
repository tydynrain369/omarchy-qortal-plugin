import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui

// Qortal node status — the color-coded Q-logo tray applet reborn for Omarchy.
// Red logo: not synced (or node down). Blue: synced. Blue ring + gold center:
// synced and minting. Height + deterministic payout countdown: every 1000th
// block is a payout block (wiki: block_rewards_distribution), so the next
// payout height is the next multiple of 1000. ETA uses the MEASURED average
// block time since the last payout block (self-correcting each refresh).
// "✦hunt" on the payout block itself; "✦paid" for a few blocks after a
// confirmed balance jump. Click opens Qortal Hub; right-click refreshes.
BarWidget {
  id: root
  moduleName: "qortal.node"

  // ---------- state ----------
  property var status: null
  property real balance: -1
  property real lastPayoutHeight: -1
  property date lastPayoutAt: new Date(0)
  property real height_: -1
  property real blockSeconds: 72          // measured average; refined each refresh
  property real anchorBlock: -1           // payout block used for the measurement

  readonly property bool nodeUp: status !== null
  readonly property bool synced: nodeUp && status.isSynchronizing === false && status.syncPercent >= 100
  readonly property bool minting: nodeUp && status.isMintingPossible === true
  readonly property color ringColor: synced ? "#2a7fd4" : "#e5484d"
  readonly property color centerColor: (synced && minting) ? "#f5c542" : ringColor

  // Deterministic payout math — no learning mode, no observation needed.
  readonly property real nextPayout: height_ > 0 ? (Math.floor(height_ / 1000) + 1) * 1000 : -1
  readonly property int blocksLeft: nextPayout > 0 ? Math.max(0, Math.floor(nextPayout - height_)) : -1
  readonly property int secsLeft: blocksLeft > 0 ? Math.round(blocksLeft * blockSeconds) : 0
  readonly property string estText: secsLeft > 0
    ? (secsLeft >= 3600
        ? "~" + Math.floor(secsLeft / 3600) + "h" + String(Math.floor((secsLeft % 3600) / 60)).padStart(2, "0") + "m"
        : "~" + Math.floor(secsLeft / 60) + "m")
      + " @" + Qt.formatDateTime(new Date(Date.now() + secsLeft * 1000), "h:mmap")
    : ""
  readonly property bool justPaid: blocksLeft > 0 && lastPayoutHeight > 0 && (height_ - lastPayoutHeight) < 20
  readonly property string payoutText: blocksLeft < 0 ? "⏳···"
    : blocksLeft === 0 ? "✦hunt"
    : justPaid ? "✦paid"
    : "⏳" + blocksLeft + "b"
  readonly property string heightText: nodeUp ? Math.floor(status.height).toLocaleString(Qt.locale("en-US"), "f", 0) : "—"

  function refresh() {
    statusProc.running = true
    balanceProc.running = true
  }

  // 2026-10-21: this Quickshell build's FileView has NO writeText() — the
  // original saveState silently crashed, so no state was EVER persisted (the
  // eternal "learning mode"). Writes now go through a base64-encoded sh pipe:
  // quoting-proof, version-independent.
  function saveState() {
    var json = JSON.stringify({
      lastPayoutHeight: lastPayoutHeight,
      lastPayoutAt: lastPayoutAt.getTime(),
      balance: balance
    })
    saveProc.command = ["sh", "-c",
      "echo " + Qt.btoa(json) + " | base64 -d > " + stateFile.path]
    saveProc.running = true
  }

  // 2026-10-21 fix: the balance baseline must load on its own — gating it on
  // lastPayoutHeight meant every restart re-anchored to -1 and silently
  // swallowed any payout that landed in between (today's missed payment).
  function loadState(txt) {
    try {
      var s = JSON.parse(txt)
      if (!s) return
      if (typeof s.balance === "number") balance = s.balance
      if (s.lastPayoutHeight > 0) {
        lastPayoutHeight = s.lastPayoutHeight
        lastPayoutAt = new Date(s.lastPayoutAt || 0)
      }
    } catch (e) {}
  }

  // Appear only while the node answers — the slot vanishes when Qortal is down.
  visible: root.nodeUp

  Component.onCompleted: refresh()

  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.refresh() }

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/qortal-widget.json"
    preload: true
    watchChanges: false
    onFileChanged: root.loadState(text)
  }

  // State writer (see saveState) — FileView is read-only in this build.
  Process { id: saveProc }

  Process {
    id: statusProc
    command: ["curl", "-s", "-m", "4", "http://localhost:12391/admin/status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.status = JSON.parse(text)
          root.height_ = root.status.height
          // Measure real average block time against the last payout block.
          var P = Math.floor(root.height_ / 1000) * 1000
          if (root.height_ === P && P > 0) P -= 1000
          if (P > 0) {
            root.anchorBlock = P
            payoutProc.command = ["curl", "-s", "-m", "4", "http://localhost:12391/blocks/byheight/" + P]
            payoutProc.running = true
          }
        } catch (e) { root.status = null }
      }
    }
  }

  // One lookup: the last payout block's Unix-ms timestamp → measured s/block.
  Process {
    id: payoutProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var blk = JSON.parse(text)
          var ts = blk && blk.timestamp
          var elapsedBlocks = root.height_ - root.anchorBlock
          if (ts > 0 && elapsedBlocks > 0) {
            var secs = (Date.now() - ts) / elapsedBlocks / 1000
            if (secs > 30 && secs < 300) root.blockSeconds = secs
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: balanceProc
    command: ["curl", "-s", "-m", "4", "http://localhost:12391/addresses/balance/YOUR_QORTAL_ADDRESS"]
    stdout: StdioCollector {
      onStreamFinished: {
        var b = parseFloat(String(text).trim())
        if (!isNaN(b) && b >= 0) {
          if (root.balance >= 0 && b > root.balance && root.height_ > 0) {
            // Payout (or incoming transfer) confirmed — flash ✦paid.
            root.lastPayoutHeight = root.height_
            root.lastPayoutAt = new Date()
            root.balance = b
            root.saveState()
          } else if (root.balance < 0) {
            // First baseline after a cold start — persist immediately so the
            // next restart can never swallow a payout that lands in between.
            root.balance = b
            root.saveState()
          } else {
            root.balance = b
          }
        }
      }
    }
  }

  implicitWidth: contentRow.implicitWidth + 20
  implicitHeight: Math.max(contentRow.implicitHeight, button.implicitHeight)

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.LeftButton) Quickshell.execDetached(["sh", "-c", "env DESKTOPINTEGRATION=1 \"$HOME/AppImages/qortal_hub.appimage\" --no-sandbox"])
    }

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: 7

      // The Qortal Q: ring + Q-tail + center disc
      Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 16
        implicitHeight: 16
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "transparent"
          border.color: root.ringColor
          border.width: 2.5
        }
        Rectangle {
          x: parent.width - 5.5
          y: parent.height - 4.5
          width: 7; height: 2.5; radius: 1.25
          color: root.ringColor
          rotation: 45
        }
        Rectangle {
          anchors.centerIn: parent
          width: 6.5; height: 6.5; radius: 3.25
          color: root.centerColor
        }
      }

      Text {
        Layout.alignment: Qt.AlignVCenter
        text: root.heightText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.weight: Font.DemiBold
      }

      Text {
        Layout.alignment: Qt.AlignVCenter
        visible: root.nodeUp
        text: root.payoutText
        color: (root.blocksLeft === 0 || root.justPaid) ? "#f5c542" : button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      // 2026-10-21: the estimated time to the next payout window — computed
      // since day one but never rendered until now. Measured block time,
      // self-correcting each refresh.
      Text {
        Layout.alignment: Qt.AlignVCenter
        visible: root.nodeUp && root.estText !== ""
        text: root.estText
        color: button.foreground
        opacity: 0.75
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }
  }
}
