# Noctalia Share Indicator

Bar widget that shows when a PipeWire screen-share / xdg-desktop-portal capture session is active.

---
title: Share Indicator
author: hmanzano
version: v0.2.0
last_updated: 2026-07-23
---

## Overview

Headless service polls `pw-dump`, detects portal / `Stream/Input/Video` capture nodes (excluding cameras), and publishes status. Bar widget stays hidden while idle and shows a primary capsule while sharing. Optional `auto_dnd` enables notification Do Not Disturb for the share session.

## Architecture

- `share-indicator/service.luau` — polls PipeWire, writes `noctalia.state.status`, optional DND ownership
- `share-indicator/widget.luau` — watches status, primary color + white glyph
- Addressed as `hmanzano/share-indicator:indicator` (widget) and `hmanzano/share-indicator:service` (service)

<!-- Diagram Placeholder
Type: Architecture
Purpose: Show service → state → widget data flow
Scope: share-indicator plugin
Description: service polls pw-dump, publishes sharing/apps on noctalia.state; widget watches and renders bar glyph; optional auto_dnd toggles notification DND with ownership
Tool Suggestion: Mermaid
Status: pending
Last Updated: 2026-07-23
-->
*Caption:* Diagram will show service polling PipeWire and feeding the bar widget through shared plugin state.

## Setup

Requires Noctalia ≥ `5.0.0` and `pw-dump` on `PATH`.

### Path source (recommended for development)

This repo is a **plugin source** (one or more plugins in subdirectories). Register the repo root, then enable:

```bash
noctalia msg plugins source add share-dev path /home/hmanzano/Repositories/noctalia-share-indicator
noctalia msg plugins enable hmanzano/share-indicator
```

Confirm it appears:

```bash
noctalia msg plugins list | rg share-indicator
```

Then add bar widget type `hmanzano/share-indicator:indicator`.

### Local data-dir drop-in

Copy (do **not** symlink) the inner plugin directory:

```bash
mkdir -p ~/.local/share/noctalia/plugins
cp -a share-indicator ~/.local/share/noctalia/plugins/share-indicator
noctalia msg plugins enable hmanzano/share-indicator
```

Symlinks into the local plugins dir are not discovered reliably on Noctalia 5.0.0.

## Usage

- Idle → widget hidden
- Active share (browser, Discord, Zen, …) → primary color + white glyph (readable without capsule)
- Click → notification lists capturing app names
- Settings → Plugins: poll interval, glyph, auto Do Not Disturb (off by default)

### Auto Do Not Disturb

When `auto_dnd` is on:

- Share start → enable DND only if it was off; plugin takes ownership
- Share stop → disable DND only if this plugin enabled it
- If DND was already on before sharing → leave it alone afterwards
- Disable/reload mid-share while owning DND → force DND off (`onExit`)

Stop transitions debounce ~1s so brief `pw-dump` gaps do not flap DND.

IPC smoke test:

```bash
noctalia msg plugin hmanzano/share-indicator:service all refresh
```

## Environment Variables

None.

## Testing

1. Start a Wayland portal screen share (e.g. Zen / Discord)
2. Confirm primary-colored glyph appears on the bar
3. Click → notification lists apps
4. Stop share → widget hides
5. Confirm webcam-only use does **not** show the widget
6. Enable `auto_dnd`, share again → DND on; stop → DND off (unless it was already on)

Optional fixture check while sharing:

```bash
pw-dump -i 0 > /tmp/pw-share.json
```

## Folder Structure

```
.
├── catalog.toml
├── README.md
└── share-indicator/
    ├── plugin.toml
    ├── service.luau
    ├── widget.luau
    └── translations/
        └── en.json
```

## Dependencies

- Noctalia ≥ 5.0.0 (`min_noctalia`)
- PipeWire (`pw-dump`)

## Versioning

Current: `0.2.0`

## Authors & Contributors

- hmanzano

## License

MIT
