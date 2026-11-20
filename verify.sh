#!/bin/bash

set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

echo "==> 1. Checking Bash & Python script syntax and executable bits..."
script_errors=0
while IFS= read -r -d '' script; do
  shebang=$(head -n1 "$script" 2>/dev/null || true)
  if [[ $shebang == *bash* || $script == "$PROJECT_DIR/default/bash/"* || $script == "$PROJECT_DIR/etc/profile.d/"* || $script == "$PROJECT_DIR/default/uwsm/"* ]]; then
    if ! bash -n "$script" 2>/dev/null; then
      echo "  Bash syntax error in: $script" >&2
      script_errors=$((script_errors + 1))
    fi
  elif [[ $shebang == *python* ]]; then
    if ! python3 -c 'import ast,sys; ast.parse(open(sys.argv[1],"rb").read())' "$script" 2>/dev/null; then
      echo "  Python syntax error in: $script" >&2
      script_errors=$((script_errors + 1))
    fi
  fi
done < <(find "$PROJECT_DIR/install.sh" "$PROJECT_DIR/verify.sh" "$PROJECT_DIR/bin" "$PROJECT_DIR/default/bash" "$PROJECT_DIR/default/uwsm" "$PROJECT_DIR/etc/profile.d" "$PROJECT_DIR/default/chromium/browser-policy.sh" "$PROJECT_DIR/default/chromium/as-root.sh" "$PROJECT_DIR/default/input-methods/keyboard-layouts.sh" -type f -print0)
while IFS= read -r -d '' bin_file; do
  base="${bin_file##*/}"
  [[ $base == "quattro-security-functions" ]] && continue
  if [[ ! -x $bin_file ]]; then
    echo "  Non-executable script in bin/: $bin_file" >&2
    script_errors=$((script_errors + 1))
  fi
done < <(find "$PROJECT_DIR/bin" -maxdepth 1 -type f -print0)
(( script_errors == 0 )) && pass "All Bash & Python scripts pass syntax and permission checks" || fail "$script_errors script syntax/permission error(s)"

echo "==> 2. Checking Lua syntax..."
if command -v luac >/dev/null 2>&1; then
  lua_errors=0
  while IFS= read -r -d '' lua_file; do
    if ! luac -p "$lua_file" 2>/dev/null; then
      echo "  Lua syntax error in: $lua_file" >&2
      lua_errors=$((lua_errors + 1))
    fi
  done < <(find "$PROJECT_DIR/config/hypr" "$PROJECT_DIR/default/hypr" "$PROJECT_DIR/default/sddm" -name '*.lua' -type f -print0)
  (( lua_errors == 0 )) && pass "All Hyprland Lua files pass luac -p" || fail "$lua_errors Lua syntax error(s)"
else
  echo "SKIP: luac not installed (skipping Lua bytecode check)"
fi

echo "==> 3. Checking JSON & XML configs..."
json_errors=0
for jf in \
  "$PROJECT_DIR/config/quattro/shell.json" \
  "$PROJECT_DIR/etc/fastfetch/config.jsonc"; do
  if ! python3 -m json.tool "$jf" >/dev/null 2>&1; then
    echo "  Invalid JSON: $jf" >&2
    json_errors=$((json_errors + 1))
  fi
done
for xf in \
  "$PROJECT_DIR/default/fontconfig/conf.avail/50-quattro.conf" \
  "$PROJECT_DIR/default/chromium/crx/updates.xml"; do
  if ! python3 -c 'import xml.etree.ElementTree as ET, sys; ET.parse(sys.argv[1])' "$xf" >/dev/null 2>&1; then
    echo "  Invalid XML: $xf" >&2
    json_errors=$((json_errors + 1))
  fi
done
(( json_errors == 0 )) && pass "All JSON & XML config files parse cleanly" || fail "$json_errors JSON/XML error(s)"

echo "==> 4. Verifying Arch repository package lists..."
if command -v pacman >/dev/null 2>&1; then
  missing=$(comm -23 \
    <(grep -hvE '^[[:space:]]*(#|$)' "$PROJECT_DIR/packages/arch-core.packages" | sort -u) \
    <(pacman -Ssq | sort -u))
  if [[ -z $missing ]]; then
    pass "All packages in arch-core.packages exist in pacman repos"
  else
    echo "$missing" | sed 's/^/  Missing package: /' >&2
    fail "Some packages were not found in pacman sync DB"
  fi
else
  echo "SKIP: pacman not found"
