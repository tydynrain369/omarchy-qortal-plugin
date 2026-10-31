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
// confirmed balance jump. Left-click opens your Qortal Hub (hubPath);
// right-click refreshes.
//
// Zero-config by default: the node's admin API port is read from the node's
// own settings.json and the monitored (minting) address from the node's own
// /admin/mintingaccounts endpoint. Both fall back sensibly, so the widget
// works out of the box against a standard local Qortal Core.
BarWidget {
  id: root
  moduleName: "io.github.tydynrain369.qortal-minting-node-status"

  // ---------- state ----------
  property var status: null
  property real balance: -1
  property real lastPayoutHeight: -1
  property date lastPayoutAt: new Date(0)
  property real height_: -1
  property real blockSeconds: 72          // measured average; refined each refresh
  property real anchorBlock: -1           // payout block used for the measurement

  // Left-click target: your own Qortal Hub executable. Defaults to the Omarchy
  // AppImage convention; point it anywhere (or at a launcher on PATH).
  readonly property string hubPath: Quickshell.env("HOME") + "/AppImages/qortal_hub.appimage"

  // ---------- auto-discovery (no config needed in the common case) ----------
  // Admin API port. Qortal writes only NON-default keys to settings.json, so a
  // missing "apiPort" means the default 12391. Read at startup (see settingsProc).
  property int nodePort: 12391
  readonly property string apiBase: "http://localhost:" + nodePort
  // Where the node core lives (only used to read settings.json).
  readonly property string settingsPath: Quickshell.env("HOME") + "/qortal/settings.json"

  // Monitored address (balance + the ✦paid indicator). Auto-filled from the
  // node's minting account; leave fallbackAddress empty for full auto-detection,
  // or set it to YOUR OWN Qortal address to override (e.g. watch another wallet).
  property string monitoredAddress: ""
  readonly property string fallbackAddress: ""

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
    if (monitoredAddress !== "") balanceProc.running = true
    else mintAcctProc.running = true          // keep probing until discovered
  }

  // Parse the node's settings.json for a non-default apiPort, then discover the
  // minting account. Robust to a missing/invalid file (port stays 12391).
  function applySettings(txt) {
    try {
      var s = JSON.parse(txt)
      if (s && s.apiPort > 0 && s.apiPort < 65536) root.nodePort = s.apiPort
    } catch (e) {}
    mintAcctProc.running = true
  }

  // The node reports its OWN minting account — no key, no config. An empty
  // answer (no minting account configured) falls back to fallbackAddress.
  function applyMintingAccounts(txt) {
    try {
      var a = JSON.parse(txt)
      if (a && a.length > 0) {
        var m = a[0].recipientAccount || a[0].mintingAccount || ""
        if (m !== "") root.monitoredAddress = m
      }
    } catch (e) {}
    if (root.monitoredAddress === "" && fallbackAddress !== "")
      root.monitoredAddress = fallbackAddress
    if (root.monitoredAddress !== "") balanceProc.running = true
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

  // Discover port + minting address, then start polling.
  Component.onCompleted: { settingsProc.running = true; refresh() }

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

  // Read the node's settings.json for a non-default API port. Always fires
  // onStreamFinished (even on a missing file), so discovery never stalls.
  Process {
    id: settingsProc
    command: ["sh", "-c", "cat \"" + root.settingsPath + "\" 2>/dev/null || true"]
    stdout: StdioCollector { onStreamFinished: root.applySettings(text) }
  }

  // Discover the minting account straight from the node — no API key required
  // when apiRestricted is false.
  Process {
    id: mintAcctProc
    command: ["curl", "-s", "-m", "4", root.apiBase + "/admin/mintingaccounts"]
    stdout: StdioCollector { onStreamFinished: root.applyMintingAccounts(text) }
  }

  Process {
    id: statusProc
    command: ["curl", "-s", "-m", "4", root.apiBase + "/admin/status"]
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
            payoutProc.command = ["curl", "-s", "-m", "4", root.apiBase + "/blocks/byheight/" + P]
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
    command: ["curl", "-s", "-m", "4", root.apiBase + "/addresses/balance/" + root.monitoredAddress]
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
      // Launch Hub with its OWN sandbox intact: never add --no-sandbox here, it
      // disables the renderer sandbox for every Hub process and webview.
      else if (b === Qt.LeftButton) Quickshell.execDetached(["sh", "-c", "env DESKTOPINTEGRATION=1 \"" + root.hubPath + "\""])
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
