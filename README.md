# Qortal Node — Omarchy Bar Widget

A Quickshell bar widget for Omarchy that shows your Qortal blockchain node's sync, minting, and payout status. The old KDE tray applet, reborn for Omarchy.

## Features

All behavior below is implemented in `BarWidget.qml`:

- **Color-coded Q-logo**: Red = not synced (or node down), Blue = synced, Blue ring + gold center = synced and minting
- **Block height**: Live chain height from the admin API, refreshed every 30 s
- **Payout countdown**: Deterministic — every 1000th block is a payout block, so the countdown is `next multiple of 1000 − height`
- **Measured ETA**: Uses the real average block time measured since the last payout block (self-correcting each refresh)
- **Payout indicators**: `✦hunt` on the payout block itself, `✦paid` for a few blocks after a confirmed balance jump
- **Auto-hide**: The widget vanishes when the node is down
- **Click**: Opens the Qortal Hub GUI
- **Right-click**: Refreshes status immediately
- **State persistence**: Balance baseline and last payout are saved to `~/.local/state/omarchy/qortal-widget.json` so restarts never miss a payout that landed in between

## Installation

### From the Omarchy Plugin Registry

```bash
omarchy plugin add https://github.com/tydynrain369/omarchy-qortal-plugin.git --enable
```

### Manual

The manifest id is `qortal.node`, and the plugin directory name must match it:

```bash
git clone https://github.com/tydynrain369/omarchy-qortal-plugin.git ~/.config/omarchy/plugins/qortal.node
omarchy restart shell
```

## Configuration

There is no config file — the widget's knobs are constants in `BarWidget.qml`:

| What | Where | Default |
|---|---|---|
| Admin API port | `BarWidget.qml` (all `curl` commands) | `http://localhost:12391` |
| Monitored address (balance/`✦paid` detection) | `BarWidget.qml`, `balanceProc.command` | `YOUR_QORTAL_ADDRESS` |
| Qortal Hub AppImage path (left-click action) | `BarWidget.qml`, `onPressed` | `$HOME/AppImages/qortal_hub.appimage` |
| Refresh interval | `BarWidget.qml`, `Timer` | 30 s |

Edit those lines directly and run `omarchy restart shell` to apply. Without a valid monitored address the widget still shows sync/minting/payout status — it just won't flash `✦paid` on balance changes.

## API Requirements

The widget connects to the Qortal admin API on `http://localhost:12391`. Make sure:

- `apiRestricted` is `false` in your `settings.json`
- The API port is the default `12391` (change it in `BarWidget.qml` if yours differs)

No local paths are hardcoded: the widget talks only to this HTTP API, so your
Qortal core node can live anywhere (its default install location is `~/qortal`).
The left-click opens **Qortal Hub** — the desktop UI, which is separate from the
node itself — resolved as `$HOME/AppImages/qortal_hub.appimage`, the Omarchy
default AppImage location.

## Removing

```bash
omarchy plugin remove qortal.node
```

## License

MIT — see [LICENSE](LICENSE).
