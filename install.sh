#!/bin/bash

set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  cat <<'EOF'
Usage: ./install.sh

Installs minimal Quattro core packages (Arch [core]/[extra]), runtime, user
configs, Tokyo Night theme, and system-wide session/environment files.
No flags needed.
EOF
  exit 0
fi

if (( $# > 0 )); then
  echo "Usage: ./install.sh (runs full install with no flags)" >&2
  exit 1
fi

SANDBOX=false
if [[ ${QUATTRO_INSTALL_SANDBOX:-0} == "1" ]]; then
  SANDBOX=true
elif (( EUID == 0 )); then
  echo "Run ./install.sh as your normal user (it will prompt for sudo when needed), not as root." >&2
  exit 1
fi

THEME="Tokyo Night"
INSTALL_DIR="$HOME/.local/share/quattro"
BIN_LINK_DIR="$HOME/.local/bin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PACMAN_SYNC_FORCE=0

setup_cachyos_repos() {
  if [[ $(uname -m) != "x86_64" ]]; then
    echo -e "${YELLOW}Non-x86_64 architecture ($(uname -m)); skipping x86_64 CachyOS repositories.${NC}"
    return
  fi

  if [[ -f /etc/pacman.conf ]] && grep -qE '^[[:space:]]*\[cachyos\][[:space:]]*$' /etc/pacman.conf; then
    echo -e "${YELLOW}CachyOS repositories already configured.${NC}"
    return
  fi

  echo -e "${YELLOW}Detecting CPU architecture...${NC}"

  local ARCH ld_help
  ld_help=$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null || true)
  if grep -qE 'x86-64-v4[[:space:]]*\(supported, searched\)' <<<"$ld_help"; then
    ARCH="v4"
    echo -e "${GREEN}Detected: x86-64-v4${NC}"
  elif grep -qE 'x86-64-v3[[:space:]]*\(supported, searched\)' <<<"$ld_help"; then
    ARCH="v3"
    echo -e "${GREEN}Detected: x86-64-v3${NC}"
  else
    ARCH="v2"
    echo -e "${GREEN}Detected: x86-64 (baseline)${NC}"
  fi

  echo -e "${YELLOW}Importing CachyOS signing key...${NC}"
  sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key F3B607488DB35A47

  echo -e "${YELLOW}Installing CachyOS keyring and mirrorlists...${NC}"
  local cachyos_base="https://mirror.cachyos.org/repo/x86_64/cachyos"
  local cachyos_index
  cachyos_index=$(curl -fsSL --max-time 10 "$cachyos_base/" 2>/dev/null || true)

  resolve_cachyos_pkg() {
    local name="$1" fallback="$2" found=""
    if [[ -n $cachyos_index ]]; then
      found=$(printf '%s\n' "$cachyos_index" | grep -oE "${name}-[0-9][^\"'<>]*-any\.pkg\.tar\.zst" | head -n1 || true)
    fi
    echo "${cachyos_base}/${found:-$fallback}"
  }

  sudo pacman -U --noconfirm \
    "$(resolve_cachyos_pkg cachyos-keyring cachyos-keyring-20240331-1-any.pkg.tar.zst)" \
    "$(resolve_cachyos_pkg cachyos-mirrorlist cachyos-mirrorlist-27-1-any.pkg.tar.zst)" \
    "$(resolve_cachyos_pkg cachyos-v3-mirrorlist cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst)" \
    "$(resolve_cachyos_pkg cachyos-v4-mirrorlist cachyos-v4-mirrorlist-27-1-any.pkg.tar.zst)"

  echo -e "${YELLOW}Configuring repositories in pacman.conf...${NC}"

  local REPO_CONFIG=""
  if [[ "$ARCH" == "v4" ]]; then
    REPO_CONFIG="[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

"
  elif [[ "$ARCH" == "v3" ]]; then
    REPO_CONFIG="[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

"
  fi

  REPO_CONFIG="${REPO_CONFIG}[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist"

  if grep -qE '^[[:space:]]*\[core\][[:space:]]*$' /etc/pacman.conf; then
    awk -v block="$REPO_CONFIG" '
      !inserted && /^[[:space:]]*\[core\][[:space:]]*$/ {
        print block
        print ""
        inserted = 1
      }
      { print }
    ' /etc/pacman.conf | sudo tee /etc/pacman.conf.tmp >/dev/null
    sudo mv /etc/pacman.conf.tmp /etc/pacman.conf
    sudo chmod 0644 /etc/pacman.conf
  else
    printf '\n%s\n' "$REPO_CONFIG" | sudo tee -a /etc/pacman.conf >/dev/null
  fi
  echo -e "${GREEN}Repositories added to pacman.conf${NC}"
  PACMAN_SYNC_FORCE=1
}

install_packages() {
  local -a pkgs=()
  mapfile -t pkgs < <(grep -hvE '^[[:space:]]*(#|$)' "$PROJECT_DIR/packages/arch-core.packages")

  if (( ${#pkgs[@]} > 0 )); then
    local sync_flags="-Syu"
    (( PACMAN_SYNC_FORCE )) && sync_flags="-Syyu"
    echo "==> Syncing package databases and installing core packages via pacman..."
    sudo pacman "$sync_flags" --needed --noconfirm "${pkgs[@]}"
  fi
}

install_runtime() {
  echo "==> Installing Quattro runtime to $INSTALL_DIR..."
  mkdir -p "$INSTALL_DIR"

  for item in applications bin config default packages shell themes icon.png icon.txt logo.svg logo.txt version LICENSE; do
    if [[ -d $PROJECT_DIR/$item ]]; then
      rm -rf "${INSTALL_DIR:?}/$item"
      mkdir -p "$INSTALL_DIR/$item"
      cp -a "$PROJECT_DIR/$item/." "$INSTALL_DIR/$item/"
    elif [[ -e $PROJECT_DIR/$item ]]; then
      cp -a "$PROJECT_DIR/$item" "$INSTALL_DIR/$item"
    fi
  done

  # Resolve file:///usr/share/quattro in bundled Chromium CRX manifests for standalone installs
  for crx_file in \
    "$INSTALL_DIR/default/chromium/crx/updates.xml" \
    "$INSTALL_DIR/default/chromium/policies/chrome-extensions.json"; do
    if [[ -f $crx_file ]]; then
      sed -i "s|file:///usr/share/quattro|file://$INSTALL_DIR|g" "$crx_file"
    fi
  done

  echo "==> Linking quattro-* commands into $BIN_LINK_DIR..."
  mkdir -p "$BIN_LINK_DIR"
  for link in "$BIN_LINK_DIR"/quattro-*; do
    [[ -L $link && ! -e $link ]] && rm -f "$link"
  done
  for bin_file in "$PROJECT_DIR"/bin/*; do
    local name="${bin_file##*/}"
    ln -snf "$INSTALL_DIR/bin/$name" "$BIN_LINK_DIR/$name"
  done
}

install_user_configs() {
  echo "==> Deploying ~/.config from $PROJECT_DIR/config..."
  mkdir -p "$HOME/.config"

  local entry name target
  for entry in "$PROJECT_DIR"/config/* "$PROJECT_DIR"/config/.*; do
    name="${entry##*/}"
    [[ $name == "." || $name == ".." ]] && continue
    [[ -e $entry ]] || continue
    target="$HOME/.config/$name"

    if [[ -d $entry ]]; then
      mkdir -p "$target"
      # Copy sub-items individually so existing user files outside Quattro defaults are preserved
      while IFS= read -r -d '' src_file; do
        local rel="${src_file#$entry/}"
        local dst_file="$target/$rel"
        mkdir -p "$(dirname "$dst_file")"
        cp -a "$src_file" "$dst_file"
      done < <(find "$entry" \( -type f -o -type l \) -print0)
    else
      cp -a "$entry" "$target"
    fi
  done

  # Resolve __QUATTRO_PATH__ in Chromium-family browser flags
  for flags_file in \
    "$HOME/.config/brave-origin-flags.conf" \
    "$HOME/.config/chrome-flags.conf" \
    "$HOME/.config/chromium-flags.conf"; do
    if [[ -f $flags_file ]]; then
      sed -i "s|__QUATTRO_PATH__|$INSTALL_DIR|g" "$flags_file"
    fi
  done

  # Keep custom_picker_binary pointed at quattro-share-picker unless user overrides it
  if [[ -f $HOME/.config/hypr/xdph.conf ]] && grep -q '^    # custom_picker_binary = hyprland-preview-share-picker' "$HOME/.config/hypr/xdph.conf"; then
    sed -i 's|^    # custom_picker_binary = hyprland-preview-share-picker|    custom_picker_binary = quattro-share-picker|' "$HOME/.config/hypr/xdph.conf"
  fi

  # Seed ~/.bashrc
  cp -a "$PROJECT_DIR/default/bashrc" "$HOME/.bashrc"

  # Seed ~/.XCompose if missing
  if [[ ! -f $HOME/.XCompose ]]; then
    cat >"$HOME/.XCompose" <<EOF
# Run quattro-restart-xcompose to apply changes

# Include fast emoji access
include "$INSTALL_DIR/default/xcompose"
EOF
  fi

  # Update branding files for fastfetch & screensaver
  mkdir -p "$HOME/.config/quattro/branding" "$HOME/.config/quattro/themes"
  cp -a "$PROJECT_DIR/logo.txt" "$HOME/.config/quattro/branding/about.txt"
  cp -a "$PROJECT_DIR/icon.txt" "$HOME/.config/quattro/branding/screensaver.txt"

  # Seed Hyprland toggles directory (only flags.lua; individual toggles opt in when activated)
  mkdir -p "$HOME/.local/state/quattro/toggles/hypr"
  [[ -e $HOME/.local/state/quattro/toggles/hypr/flags.lua ]] || cp -a "$PROJECT_DIR/default/hypr/toggles/flags.lua" "$HOME/.local/state/quattro/toggles/hypr/flags.lua"
  # One-time cleanup of shipped toggle files copied by earlier installer versions
  if [[ ! -e $HOME/.local/state/quattro/.toggles-cleaned ]]; then
    for stale_toggle in bar-glassy.lua corners-rounded.lua corners-sharp.lua no-animations.lua single-window-aspect-ratio.lua window-glassy.lua window-no-gaps.lua window-opaque.lua; do
      rm -f "$HOME/.local/state/quattro/toggles/hypr/$stale_toggle"
    done
    : >"$HOME/.local/state/quattro/.toggles-cleaned"
  fi

  # Seed user systemd environment drop-ins (UWSM 10-quattro is installed system-wide in /usr/share/uwsm/env.d
  # so user overrides in ~/.config/uwsm/env are not clobbered; only seed under ~/.config in sandbox mode)
  mkdir -p "$HOME/.config/environment.d"
  if $SANDBOX; then
    mkdir -p "$HOME/.config/uwsm/env.d"
    cp -a "$PROJECT_DIR/default/uwsm/env.d/10-quattro" "$HOME/.config/uwsm/env.d/10-quattro"
  else
    rm -f "$HOME/.config/uwsm/env.d/10-quattro" "$HOME/.config/xdg-terminal-exec/hyprland-xdg-terminals.list"
  fi
  cp -a "$PROJECT_DIR/default/environment.d/10-quattro-fcitx.conf" "$HOME/.config/environment.d/10-quattro-fcitx.conf"

  cat >"$HOME/.config/environment.d/20-quattro-path.conf" <<EOF
QUATTRO_PATH=$INSTALL_DIR
PATH=$BIN_LINK_DIR:$INSTALL_DIR/bin:\$PATH
EOF

  # Install desktop entries, icons, and fonts to ~/.local/share
  mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/fonts/quattro" "$HOME/.config/fontconfig/conf.d"
  cp -a "$PROJECT_DIR"/applications/*.desktop "$HOME/.local/share/applications/"
  if command -v alacritty >/dev/null 2>&1 && [[ -f $PROJECT_DIR/default/alacritty/Alacritty.desktop ]]; then
    cp -a "$PROJECT_DIR/default/alacritty/Alacritty.desktop" "$HOME/.local/share/applications/"
  fi
  if command -v foot >/dev/null 2>&1 && [[ -f $PROJECT_DIR/default/foot/foot.desktop ]]; then
    cp -a "$PROJECT_DIR/default/foot/foot.desktop" "$HOME/.local/share/applications/"
  fi
  rm -f "$HOME/.cache/xdg-terminal-exec"
  cp -a "$PROJECT_DIR/default/fonts/quattro/quattro.ttf" "$HOME/.local/share/fonts/quattro/quattro.ttf"
  cp -a "$PROJECT_DIR/default/fontconfig/conf.avail/50-quattro.conf" "$HOME/.config/fontconfig/conf.d/50-quattro.conf"

  mkdir -p "$HOME/.local/share/icons/hicolor/256x256/apps"
  cp -a "$PROJECT_DIR/icon.png" "$HOME/.local/share/icons/hicolor/256x256/apps/quattro.png"
  if [[ -d $PROJECT_DIR/applications/icons ]]; then
    cp -a "$PROJECT_DIR/applications/icons/." "$HOME/.local/share/icons/hicolor/256x256/apps/"
  fi

  # Remove orphaned web-app entries whose icon file is missing
  local app_file exec_line icon_line
  while IFS= read -r -d '' app_file; do
    exec_line=$(grep -m1 '^Exec=' "$app_file" 2>/dev/null || true)
    [[ $exec_line == Exec=*launch-webapp* || $exec_line == Exec=*webapp-handler* ]] || continue
    icon_line=$(sed -n 's/^Icon=//p' "$app_file" 2>/dev/null | head -n1)
    if [[ -z $icon_line ]]; then
      rm -f "$app_file"
    elif [[ $icon_line == /* && ! -e $icon_line ]]; then
      rm -f "$app_file"
    elif [[ $icon_line != /* ]]; then
      local icon_base="${icon_line%.*}"
      if ! find -L "$HOME/.local/share/icons" /usr/share/icons /usr/share/pixmaps -type f \( -name "$icon_line" -o -name "$icon_base.png" -o -name "$icon_base.svg" \) -print -quit 2>/dev/null | grep -q .; then
        rm -f "$app_file"
      fi
    fi
  done < <(find "$HOME/.local/share/applications" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)

  # User-level XKB option (Shift + CapsLock Compose), fastfetch, and mpv defaults
  mkdir -p "$HOME/.config/xkb/rules" "$HOME/.config/xkb/symbols"
  cp -a "$PROJECT_DIR/etc/xkb/rules/evdev" "$HOME/.config/xkb/rules/evdev"
  cp -a "$PROJECT_DIR/etc/xkb/symbols/quattro" "$HOME/.config/xkb/symbols/quattro"

  # Keep /etc/fastfetch/config.jsonc as the default so quattro-launch-about does
  # not mistake an untouched user copy for a custom layout and skip auto-sizing.
  if [[ -f $HOME/.config/fastfetch/config.jsonc ]] && cmp -s "$HOME/.config/fastfetch/config.jsonc" "$PROJECT_DIR/etc/fastfetch/config.jsonc"; then
    rm -f "$HOME/.config/fastfetch/config.jsonc"
  fi

  if [[ ! -f $HOME/.config/mpv/mpv.conf ]]; then
    mkdir -p "$HOME/.config/mpv"
    cp -a "$PROJECT_DIR/etc/mpv/mpv.conf" "$HOME/.config/mpv/mpv.conf"
  fi

  # Install user systemd units
  mkdir -p "$HOME/.config/systemd/user/wireplumber.service.d"
  for unit in "$PROJECT_DIR"/default/systemd/user/*.service; do
    cp -a "$unit" "$HOME/.config/systemd/user/"
  done
  cp -a "$PROJECT_DIR/default/systemd/user/wireplumber.service.d/"*.conf "$HOME/.config/systemd/user/wireplumber.service.d/"

  # Install default mimeapps if user doesn't have one yet
  if [[ ! -f $HOME/.config/mimeapps.list ]]; then
    cp -a "$PROJECT_DIR/default/applications/mimeapps.list" "$HOME/.config/mimeapps.list"
  elif command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default org.gnome.Nautilus.desktop inode/directory || true
  fi

  # Ensure default folders exist and are pinned in Nautilus sidebar bookmarks
  local gtk_bookmarks="$HOME/.config/gtk-3.0/bookmarks"
  mkdir -p "$HOME/.config/gtk-3.0"
  touch "$gtk_bookmarks"
  local pin_dir pin_uri
  for pin_dir in Downloads Documents Projects Pictures Videos; do
    mkdir -p "$HOME/$pin_dir"
    pin_uri="file://$HOME/$pin_dir"
    if ! awk -v uri="$pin_uri" '$1 == uri { found = 1; exit } END { exit !found }' "$gtk_bookmarks" 2>/dev/null; then
      printf '%s %s\n' "$pin_uri" "$pin_dir" >>"$gtk_bookmarks"
    fi
  done

  # Seed unlocked default keyring if none exists so logins do not prompt
  local keyring_dir="$HOME/.local/share/keyrings"
  mkdir -p "$keyring_dir"
  chmod 700 "$keyring_dir"
  if [[ ! -f $keyring_dir/Default_keyring.keyring ]]; then
    cat >"$keyring_dir/Default_keyring.keyring" <<EOF
[keyring]
display-name=Default keyring
ctime=$(date +%s)
mtime=0
lock-on-idle=false
lock-after=false
EOF
    chmod 600 "$keyring_dir/Default_keyring.keyring"
  fi
  if [[ ! -f $keyring_dir/default ]]; then
    printf 'Default_keyring\n' >"$keyring_dir/default"
    chmod 644 "$keyring_dir/default"
  fi

  # Refresh font cache
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$HOME/.local/share/fonts" || true
  fi
}

generate_initial_theme() {
  echo "==> Generating initial theme ($THEME)..."
  export QUATTRO_PATH="$INSTALL_DIR"
  export PATH="$BIN_LINK_DIR:$INSTALL_DIR/bin:$PATH"
  export QUATTRO_THEME_HEADLESS=1

  "$INSTALL_DIR/bin/quattro-theme-set" "$THEME"
  mkdir -p "$HOME/.config/btop/themes"
  ln -snf "$HOME/.local/state/quattro/current/theme/btop.theme" "$HOME/.config/btop/themes/current.theme"

  if command -v quattro-theme-set-qt >/dev/null 2>&1; then
    quattro-theme-set-qt || true
  fi
}

install_system_configs() {
  echo "==> Installing system-wide Arch integration (requires sudo)..."
  sudo install -d -m 0755 -o root -g root \
    /usr/local/share/wayland-sessions \
    /usr/local/share/xdg-terminal-exec \
    /etc/sddm.conf.d \
    /usr/share/sddm/themes/quattro \
    /usr/share/quattro/default/i18n \
    /etc/profile.d \
    /usr/share/uwsm/env.d \
    /etc/fastfetch \
    /etc/mpv \
    /etc/xdg/kitty \
    /etc/xkb/rules \
    /etc/xkb/symbols \
    /etc/fonts/conf.d \
    /etc/systemd/user/wayland-wm@hyprland.desktop.service.d

  sudo install -Dm644 -o root -g root "$PROJECT_DIR/default/wayland-sessions/quattro.desktop" /usr/local/share/wayland-sessions/quattro.desktop
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/default/xdg-terminal-exec/hyprland-xdg-terminals.list" /usr/local/share/xdg-terminal-exec/hyprland-xdg-terminals.list
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/sddm.conf.d/10-wayland.conf" /etc/sddm.conf.d/10-wayland.conf
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/sddm.conf.d/10-theme.conf" /etc/sddm.conf.d/10-theme.conf
  cat <<'EOF' | sudo tee /etc/sddm.conf.d/99-quattro-login.conf >/dev/null
[Users]
RememberLastUser=true
RememberLastSession=true
EOF
  sudo chmod 0644 /etc/sddm.conf.d/99-quattro-login.conf
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/default/sddm/hyprland.lua" /usr/share/sddm/hyprland.lua
  sudo rm -rf /usr/share/sddm/themes/quattro
  sudo install -d -m 0755 -o root -g root /usr/share/sddm/themes/quattro
  sudo cp -r --no-preserve=ownership "$PROJECT_DIR/default/sddm/quattro/." /usr/share/sddm/themes/quattro/
  sudo chown -R root:root /usr/share/sddm/themes/quattro
  sudo chmod -R a+rX,go-w /usr/share/sddm/themes/quattro

  if ! sudo grep -qE '^User=.+' /var/lib/sddm/state.conf 2>/dev/null; then
    sudo install -d -m 0755 -o sddm -g sddm /var/lib/sddm 2>/dev/null || sudo install -d -m 0755 /var/lib/sddm
    cat <<EOF | sudo tee /var/lib/sddm/state.conf >/dev/null
[Last]
Session=/usr/local/share/wayland-sessions/quattro.desktop
User=$USER
EOF
    sudo chmod 0644 /var/lib/sddm/state.conf
    sudo chown sddm:sddm /var/lib/sddm /var/lib/sddm/state.conf 2>/dev/null || true
  fi

  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/profile.d/quattro.sh" /etc/profile.d/quattro.sh
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/default/uwsm/env.d/10-quattro" /usr/share/uwsm/env.d/10-quattro
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/fastfetch/config.jsonc" /etc/fastfetch/config.jsonc
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/mpv/mpv.conf" /etc/mpv/mpv.conf
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/xdg/kitty/kitty.conf" /etc/xdg/kitty/kitty.conf
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/xkb/rules/evdev" /etc/xkb/rules/evdev
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/xkb/symbols/quattro" /etc/xkb/symbols/quattro
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/default/fontconfig/conf.avail/50-quattro.conf" /etc/fonts/conf.d/50-quattro.conf
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf" /etc/systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/default/i18n/locales.json" /usr/share/quattro/default/i18n/locales.json

  # Prevent SDDM PAM logins from creating an encrypted keyring that prompts on login
  if [[ -f /etc/pam.d/sddm ]]; then
    sudo sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
    sudo sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
  fi
  if command -v faillock >/dev/null 2>&1; then
    sudo faillock --user "$USER" --reset 2>/dev/null || true
  fi

  # Remove any stale /etc/quattro.conf pointing at an unprivileged user home (env-bootstrap resolves $HOME/.local/share/quattro per user)
  if [[ -f /etc/quattro.conf ]] && grep -qxF "export QUATTRO_PATH=\"$INSTALL_DIR\"" /etc/quattro.conf; then
    sudo rm -f /etc/quattro.conf
  fi

  # Install packaged root-owned privileged helpers and sudoers rules
  sudo install -Dm755 -o root -g root "$PROJECT_DIR/bin/quattro-dns" /usr/bin/quattro-dns
  sudo install -Dm755 -o root -g root "$PROJECT_DIR/bin/quattro-sudo-passwordless" /usr/bin/quattro-sudo-passwordless
  sudo install -Dm755 -o root -g root "$PROJECT_DIR/bin/quattro-theme-set-browser-policy" /usr/bin/quattro-theme-set-browser-policy
  sudo install -Dm755 -o root -g root "$PROJECT_DIR/bin/quattro-locale-generate" /usr/bin/quattro-locale-generate
  sudo install -Dm755 -o root -g root "$PROJECT_DIR/bin/quattro-apply-lock" /usr/bin/quattro-apply-lock
  sudo install -Dm755 -o root -g root "$PROJECT_DIR/bin/quattro-hw-laptop-closed" /usr/bin/quattro-hw-laptop-closed
  sudo install -Dm755 -o root -g root "$PROJECT_DIR/bin/quattro-windows-vm" /usr/bin/quattro-windows-vm
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/bin/quattro-security-functions" /usr/bin/quattro-security-functions
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/etc/tmpfiles.d/quattro-nopasswd-sudo.conf" /etc/tmpfiles.d/quattro-nopasswd-sudo.conf
  sudo install -Dm644 -o root -g root "$PROJECT_DIR/default/libalpm/hooks/05-quattro-passwordless-revoke.hook" /usr/share/libalpm/hooks/05-quattro-passwordless-revoke.hook
  for sudoers_rule in quattro-dns quattro-theme-browser quattro-locale-generate; do
    if [[ -f $PROJECT_DIR/etc/sudoers.d/$sudoers_rule ]] && { ! command -v visudo >/dev/null 2>&1 || visudo -cf "$PROJECT_DIR/etc/sudoers.d/$sudoers_rule" >/dev/null 2>&1; }; then
      sudo install -Dm440 -o root -g root "$PROJECT_DIR/etc/sudoers.d/$sudoers_rule" "/etc/sudoers.d/$sudoers_rule"
    fi
  done

  # Seed managed browser policy for Brave (prevents Brave from hijacking mimeapps.list;
  # remove any legacy CRX theme policy and apply BrowserThemeColor for live theme reloads)
  if command -v brave-origin >/dev/null 2>&1 || command -v brave >/dev/null 2>&1; then
    sudo install -d -m 0755 -o root -g root /etc/brave /etc/brave/policies /etc/brave/policies/managed
    sudo install -Dm644 -o root -g root "$PROJECT_DIR/default/chromium/policies/quattro.json" /etc/brave/policies/managed/quattro.json
    sudo rm -f /etc/brave/policies/managed/quattro-theme.json
    sudo rm -rf /var/lib/quattro/brave-theme
    rm -rf "$HOME/.local/state/quattro/current/brave-theme"
    QUATTRO_PATH="$INSTALL_DIR" PATH="$BIN_LINK_DIR:$INSTALL_DIR/bin:$PATH" "$INSTALL_DIR/bin/quattro-theme-set-browser" || true
  fi

  # Ensure Quickshell lock screen PAM config (/etc/pam.d/quattro-lock-password) is installed
  if [[ -x /usr/bin/quattro-apply-lock ]]; then
    sudo QUATTRO_PATH="$INSTALL_DIR" QUATTRO_INSTALL_USER="$USER" /usr/bin/quattro-apply-lock
  fi

  echo "==> Enabling SDDM display manager..."
  sudo systemctl enable --force sddm.service
}

if ! $SANDBOX; then
  setup_cachyos_repos
  install_packages
fi

install_runtime
install_user_configs
generate_initial_theme

if ! $SANDBOX; then
  install_system_configs
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
  fi
fi

cat <<EOF

Done! Quattro installed to: $INSTALL_DIR

Next steps:
  1. Open a new bash login shell (or run: source ~/.bashrc)
  2. Switch themes anytime with:
     quattro-theme-set "Tokyo Night"   # or catppuccin, gruvbox, kanagawa, nord, etc.
  3. Log in via SDDM (Quattro (Hyprland uwsm)) or start from TTY:
     uwsm start hyprland.desktop
EOF

if ! $SANDBOX && [[ ${QUATTRO_NO_REBOOT:-0} != "1" ]]; then
  echo ""
  echo "==> Installation complete. Rebooting in 5 seconds (Ctrl+C to cancel)..."
  sleep 5
  sudo reboot
fi
