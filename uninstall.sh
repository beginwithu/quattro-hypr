#!/bin/bash

set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

ASSUME_YES=false
KEEP_PACKAGES=false

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [OPTIONS]

Completely removes Quattro from the system: user runtime, CLI symlinks,
dotfiles/configs, themes, icons, fonts, state/cache, system-wide configs,
SDDM theme, sudoers/PAM/alpm rules, core packages, and CachyOS repos.

Options:
  -y, --yes            Skip interactive confirmation prompt
      --keep-packages  Keep installed pacman packages and CachyOS repos
  -h, --help           Show this help message
EOF
}

while (( $# > 0 )); do
  case "$1" in
    -y|--yes) ASSUME_YES=true ;;
    --keep-packages) KEEP_PACKAGES=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

SANDBOX=false
if [[ ${QUATTRO_UNINSTALL_SANDBOX:-0} == "1" ]]; then
  SANDBOX=true
elif (( EUID == 0 )); then
  echo "Run ./uninstall.sh as your normal user (it will prompt for sudo when needed), not as root." >&2
  exit 1
fi

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
INSTALL_DIR="$DATA_HOME/quattro"
BIN_LINK_DIR="$HOME/.local/bin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

_TMP_FILES=()
cleanup_tmp_files() {
  if (( ${#_TMP_FILES[@]} > 0 )); then
    rm -f "${_TMP_FILES[@]}"
  fi
}
trap cleanup_tmp_files EXIT

# Remove a directory only if it exists and is empty.
prune_empty_dir() {
  local dir="$1"
  [[ -d $dir && ! -L $dir ]] && rmdir --ignore-fail-on-non-empty "$dir" 2>/dev/null || true
}

sudo_prune_empty_dir() {
  local dir="$1"
  sudo test -d "$dir" && ! sudo test -L "$dir" && sudo rmdir --ignore-fail-on-non-empty "$dir" 2>/dev/null || true
}

confirm_uninstall() {
  $ASSUME_YES && return 0

  echo -e "${RED}================================================================${NC}"
  echo -e "${RED}  WARNING: COMPLETE QUATTRO UNINSTALL${NC}"
  echo -e "${RED}================================================================${NC}"
  echo ""
  echo "This will permanently remove:"
  echo "  - Quattro runtime, state, cache & CLI symlinks:"
  echo "      $INSTALL_DIR"
  echo "      $STATE_HOME/quattro"
  echo "      $CACHE_HOME/quattro"
  echo "      $BIN_LINK_DIR/quattro*"
  echo "  - User configs deployed by Quattro:"
  echo "      $CONFIG_HOME/{hypr,foot,btop,git,imv,lazygit,quattro,satty,tmux,qt6ct}"
  echo "      $CONFIG_HOME/{starship.toml,brave-origin-flags.conf,hyprland-mimeapps.list}"
  echo "      Quattro GTK CSS blocks, XKB/mpv/fastfetch/fontconfig/environment.d/systemd units"
  echo "      Quattro ~/.bashrc (restored from /etc/skel/.bashrc if available) & ~/.XCompose"
  echo "      Quattro desktop entries, icons, fonts, and VS Code theme extension"
  if ! $SANDBOX; then
    echo "  - System-wide integration (requires sudo):"
    echo "      /usr/bin/quattro-*, /usr/share/quattro, /usr/lib/quattro-hyprland-titlebars"
    echo "      /usr/share/sddm/themes/silent, /etc/sddm.conf.d/*, /etc/sudoers.d/*quattro*"
    echo "      /etc/pam.d/quattro-*, /etc/profile.d/quattro.sh, /usr/share/uwsm/env.d/10-quattro"
    echo "      /usr/share/libalpm/hooks/90-quattro-titlebars-rebuild.hook"
    echo "      /etc/brave/policies/managed/*, /etc/fastfetch, /etc/mpv, /etc/xkb, /var/lib/quattro"
    if ! $KEEP_PACKAGES; then
      echo -e "  - ${YELLOW}ALL packages in packages/arch-core.packages (pacman -Rns):${NC}"
      echo "      hyprland, quickshell, sddm, uwsm, foot, nautilus, brave-origin-bin,"
      echo "      networkmanager, pipewire, wireplumber, neovim, tmux, yay, etc."
      echo "  - CachyOS repositories in /etc/pacman.conf, mirrorlists, keyring & GPG key"
      echo "      (skipped automatically if running native CachyOS)"
    fi
  fi
  echo ""
  echo -e "${YELLOW}Personal directories (~/Downloads, ~/Documents, ~/Projects, ~/Pictures, ~/Videos) will NOT be touched.${NC}"
  echo ""

  if [[ ! -t 0 ]]; then
    echo "Non-interactive shell detected. Re-run with --yes to confirm uninstall." >&2
    exit 1
  fi

  local reply
  read -r -p "Proceed with complete uninstall? [y/N] " reply || reply=""
  if [[ ! $reply =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
  fi
}

stop_user_services() {
  echo "==> Stopping and disabling Quattro user services..."

  if ! $SANDBOX && command -v systemctl >/dev/null 2>&1; then
    local unit
    for unit in \
      quattro-sleep-lock.service \
      quattro-recover-internal-monitor.service \
      bt-agent.service; do
      systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
    done
  fi

  if ! $SANDBOX; then
    # Stop background Quattro shell/daemons without killing the active terminal or Hyprland session.
    pkill -u "$USER" -x quickshell >/dev/null 2>&1 || true
    pkill -u "$USER" -f 'quattro-system-sleep-monitor' >/dev/null 2>&1 || true

    local runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
    rm -f \
      "$runtime_dir"/quattro-theme-set.lock \
      "$runtime_dir"/quattro-theme-set-retint.lock \
      "$runtime_dir"/quattro-*.lock \
      2>/dev/null || true
  fi
}

remove_user_runtime() {
  echo "==> Removing Quattro runtime, symlinks, state, and cache..."

  rm -rf "$INSTALL_DIR"
  rm -rf "$STATE_HOME/quattro"
  rm -rf "$CACHE_HOME/quattro"
  rm -rf "$CACHE_HOME/quickshell"
  rm -rf "$CACHE_HOME/hyprland"
  rm -f "$CACHE_HOME/xdg-terminal-exec"

  if [[ -d $BIN_LINK_DIR ]]; then
    rm -f "$BIN_LINK_DIR/quattro"
    local link
    for link in "$BIN_LINK_DIR"/quattro-*; do
      [[ -e $link || -L $link ]] && rm -f "$link"
    done

    # Also remove any symlink in BIN_LINK_DIR pointing into Quattro runtime directories.
    local target
    for link in "$BIN_LINK_DIR"/*; do
      [[ -L $link ]] || continue
      target=$(readlink "$link" 2>/dev/null || true)
      if [[ $target == "$INSTALL_DIR/"* || $target == "/usr/share/quattro/"* ]]; then
        rm -f "$link"
      fi
    done

    prune_empty_dir "$BIN_LINK_DIR"
  fi
}

strip_managed_gtk_blocks() {
  local gtk_css="$1"
  [[ -f $gtk_css ]] || return 0

  local tmp
  tmp=$(mktemp)
  _TMP_FILES+=("$tmp")
  awk '
    /^\/\* quattro-theme begin \*\// { skip = 1; next }
    skip && /^\/\* quattro-theme end \*\// { skip = 0; next }
    /^\/\* quattro-glass begin/ { skip = 1; next }
    skip && /^\/\* quattro-glass end \*\// { skip = 0; next }
    skip { next }
    { print }
  ' "$gtk_css" >"$tmp"

  if [[ ! -s $tmp ]] || ! grep -q '[^[:space:]]' "$tmp"; then
    rm -f "$tmp" "$gtk_css"
  else
    mv -f "$tmp" "$gtk_css"
  fi
}

clean_vscode_extensions() {
  local ext_base ext_dir extensions_file obsolete_file tmp
  for ext_base in \
    "$HOME/.vscode/extensions" \
    "$HOME/.vscode-insiders/extensions" \
    "$HOME/.vscode-oss/extensions"; do
    ext_dir="$ext_base/quattro-theme"
    rm -rf "$ext_dir"

    extensions_file="$ext_base/extensions.json"
    if [[ -f $extensions_file ]] && command -v jq >/dev/null 2>&1; then
      tmp=$(mktemp)
      _TMP_FILES+=("$tmp")
      if jq 'map(select(.identifier.id != "local.quattro-theme"))' "$extensions_file" >"$tmp" 2>/dev/null; then
        mv -f "$tmp" "$extensions_file"
      else
        rm -f "$tmp"
      fi
    fi

    obsolete_file="$ext_base/.obsolete"
    if [[ -f $obsolete_file ]] && command -v jq >/dev/null 2>&1; then
      tmp=$(mktemp)
      _TMP_FILES+=("$tmp")
      if jq 'with_entries(select(.key | startswith("local.quattro-theme-") | not))' "$obsolete_file" >"$tmp" 2>/dev/null; then
        mv -f "$tmp" "$obsolete_file"
      else
        rm -f "$tmp"
      fi
    fi
  done
}

remove_user_configs() {
  echo "==> Removing user configs from $CONFIG_HOME and $HOME..."

  # Remove all top-level config directories and files deployed from config/
  # (handle shared directories like wireplumber and xdg-desktop-portal granularly).
  local entry name target
  for entry in "$PROJECT_DIR"/config/* "$PROJECT_DIR"/config/.*; do
    name="${entry##*/}"
    [[ $name == "." || $name == ".." ]] && continue
    [[ -e $entry ]] || continue
    target="$CONFIG_HOME/$name"

    case "$name" in
      wireplumber)
        rm -f "$CONFIG_HOME/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf"
        prune_empty_dir "$CONFIG_HOME/wireplumber/wireplumber.conf.d"
        prune_empty_dir "$CONFIG_HOME/wireplumber"
        ;;
      xdg-desktop-portal)
        rm -f "$CONFIG_HOME/xdg-desktop-portal/hyprland-portals.conf"
        prune_empty_dir "$CONFIG_HOME/xdg-desktop-portal"
        ;;
      *)
        rm -rf "$target"
        ;;
    esac
  done

  # Remove additional user configs deployed by install.sh and theme helpers
  rm -f \
    "$CONFIG_HOME/environment.d/20-quattro-path.conf" \
    "$CONFIG_HOME/environment.d/90-gcr-ssh-agent.conf" \
    "$CONFIG_HOME/uwsm/env.d/10-quattro" \
    "$CONFIG_HOME/xdg-terminal-exec/hyprland-xdg-terminals.list" \
    "$CONFIG_HOME/fontconfig/conf.d/50-quattro.conf" \
    "$CONFIG_HOME/xkb/rules/evdev" \
    "$CONFIG_HOME/xkb/symbols/quattro" \
    "$CONFIG_HOME/mpv/mpv.conf" \
    "$CONFIG_HOME/fastfetch/config.jsonc" \
    "$CONFIG_HOME/qt6ct/qt6ct.conf"

  # Remove user systemd units installed from default/systemd/user/
  local unit_file
  for unit_file in "$PROJECT_DIR"/default/systemd/user/*.service; do
    [[ -f $unit_file ]] && rm -f "$CONFIG_HOME/systemd/user/${unit_file##*/}"
  done
  rm -f \
    "$CONFIG_HOME/systemd/user/bt-agent.service" \
    "$CONFIG_HOME/systemd/user/quattro-recover-internal-monitor.service" \
    "$CONFIG_HOME/systemd/user/quattro-sleep-lock.service"

  # Strip managed GTK theme and glass blocks
  strip_managed_gtk_blocks "$CONFIG_HOME/gtk-3.0/gtk.css"
  strip_managed_gtk_blocks "$CONFIG_HOME/gtk-4.0/gtk.css"

  # Clean Quattro-pinned default entries from GTK3 bookmarks without touching custom ones
  local gtk_bookmarks="$CONFIG_HOME/gtk-3.0/bookmarks"
  if [[ -f $gtk_bookmarks ]]; then
    local tmp
    tmp=$(mktemp)
    _TMP_FILES+=("$tmp")
    awk -v home="$HOME" '
      $0 == "file://" home "/Downloads Downloads" ||
      $0 == "file://" home "/Documents Documents" ||
      $0 == "file://" home "/Projects Projects" ||
      $0 == "file://" home "/Pictures Pictures" ||
      $0 == "file://" home "/Videos Videos" { next }
      { print }
    ' "$gtk_bookmarks" >"$tmp"
    if [[ ! -s $tmp ]] || ! grep -q '[^[:space:]]' "$tmp"; then
      rm -f "$tmp" "$gtk_bookmarks"
    else
      mv -f "$tmp" "$gtk_bookmarks"
    fi
  fi

  # Remove mimeapps.list if it was seeded by Quattro
  if [[ -f $CONFIG_HOME/mimeapps.list ]]; then
    if cmp -s "$CONFIG_HOME/mimeapps.list" "$PROJECT_DIR/default/applications/mimeapps.list" 2>/dev/null ||
      grep -q 'quattro-launch-editor\.desktop' "$CONFIG_HOME/mimeapps.list" 2>/dev/null; then
      rm -f "$CONFIG_HOME/mimeapps.list"
    fi
  fi

  # Clean ~/.bashrc (restore /etc/skel/.bashrc on real systems so bash stays clean)
  if [[ -f $HOME/.bashrc ]] && grep -qE 'QUATTRO_PATH|default/bash/env-bootstrap|default/bash/rc' "$HOME/.bashrc" 2>/dev/null; then
    if ! $SANDBOX && [[ -f /etc/skel/.bashrc ]]; then
      cp -a /etc/skel/.bashrc "$HOME/.bashrc"
    else
      rm -f "$HOME/.bashrc"
    fi
  fi

  # Clean ~/.XCompose if it was seeded by Quattro
  if [[ -f $HOME/.XCompose ]] && grep -qi 'quattro' "$HOME/.XCompose" 2>/dev/null; then
    rm -f "$HOME/.XCompose"
  fi

  # Clean VS Code / VSCodium generated theme extension
  clean_vscode_extensions

  # Prune now-empty config subdirectories
  local d
  for d in \
    "$CONFIG_HOME/environment.d" \
    "$CONFIG_HOME/uwsm/env.d" \
    "$CONFIG_HOME/uwsm" \
    "$CONFIG_HOME/xdg-terminal-exec" \
    "$CONFIG_HOME/fontconfig/conf.d" \
    "$CONFIG_HOME/fontconfig" \
    "$CONFIG_HOME/xkb/rules" \
    "$CONFIG_HOME/xkb/symbols" \
    "$CONFIG_HOME/xkb" \
    "$CONFIG_HOME/mpv" \
    "$CONFIG_HOME/fastfetch" \
    "$CONFIG_HOME/qt6ct" \
    "$CONFIG_HOME/gtk-3.0" \
    "$CONFIG_HOME/gtk-4.0" \
    "$CONFIG_HOME/systemd/user" \
    "$CONFIG_HOME/systemd"; do
    prune_empty_dir "$d"
  done
}

