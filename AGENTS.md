# AGENTS.md

Contributor and maintainer reference for `quattro-hypr` and `quattro-shell`.

## Repository layout

- `bin/` - `quattro` CLI router and `quattro-*` executables. Every script directly in `bin/` must be `+x`, include `# quattro:summary=...` metadata headers when routed, and enable strict mode (`set -eo pipefail` or `set -euo pipefail`) for Bash scripts or `#!/usr/bin/env -S python3 -B` for Python scripts.
- `config/` - user dotfiles deployed to `~/.config/` (`hypr`, `quattro/shell.json`, `quattro/extensions/quattro-menu.jsonc`, `foot`, `btop`, `tmux`, `git`, `imv`, `lazygit`, `satty`, `wireplumber`, `xdg-desktop-portal`, `starship.toml`, `hyprland-mimeapps.list`, `brave-origin-flags.conf`).
- `default/` - runtime defaults deployed to `~/.local/share/quattro/default/`:
  - `bash/` & `bashrc` - interactive shell chain (`envs`, `env-bootstrap`, `init`, `completions`, `lib-common.sh`, `lib-shell-config.sh`, `fns/`).
  - `hypr/` - Hyprland Lua modules (`bootstrap.lua`, `quattro.lua`, `require_all.lua`, `helpers.lua`, `monitor-workspaces.lua`, `qconsole.lua`, `toggles.lua`, `workspace-layouts.lua`, `bindings/`, `apps/`, `toggles/`) and `titlebars/` C++ compositor plugin (`main.cpp`, `barDeco.hpp`, `barDeco.cpp`, `appName.cpp`).
  - `quattro/` - default menu definition (`quattro-menu.jsonc`), global shortcuts (`shortcuts`), and hidden desktop IDs (`launcher.hides`).
  - `themed/` - templates rendered into `~/.local/state/quattro/current/theme/` by `bin/quattro-theme-set*`.
  - `i18n/` - translation catalogs (`<code>/cli.json`, `<code>/shell.json`, `<code>/menu.json`, `locales.json`, `plural.jq`).
  - `input-methods/`, `sddm/`, `systemd/`, `uwsm/`, `fontconfig/`, `fonts/`, `gtk/`, `xcompose/`.
- `shell/` - Quickshell desktop environment (`shell.qml` host, standalone `screensaver.qml` and `share-picker.qml`, `Commons/`, `Ui/`, `services/`, and first-party `plugins/`).
- `themes/` - 10 curated themes (`catppuccin`, `catppuccin-latte`, `everforest`, `gruvbox`, `kanagawa`, `matte-black`, `nord`, `rose-pine`, `solitude`, `tokyo-night`).
- `applications/` - Quattro `.desktop` entries and SVG icons.
- `etc/` - system-level configs (`fastfetch`, `mpv`, `profile.d`, `sddm.conf.d`, `sudoers.d`, `systemd`, `tmpfiles.d`, `xkb`).
- `packages/arch-core.packages` - official Arch Linux `[core]` / `[extra]` package list.
- `install.sh`, `uninstall.sh`, `verify.sh` - single-command installer, uninstaller, and automated verification suite.

## Runtime & paths

- `QUATTRO_PATH` resolves `~/.local/share/quattro` first and falls back to `/usr/share/quattro`. Never hardcode `/home/<user>`; always read `$QUATTRO_PATH` in shell/Lua or `Util.quattroPath` / `shell.quattroPath` in QML.
- Quickshell launches with `QS_DISABLE_FILE_WATCHER=1` (`bin/quattro-launch-shell`) to avoid idle `inotify` overhead:
  - Reload plugin QML/manifests: `quattro-shell shell rescanPlugins`
  - Reload `shell.json`: `quattro-shell shell reloadConfig`
  - Restart full host (`shell.qml`, `Commons/`, `Ui/`, `services/`): `quattro-restart-shell`

## Performance & hygiene conventions

