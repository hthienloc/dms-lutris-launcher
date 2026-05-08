# DMS Lutris Plugin

A plugin for DankMaterialShell (DMS) that allows you to list and launch your installed Lutris games directly from the shell bar with a beautiful grid interface.

<img src="screenshot.png" width="400" alt="Screenshot">

## Features
- **Grid Layout**: Displays your game library in a 4-column grid.
- **Game Covers**: Shows official cover art for each game.
- **Direct Launch**: Circular "Play" icon on each card for quick launching via Lutris URI.
- **Auto-Sync**: Automatically fetches and cleans the Lutris game list on initialization.
- **Optimized UI**: Clean typography and consistent spacing following the DMS theme.

## Requirements
- `lutris` CLI must be installed (`/usr/bin/lutris`).
- Quickshell and DMS framework.

## Installation
1. Copy the `dms-lutris` folder to your DMS plugins directory:
   ```bash
   cp -r dms-lutris ~/.config/DankMaterialShell/plugins/
   ```
2. Restart DMS or reload plugins.

## Technical Details
The plugin uses `lutris -l -o -j` to fetch installed games. It includes a custom data cleaning layer to handle inconsistent CLI output from Lutris (interleaved logs and JSON).

## License
GNU GPLv3