remove_user_data_assets() {
  echo "==> Removing user desktop entries, icons, fonts, and resetting desktop settings..."

  # Desktop entries
  local desktop_file
  for desktop_file in "$PROJECT_DIR"/applications/*.desktop; do
    [[ -f $desktop_file ]] && rm -f "$DATA_HOME/applications/${desktop_file##*/}"
  done
  rm -f \
    "$DATA_HOME/applications"/quattro-*.desktop \
    "$DATA_HOME/applications/imv.desktop" \
    "$DATA_HOME/applications/foot.desktop"

  # Hidden fcitx5 stub entries created by install.sh
  local hidden_desktop target_desktop
  for hidden_desktop in \
    fcitx5-configtool.desktop \
    fcitx5-wayland-launcher.desktop \
    org.fcitx.Fcitx5.desktop; do
    target_desktop="$DATA_HOME/applications/$hidden_desktop"
    if [[ -f $target_desktop ]] && grep -qxF 'NoDisplay=true' "$target_desktop" 2>/dev/null; then
      local line_count=0 _line
      while IFS= read -r _line && (( ++line_count <= 5 )); do :; done <"$target_desktop"
      (( line_count <= 4 )) && rm -f "$target_desktop"
    fi
  done

  # Icons (Quattro theme symlinks, hicolor app icons, and themed SVG symlinks)
  rm -rf "$DATA_HOME/icons/Quattro" "$DATA_HOME/icons/Quattro-alt"
  rm -f "$DATA_HOME/icons/hicolor/256x256/apps/quattro.png"
  if [[ -d $PROJECT_DIR/applications/icons ]]; then
    local icon_file
    for icon_file in "$PROJECT_DIR"/applications/icons/*; do
      [[ -e $icon_file ]] && rm -f "$DATA_HOME/icons/hicolor/256x256/apps/${icon_file##*/}"
    done
  fi

  local scalable_dir="$DATA_HOME/icons/hicolor/scalable/apps"
  if [[ -d $scalable_dir ]]; then
    local svg_link svg_target
    for svg_link in "$scalable_dir"/*.svg; do
      [[ -L $svg_link ]] || continue
      svg_target=$(readlink "$svg_link" 2>/dev/null || true)
      if [[ $svg_target == *"/quattro/"* ]]; then
        rm -f "$svg_link"
      fi
    done
    local tpl name
    for tpl in "$PROJECT_DIR"/default/themed/icons/*.svg.tpl; do
      [[ -f $tpl ]] || continue
      name="${tpl##*/}"
      name="${name%.tpl}"
      [[ -L $scalable_dir/$name ]] && rm -f "$scalable_dir/$name"
    done
  fi

  # Fonts
  rm -rf "$DATA_HOME/fonts/quattro"

  # Remove untouched empty default keyring seeded by install.sh (preserve if it holds saved secrets)
  local keyring_dir="$DATA_HOME/keyrings"
  if [[ -f $keyring_dir/Default_keyring.keyring ]] && ! grep -qE '^\[[0-9]+\]' "$keyring_dir/Default_keyring.keyring" 2>/dev/null; then
    rm -f "$keyring_dir/Default_keyring.keyring"
    if [[ -f $keyring_dir/default ]] && [[ $(<"$keyring_dir/default") == "Default_keyring" ]]; then
      rm -f "$keyring_dir/default"
    fi
  fi

  # Prune empty user data directories
  local d
  for d in \
    "$DATA_HOME/applications" \
    "$DATA_HOME/fonts" \
    "$DATA_HOME/icons/hicolor/256x256/apps" \
    "$DATA_HOME/icons/hicolor/256x256" \
    "$DATA_HOME/icons/hicolor/scalable/apps" \
    "$DATA_HOME/icons/hicolor/scalable" \
    "$DATA_HOME/icons/hicolor" \
    "$DATA_HOME/icons" \
    "$DATA_HOME/keyrings"; do
    prune_empty_dir "$d"
  done

  # Reset GNOME/GTK dconf settings applied by quattro-theme-set-gnome
  if ! $SANDBOX && [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] && command -v gsettings >/dev/null 2>&1; then
    local current_icon_theme
    current_icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true)
    if [[ $current_icon_theme == "'Quattro'" || $current_icon_theme == "'Quattro-alt'" ]]; then
      gsettings reset org.gnome.desktop.interface icon-theme >/dev/null 2>&1 || true
    fi
    gsettings reset org.gnome.desktop.interface color-scheme >/dev/null 2>&1 || true
    gsettings reset org.gnome.desktop.interface gtk-theme >/dev/null 2>&1 || true
    gsettings reset org.gnome.desktop.interface accent-color >/dev/null 2>&1 || true
  fi

  if ! $SANDBOX && command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi

  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$DATA_HOME/fonts" >/dev/null 2>&1 || true
  fi
}

