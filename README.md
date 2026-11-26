**English** | [简体中文](README.zh-CN.md)

# Death Road to Canada · Cheat Trainer

> Version: **0.1.0** ｜ Game: **Death Road to Canada** (Steam release, tested on JUN-20-2024.10.25)

A trainer for the single-player game **Death Road to Canada** (Steam release).
It is built entirely from PowerShell scripts plus the game's built-in `deathforth` script engine: **no process injection, no save-file modification**.

- The panel UI is compiled and run in memory.
- Every effect exists only in the current game session and is fully reverted when you quit.
- Delete `deathforth\hack\hack.df` to return to vanilla.

## Supported game version

- Game: **Death Road to Canada** (Steam release)
- Tested version: **JUN-20-2024.10.25** (other versions may work, or may break if the script API changes)
- Windows only; requires the game's built-in `deathforth` folder and `boot.df`.

## Features and hotkeys

| Hotkey | Feature |
| --- | --- |
| `Ctrl+1` | Infinite resources: food / gas / medical up to 500, bullets / shotgun shells / rifle shells up to 300 |
| `Ctrl+2` | Full heal for the whole team |
| `Ctrl+3` | Weapons never break |
| `Ctrl+4` | Swinging weapons costs no stamina |
| `Ctrl+5` | One-hit kill |
| `Ctrl+6` | Indestructible vehicle: chassis and engine locked at max (immune to crashes / roadblocks / driving wear) |
| `Ctrl+0` | Enable everything at once (runs the six above in order) |

- All settings except `Ctrl+6` are idempotent and can be pressed repeatedly; press again after switching weapons.
- `Ctrl+6` is a toggle: press once to enable, press again to disable. For small-chassis cars it raises the durability cap to 8 so a single crash cannot destroy them.
- Hotkeys are delivered directly to the game window as window messages; **you do not need to open or close the in-game console**.

## Installation

1. Close the game first.
2. Double-click `install.bat` (if the game is under `Program Files`, you may need to right-click → "Run as administrator").
3. Seeing `Installed:` means success; saves are backed up to `backup\` automatically.
4. Restart the game once for it to take effect.

## Usage

1. Launch the game through Steam and reach the main menu.
2. Double-click `start-panel.bat` (or `启动面板.bat`).
3. When the panel reports a connected DR2C window, tick the features you want; ticked features are re-sent periodically.
4. You can also skip the panel and press `Ctrl+1..6` or `Ctrl+0` in-game.

> If double-clicking a `.bat` does nothing, right-click it and choose "Run as administrator".

## Uninstallation

1. Close the game first.
2. Double-click `uninstall.bat`. It removes only `deathforth\hack\hack.df`, returning the game to vanilla immediately. (The folder is removed as well if it becomes empty; other mod files inside it are left untouched.)
3. This tool never modifies saves; to restore the pre-install save, copy it back from `backup\`.

## About "untrusted script" warnings

- `.ps1` / `.bat` files downloaded from the internet carry the Mark-of-the-Web, so PowerShell / SmartScreen may warn that "this script is not trusted" and block execution. This is not a virus: right-click the file → Properties → tick "Unblock", or run `unblock.bat` (`解除锁定.bat`) to unblock everything at once.
- The scripts use `-ExecutionPolicy Bypass` only to temporarily bypass the local execution policy for this tool; they do not change the system-wide policy.

## Repository layout

```
dr2c-cheat/
├─ install.bat                 install (copies hack.df into the game folder and backs up saves)
├─ uninstall.bat               uninstall (removes only hack.df)
├─ start-panel.bat             launch the panel (English alias)
├─ 启动面板.bat                 launch the panel (original Chinese name, same content)
├─ unblock.bat                 remove the Mark-of-the-Web (English alias)
├─ 解除锁定.bat                 remove the Mark-of-the-Web (original Chinese name, same content)
├─ hack/
│  └─ hack.df                  in-game script, copied to deathforth\hack\ on install
├─ tools/
│  ├─ install.ps1              install logic
│  ├─ uninstall.ps1            uninstall logic
│  ├─ panel.ps1                WinForms panel (embedded C#, compiled in memory)
│  └─ unblock.ps1              batch unblock
├─ backup/                     save backups created on install (ignored by .gitignore)
├─ README.md                   English documentation (GitHub front page)
├─ README.zh-CN.md             Chinese documentation
├─ CHANGELOG.md                changelog
└─ LICENSE
```

## Disclaimer

- This tool is for **single-player / offline** use only. Do not use it in multiplayer, leaderboards, or any other online scenario.
- Please support the official game. You are responsible for any consequences such as save corruption, disabled achievements, crashes, or anything else caused by using this tool.
- This project is not affiliated with the game's developer, publisher, or Valve / Steam.
- This tool collects and uploads no data, and does not modify game save files.

## License

[MIT](LICENSE)