fi

echo "==> 5. Running isolated sandbox install & theme rendering test..."
tmp_home=$(mktemp -d)
trap 'rm -rf "$tmp_home"' EXIT

if HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" XDG_DATA_HOME="$tmp_home/.local/share" XDG_STATE_HOME="$tmp_home/.local/state" \
  QUATTRO_INSTALL_SANDBOX=1 "$PROJECT_DIR/install.sh" >/dev/null; then
  pass "Sandbox install.sh succeeded"
else
  fail "Sandbox install.sh failed"
fi

expected_files=(
  "$tmp_home/.bashrc"
  "$tmp_home/.XCompose"
  "$tmp_home/.config/hypr/hyprland.lua"
  "$tmp_home/.config/alacritty/alacritty.toml"
  "$tmp_home/.config/kitty/kitty.conf"
  "$tmp_home/.config/foot/foot.ini"
  "$tmp_home/.config/ghostty/config"
  "$tmp_home/.config/btop/btop.conf"
  "$tmp_home/.config/btop/themes/current.theme"
  "$tmp_home/.config/starship.toml"
  "$tmp_home/.config/satty/config.toml"
  "$tmp_home/.config/gtk-3.0/bookmarks"
  "$tmp_home/.config/tmux/tmux.conf"
  "$tmp_home/.config/brave-origin-flags.conf"
  "$tmp_home/.config/chrome-flags.conf"
  "$tmp_home/.config/chromium-flags.conf"
  "$tmp_home/.local/share/quattro/bin/quattro"
  "$tmp_home/.local/share/quattro/bin/quattro-build-titlebars"
  "$tmp_home/.local/share/quattro/default/hypr/titlebars/main.cpp"
  "$tmp_home/.local/share/quattro/config/quattro/shell.json"
  "$tmp_home/.local/bin/quattro"
  "$tmp_home/.local/state/quattro/current/theme/colors.toml"
  "$tmp_home/.local/state/quattro/current/theme/alacritty.toml"
  "$tmp_home/.local/state/quattro/current/theme/kitty.conf"
  "$tmp_home/.local/state/quattro/current/theme/foot.ini"
  "$tmp_home/.local/state/quattro/current/theme/ghostty.conf"
  "$tmp_home/.local/state/quattro/current/theme/btop.theme"
  "$tmp_home/.local/state/quattro/current/theme/hyprland.lua"
  "$tmp_home/.local/state/quattro/current/theme/qt6ct.colors"
  "$tmp_home/.local/state/quattro/current/theme/shell.toml"
  "$tmp_home/.local/state/quattro/current/theme/gtk.css"
  "$tmp_home/.config/gtk-4.0/gtk.css"
  "$tmp_home/.local/state/quattro/current/icons/org.gnome.Nautilus.svg"
  "$tmp_home/.local/share/icons/Quattro/scalable/places/folder.svg"
  "$tmp_home/.local/share/icons/Quattro-alt/scalable/places/folder.svg"
)

missing_deployed=0
for f in "${expected_files[@]}"; do
  if [[ ! -e $f ]]; then
    echo "  Missing deployed artifact: $f" >&2
    missing_deployed=$((missing_deployed + 1))
  fi
done
(( missing_deployed == 0 )) && pass "All expected configs and rendered theme files exist" || fail "$missing_deployed missing deployed file(s)"

flags_unresolved=0
for ff in "$tmp_home/.config/brave-origin-flags.conf" "$tmp_home/.config/chrome-flags.conf" "$tmp_home/.config/chromium-flags.conf"; do
  if grep -q '__QUATTRO_PATH__' "$ff" || grep -q '/usr/share/quattro' "$ff"; then
    echo "  Unresolved path in: $ff" >&2
    flags_unresolved=$((flags_unresolved + 1))
  fi
done
(( flags_unresolved == 0 )) && pass "Browser flag extension paths resolved to sandbox QUATTRO_PATH" || fail "$flags_unresolved browser flag file(s) still contain unresolved path"

if [[ -n $(HOME="$tmp_home" QUATTRO_PATH="$tmp_home/.local/share/quattro" "$tmp_home/.local/bin/quattro-version") ]]; then
  pass "quattro-version reports installed version"
else
  fail "quattro-version output unexpected"
fi

if (( failures == 0 )); then
  echo
  echo "ALL CHECKS PASSED."
  exit 0
else
  echo
  echo "$failures CHECK(S) FAILED." >&2
  exit 1
fi