remove_system_configs() {
  echo "==> Removing system-wide Quattro integration (requires sudo)..."
  sudo -v

  # Remove pacman alpm hooks first so subsequent pacman operations never invoke them
  sudo rm -f \
    /usr/share/libalpm/hooks/90-quattro-titlebars-rebuild.hook \
    /usr/share/libalpm/hooks/90-quattro-nautilus-theme-rebuild.hook

  # Clean PAM references to quattro-hw-laptop-closed BEFORE deleting /usr/bin/quattro-hw-laptop-closed
  local pam_file
  for pam_file in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
    if sudo test -f "$pam_file" && sudo grep -q 'quattro-hw-laptop-closed' "$pam_file" 2>/dev/null; then
      sudo sed -i '/quattro-hw-laptop-closed/d' "$pam_file"
    fi
  done
  sudo rm -f \
    /etc/pam.d/quattro-lock-password \
    /etc/pam.d/quattro-lock-fingerprint

  # Stop any transient passwordless-sudo expiry timers
  if command -v systemctl >/dev/null 2>&1; then
    local timer_unit
    while IFS= read -r timer_unit; do
      [[ -n $timer_unit ]] || continue
      sudo systemctl stop "$timer_unit" >/dev/null 2>&1 || true
    done < <(sudo systemctl list-units --all --no-legend 'quattro-nopasswd-expire-*' 2>/dev/null | awk '{print $1}' || true)

    # Disable SDDM (without --now so an active graphical session is not killed mid-uninstall)
    sudo systemctl disable sddm.service >/dev/null 2>&1 || true
  fi

  # Remove root-owned privileged helpers
  sudo rm -f \
    /usr/bin/quattro-build-titlebars \
    /usr/bin/quattro-build-nautilus-theme \
    /usr/bin/quattro-dns \
    /usr/bin/quattro-sudo-passwordless \
    /usr/bin/quattro-theme-set-browser-policy \
    /usr/bin/quattro-locale-generate \
    /usr/bin/quattro-apply-lock \
    /usr/bin/quattro-hw-laptop-closed

  # Remove compiled titlebars & Nautilus plugins, system runtime data, licenses, and state
  sudo rm -rf \
    /usr/lib/quattro-hyprland-titlebars \
    /usr/lib/nautilus/extensions-4/libquattro-nautilus-theme.so \
    /usr/lib/nautilus/extensions-4/.quattro-nautilus-theme.stamp \
    /usr/share/quattro \
    /usr/share/licenses/quattro-hyprland-titlebars \
    /var/lib/quattro \
    /run/lock/quattro-sudo-passwordless.lock

  # Remove Wayland session, UWSM, xdg-terminal-exec, profile.d, fontconfig, fastfetch, mpv, xkb
  sudo rm -f \
    /usr/local/share/wayland-sessions/quattro.desktop \
    /usr/local/share/xdg-terminal-exec/hyprland-xdg-terminals.list \
    /etc/profile.d/quattro.sh \
    /etc/quattro.conf \
    /usr/share/uwsm/env.d/10-quattro \
    /etc/fastfetch/config.jsonc \
    /etc/mpv/mpv.conf \
    /etc/xkb/rules/evdev \
    /etc/xkb/symbols/quattro \
    /etc/fonts/conf.d/50-quattro.conf

  # Remove SDDM configs & SilentSDDM theme + fonts
  sudo rm -f \
    /etc/sddm.conf.d/10-wayland.conf \
    /etc/sddm.conf.d/10-theme.conf \
    /etc/sddm.conf.d/99-quattro-login.conf \
    /usr/share/sddm/hyprland.lua
  sudo rm -rf \
    /usr/share/sddm/themes/silent \
    /usr/share/sddm/themes/quattro \
    /usr/share/fonts/silent-sddm
  if command -v fc-cache >/dev/null 2>&1; then
    sudo fc-cache -f /usr/share/fonts >/dev/null 2>&1 || true
  fi
  if sudo test -f /var/lib/sddm/state.conf && sudo grep -q 'quattro\.desktop' /var/lib/sddm/state.conf 2>/dev/null; then
    sudo rm -f /var/lib/sddm/state.conf
  fi

  # Remove systemd overrides, sleep/resume hooks, mkinitcpio, tmpfiles
  sudo rm -f \
    /etc/systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf \
    /etc/systemd/sleep.conf.d/quattro-sleep-disabled.conf \
    /etc/systemd/system/fprintd.service.d/10-stop-timeout.conf \
    /usr/lib/systemd/system-sleep/fprintd-resume \
    /etc/mkinitcpio.conf.d/quattro_resume.conf \
    /etc/tmpfiles.d/quattro-nopasswd-sudo.conf

  # Remove sudoers drop-ins
  sudo rm -f \
    /etc/sudoers.d/quattro-dns \
    /etc/sudoers.d/quattro-theme-browser \
    /etc/sudoers.d/quattro-locale-generate \
    /etc/sudoers.d/99-quattro-nopasswd-* \
    /etc/sudoers.d/99-quattro-permanent-nopasswd-* \
    /etc/sudoers.d/.quattro-nopasswd.*

  # Remove managed browser policies
  sudo rm -f \
    /etc/brave/policies/managed/quattro.json \
    /etc/brave/policies/managed/quattro-theme.json \
    /etc/brave/policies/managed/color.json
  local browser_policy_dir
  for browser_policy_dir in \
    /etc/chromium/policies/managed \
    /etc/opt/chrome/policies/managed \
    /etc/opt/edge/policies/managed; do
    if sudo test -f "$browser_policy_dir/color.json" &&
      sudo grep -q '"BrowserThemeColor"' "$browser_policy_dir/color.json" 2>/dev/null &&
      sudo grep -q '"BrowserColorScheme"' "$browser_policy_dir/color.json" 2>/dev/null; then
      sudo rm -f "$browser_policy_dir/color.json"
    fi
  done

  # Remove NetworkManager DNS drop-in if created by quattro-dns
  sudo rm -f /etc/NetworkManager/conf.d/20-quattro-dns.conf

  # Prune empty system directories created by install.sh
  local sys_dir
  for sys_dir in \
    /usr/local/share/wayland-sessions \
    /usr/local/share/xdg-terminal-exec \
    /etc/sddm.conf.d \
    /usr/share/uwsm/env.d \
    /etc/fastfetch \
    /etc/mpv \
    /etc/xkb/rules \
    /etc/xkb/symbols \
    /etc/xkb \
    /etc/systemd/user/wayland-wm@hyprland.desktop.service.d \
    /etc/systemd/sleep.conf.d \
    /etc/systemd/system/fprintd.service.d \
    /etc/brave/policies/managed \
    /etc/brave/policies \
    /etc/brave \
    /var/lib/sddm; do
    sudo_prune_empty_dir "$sys_dir"
  done

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

is_native_cachyos() {
  [[ -r /etc/os-release ]] && grep -qiE '^ID=cachyos([[:space:]]|$)' /etc/os-release
}

remove_cachyos_repos() {
  if is_native_cachyos; then
    echo -e "${YELLOW}Native CachyOS detected; keeping CachyOS repositories and keyring intact.${NC}"
    return 0
  fi

  echo "==> Removing CachyOS repositories, mirrorlists, and signing key..."

  if [[ -f /etc/pacman.conf ]] && grep -qE '^[[:space:]]*\[cachyos(-[a-z0-9-]+)?\][[:space:]]*$' /etc/pacman.conf; then
    local tmp
    tmp=$(mktemp)
    _TMP_FILES+=("$tmp")
    awk '
      /^[[:space:]]*\[cachyos(-[a-z0-9-]+)?\][[:space:]]*$/ { skip = 1; next }
      /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { skip = 0; eat_blank = 0; print; next }
      skip { eat_blank = 1; next }
      eat_blank && /^[[:space:]]*$/ { next }
      { eat_blank = 0; print }
    ' /etc/pacman.conf >"$tmp"

    if [[ -s $tmp ]]; then
      sudo install -m 0644 -o root -g root "$tmp" /etc/pacman.conf
      echo -e "${GREEN}Removed CachyOS repository blocks from /etc/pacman.conf${NC}"
    fi
    rm -f "$tmp"
  fi

  sudo rm -f \
    /etc/pacman.d/cachyos-mirrorlist* \
    /etc/pacman.d/cachyos-v3-mirrorlist* \
    /etc/pacman.d/cachyos-v4-mirrorlist* \
    /var/lib/pacman/sync/cachyos*.db* \
    /var/lib/pacman/sync/cachyos*.files*

  if command -v pacman-key >/dev/null 2>&1; then
    sudo pacman-key --delete F3B607488DB35A47 >/dev/null 2>&1 || true
  fi
}

remove_packages() {
  if ! command -v pacman >/dev/null 2>&1; then
    echo -e "${YELLOW}pacman not found; skipping package removal.${NC}"
    return 0
  fi

  echo "==> Removing Quattro core packages via pacman..."

  local -a all_pkgs=()
  mapfile -t all_pkgs < <(grep -hvE '^[[:space:]]*(#|$)' "$PROJECT_DIR/packages/arch-core.packages")

  if ! is_native_cachyos; then
    all_pkgs+=(
      cachyos-keyring
      cachyos-mirrorlist
      cachyos-v3-mirrorlist
      cachyos-v4-mirrorlist
    )
  fi

  local -a installed_pkgs=()
  if (( ${#all_pkgs[@]} > 0 )); then
    mapfile -t installed_pkgs < <(pacman -Qq "${all_pkgs[@]}" 2>/dev/null || true)
  fi

  if (( ${#installed_pkgs[@]} == 0 )); then
    echo "No Quattro packages are currently installed."
  else
    # First attempt a single clean transaction removing all installed Quattro packages + unneeded deps.
    if sudo pacman -Rns --noconfirm "${installed_pkgs[@]}"; then
      echo -e "${GREEN}All Quattro packages removed cleanly.${NC}"
    else
      echo -e "${YELLOW}Batch removal hit dependency constraints from other installed packages; unwinding package-by-package...${NC}"

      local -a remaining=("${installed_pkgs[@]}")
      local -a next_remaining=()
      local removed_in_pass=1
      local pkg

      while (( removed_in_pass > 0 && ${#remaining[@]} > 0 )); do
        removed_in_pass=0
        next_remaining=()
        for pkg in "${remaining[@]}"; do
          if ! pacman -Qq "$pkg" >/dev/null 2>&1; then
            continue
          fi
          if sudo pacman -Rns --noconfirm "$pkg" >/dev/null 2>&1; then
            echo "  Removed: $pkg"
            removed_in_pass=$((removed_in_pass + 1))
          else
            next_remaining+=("$pkg")
          fi
        done
        remaining=("${next_remaining[@]}")
      done

      if (( ${#remaining[@]} > 0 )); then
        echo -e "${YELLOW}The following packages were kept because other non-Quattro packages still depend on them:${NC}"
        for pkg in "${remaining[@]}"; do
          if pacman -Qq "$pkg" >/dev/null 2>&1; then
            echo "  - $pkg"
            sudo pacman -D --asdeps --noconfirm "$pkg" >/dev/null 2>&1 || true
          fi
        done
      fi
    fi
  fi

  remove_cachyos_repos

  # Refresh font cache if fontconfig is still installed
  if command -v fc-cache >/dev/null 2>&1; then
    sudo fc-cache -f >/dev/null 2>&1 || true
  fi
}

confirm_uninstall
stop_user_services
remove_user_runtime
remove_user_configs
remove_user_data_assets

if ! $SANDBOX; then
  remove_system_configs
  if ! $KEEP_PACKAGES; then
    remove_packages
  fi
fi

echo ""
echo -e "${GREEN}Done! Quattro has been completely uninstalled.${NC}"

if ! $SANDBOX && [[ ${QUATTRO_NO_REBOOT:-0} != "1" ]] && [[ -t 0 ]] && ! $ASSUME_YES; then
  echo ""
  read -r -p "Reboot now to finalize system cleanup? [y/N] " reply || reply=""
  if [[ $reply =~ ^[Yy]$ ]]; then
    sudo reboot
  fi
fi
