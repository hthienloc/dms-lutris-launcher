# Lutris Launcher

Browse and launch your Lutris games from the bar.

<img src="screenshot.png" width="400" alt="Screenshot">

## Install


**Required:** This plugin requires [dms-common](https://github.com/hthienloc/dms-common) to be installed.

```bash
# 1. Install shared components
git clone https://github.com/hthienloc/dms-common ~/.config/DankMaterialShell/plugins/dms-common

# 2. Install this plugin
dms://plugin/install/lutrisLauncher
```

Or manually:
```bash
git clone https://github.com/hthienloc/dms-lutris-launcher ~/.config/DankMaterialShell/plugins/lutrisLauncher
```

## Features

- **Game grid** - Visual cover art display
- **Sort & filter** - By name, recently played, most played
- **Favorites & blacklist** - Organize your library
- **Launch stats** - Track play time and last played

## Usage

| Action | Result |
|--------|--------|
| Left click | Launch game |
| Right click | Show stats & hide option |

## Requirements

- `lutris` - Game launcher CLI

## License

GPL-3.0

## Roadmap / TODO

- [ ] **Runner Badges**: Display small icons on game covers to identify the runner (Wine, Steam, RetroArch, etc.).
- [ ] **SteamGridDB Integration**: Automatically fetch high-quality cover art from SteamGridDB for games missing local assets.
- [ ] **Active Game Tracking**: Show a special "Now Playing" state on the bar when a game is running, including time elapsed.
- [ ] **Process Management**: Add a "Force Quit" option to the right-click menu for active games.
- [ ] **Custom Grid Sizes**: Allow users to adjust the size and spacing of the game grid in the popout.
