# Qortal Node — Omarchy Bar Widget

A Quickshell bar widget for Omarchy that shows your Qortal blockchain node's sync, minting, and payout status. The old KDE tray applet, reborn for Omarchy.

## Features

- **Color-coded Q-logo**: Red = not synced (or node down), Blue = synced, Blue ring + gold center = synced and minting
- **Block height**: Live chain height from the admin API
- **Payout countdown**: Deterministic — every 1000th block is a payout block, so the countdown is `next multiple of 1000 − height`
- **Measured ETA**: Uses the real average block time measured since the last payout block (self-correcting each refresh)
- **Payout indicators**: `✦hunt` on the payout block itself, `✦paid` for a few blocks after a confirmed balance jump
- **Auto-hide**: The widget vanishes when the node is down
- **Click**: Opens the Qortal Hub GUI
- **Right-click**: Refreshes status immediately

## Installation

### From the Omarchy Plugin Registry

```bash
omarchy plugin add https://github.com/tydynrain369/omarchy-qortal-plugin.git --enable
```

### Manual

```bash
git clone https://github.com/tydynrain369/omarchy-qortal-plugin.git ~/.config/omarchy/plugins/qortal.node
omarchy restart shell
```

## Configuration

The widget auto-detects the Qortal data directory in this order:

1. `$QORTAL_HOME` environment variable (if set)
2. `~/qortal` (the default location)
3. `~/Applications/qortal` (common custom location)
4. `~/.config/qortal` (alternative custom location)

The Qortal Hub AppImage path is resolved in this order:

1. `$QORTAL_HUB_APPIMAGE` environment variable (if set)
2. `~/AppImages/qortal_hub.appimage`
3. `~/Applications/qortal-hub/qortal-hub.appimage`
4. `~/qortal/qortal-hub.appimage`

The monitoring address (for balance/payout detection) is optional. If you want balance tracking, set it in the widget's config:

```bash
echo 'QORTAL_MONITOR_ADDRESS=YOUR_QORTAL_ADDRESS' > ~/.config/omarchy/plugins/qortal.node/config
```

Without a monitoring address, the widget still shows sync/minting/payout status — it just won't flash `✦paid` on balance changes.

## API Requirements

The widget connects to the Qortal admin API on `http://localhost:12391`. Make sure:

- `apiRestricted` is `false` in your `settings.json`
- The API port is the default `12391` (changeable in settings.json if needed)

## Removing

```bash
omarchy plugin remove qortal.node
```

## License

MIT — see [LICENSE](LICENSE).