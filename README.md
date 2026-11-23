# quattro-hypr

Minimal [Hyprland](https://hypr.land/) desktop configuration and Quickshell environment for Arch Linux.

![showcase.webp](showcase.webp)

## Directory layout

- `config/` - user dotfiles (`hypr`, `foot`, `btop`, `tmux`, `starship.toml`, `satty`, `brave-origin-flags.conf`)
- `default/` - runtime defaults (bash setup, Hyprland Lua modules, theme templates, systemd user units, SDDM theme, fonts)
- `bin/` - `quattro-*` helper scripts
- `shell/` - Quickshell configuration (bar, dock, launcher, panels, notifications, lockscreen)
- `themes/` - 8 curated color schemes (`Tokyo Night`, `Catppuccin`, `Catppuccin Latte`, `Gruvbox`, `Kanagawa`, `Nord`, `Rose Pine`, `Matte Black`)
- `applications/` - core `.desktop` entries and icons
- `etc/` - system config files (`fastfetch`, `mpv`, `xkb`, `profile.d`, `sddm.conf.d`, `sudoers.d`)
- `packages/` - core Arch package list ([arch-core.packages](packages/arch-core.packages))
- `install.sh` - single-command installer (deploys packages, runtime, configs, theme, and system integration)
- `verify.sh` - checks script syntax, Lua compilation, JSON/XML configs, CLI routes, hygiene, pacman package names, and sandbox install

## Install

Check script syntax, Lua files, and package names without touching the system:

```bash
./verify.sh
```

Run the installer (installs core packages, runtime, user configs, initial `Tokyo Night` theme, and system integration):

```bash
./install.sh
```

Existing user files in `~/.config` and `~/.bashrc` are overwritten directly without creating backups.

## Starting the session

Log in via SDDM (choose **Quattro (Hyprland uwsm)**), or start it from a TTY:

```bash
uwsm start hyprland.desktop
```

## Notes

- `QUATTRO_PATH` resolves `~/.local/share/quattro` before `/usr/share/quattro`, so user-only installs work cleanly.
- Standard Arch components are used throughout (`nautilus` for files, `foot` for terminal, `grim` + `slurp` + `satty` for screenshots, `qt6ct` for Qt6 theming, `quattro.screensaver` for screensaver, and `quattro-share-picker` for screen sharing).
- Existing terminal configs and browser flag files (`brave-origin-flags.conf`) are self-contained under `$HOME`.