1. **Bash scripts & CLI hot paths**:
   - Avoid subshell forks (`$(dirname ...)`, `$(basename ...)`, `$(cat ...)`, `$(date ...)`, `wc`, `cut`, `tr`, `awk`, `sed`) in loops and hotkey paths; use Bash parameter expansion, `IFS= read -r`, `printf -v ... '%(%s)T' -1`, `$EPOCHREALTIME`, and `REPLY`-returning helper functions.
   - Batch IPC and package queries: use `hyprctl --batch` for multi-dispatch sequences, `hyprctl --batch -j` + single `@tsv` `jq` reads for compositor state, and single `pacman -Qq "${pkgs[@]}"` calls instead of per-package loops.
   - Keep pure-Bash fast paths in `bin/quattro-theme-color` (integer hex mixing), `bin/quattro-i18n` (English catalog lookup), and `bin/quattro-osd` bit-identical to fallback behavior.
   - Keep `.bashrc` startup idempotent (`_quattro_env_bootstrapped` guard) and mtime-cached (`~/.cache/quattro/bash-init/` for `starship` and `zoxide`).

2. **Python bytecode hygiene**:
   - Always pass `-B` (`#!/usr/bin/env -S python3 -B` or `python3 -B`) so `__pycache__/` and `*.pyc` files are never generated inside `bin/`, `default/`, or the repository tree.

3. **Hyprland Lua & C++ titlebars**:
   - Guard `package.path` prepends with plain-substring checks so `hyprctl reload` stays idempotent and preserves priority (`XDG_STATE_HOME` -> `XDG_CONFIG_HOME` -> `QUATTRO_PATH`).
   - Only write watched state files (`monitors`, `workspaces`) when serialized content actually changes on disk.
   - Compile C++ titlebars with `-O2` (`bin/quattro-build-titlebars`), keep `.desktop` lookups `O(1)` via `std::unordered_map`, cache `m_szLastAppID` / `m_szLastRawTitle` in `renderPass`, and early-exit `damageOnButtonHover()` when buttons are not visible.

4. **Quickshell QML & JS models**:
   - Always alias `import qs.Commons as Commons` and qualify `Commons.Color.*` (Qt 6 defines its own `Color` type).
   - Never re-import `services/` by relative path inside plugins; use injected `shell`, `pluginRegistry`, `barWidgetRegistry`, and `appLibrary` properties.
   - Set `textFormat: Text.PlainText` on any `Text` displaying external or user-provided strings.
   - Wrap animation durations in `Style.duration(ms)` so `Style.reduceMotion` is honored.
   - Never attach cache fields onto C++ `QObject` wrappers (`DesktopEntry`, `WifiNetwork`) or mutate nested objects already stored in QML `property var`. Pre-stamp search tokens (`_nameSearch`, `_labelLower`, `_descWords`) on fresh plain JS objects before assignment, use `MenuModel.childrenByParent` (`O(1)`) for menu visibility/counts, and lazy-bind `FileView.path` for large static JSON catalogs in `keepLoaded` overlays (such as `emojis.json`).

## IPC & CLI entry points

```bash
quattro --help
quattro commands --check
quattro-shell shell ping
quattro-shell shell listPlugins
quattro-shell shell summon quattro.clock '{}'
quattro-shell shell toggle quattro.menu '{"menu":"root"}'
quattro-shell shell reloadConfig
quattro-shell shell rescanPlugins
```

## Verification

Run the full verification suite after any script, config, Lua, theme, or shell change:

```bash
./verify.sh
```

`./verify.sh` validates Bash syntax & executable bits, batched Python AST parsing, `luac -p` bytecode compilation, JSON/JSONC/XML validity, CLI route metadata (`quattro commands --check`), `quattro-menu.jsonc` command references, strict mode in `bin/`, git-history checks for removed `quattro-*` commands, `pacman -Ssq` resolution for `packages/arch-core.packages`, and an isolated `QUATTRO_INSTALL_SANDBOX=1 ./install.sh` deployment + theme render test.
