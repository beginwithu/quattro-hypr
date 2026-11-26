#!/bin/bash

set -euo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

echo "==> 1. Checking Bash & Python script syntax and executable bits..."
script_errors=0
py_scripts=()
while IFS= read -r -d '' script; do
  shebang=""
  IFS= read -r shebang <"$script" || true
  if [[ $shebang == *bash* || $script == *.sh || $script == "$PROJECT_DIR/default/bash/"* || $script == "$PROJECT_DIR/etc/profile.d/"* || $script == "$PROJECT_DIR/default/uwsm/"* ]]; then
    if ! bash -n "$script" 2>/dev/null; then
      echo "  Bash syntax error in: $script" >&2
      script_errors=$((script_errors + 1))
    fi
  elif [[ $shebang == *python* || $script == *.py ]]; then
    py_scripts+=("$script")
  fi
done < <(find "$PROJECT_DIR/install.sh" "$PROJECT_DIR/uninstall.sh" "$PROJECT_DIR/verify.sh" "$PROJECT_DIR/bin" "$PROJECT_DIR/default/bash" "$PROJECT_DIR/default/input-methods" "$PROJECT_DIR/default/uwsm" "$PROJECT_DIR/etc/profile.d" "$PROJECT_DIR/shell" -type f \( ! -path "$PROJECT_DIR/shell/*" -o -name '*.sh' -o -name '*.py' \) -print0)
if (( ${#py_scripts[@]} > 0 )); then
  py_bad=$(python3 -B - "${py_scripts[@]}" <<'PY'
import ast, sys
for p in sys.argv[1:]:
    try:
        with open(p, "rb") as fh:
            ast.parse(fh.read(), filename=p)
    except Exception:
        print(p)
PY
  )
  if [[ -n $py_bad ]]; then
    while IFS= read -r pf; do
      echo "  Python syntax error in: $pf" >&2
      script_errors=$((script_errors + 1))
    done <<<"$py_bad"
  fi
fi
while IFS= read -r -d '' bin_file; do
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

echo "==> 3. Checking JSON, JSONC & XML configs..."
json_errors=0
# One Python process for every JSON, JSONC, and XML config file.
json_bad=$(find \
  "$PROJECT_DIR/config/quattro/shell.json" \
  "$PROJECT_DIR/etc/fastfetch/config.jsonc" \
  "$PROJECT_DIR/default/i18n" \
  "$PROJECT_DIR/shell/plugins" \
  "$PROJECT_DIR/themes" \
  -type f \( -name '*.json' -o -name 'config.jsonc' \) -print0 |
  python3 -B -c '
import json, re, sys, xml.etree.ElementTree as ET
for path in filter(None, sys.stdin.buffer.read().split(b"\0")):
    try:
        with open(path, "rb") as fh:
            json.load(fh)
    except Exception:
        print("JSON\t" + path.decode(errors="replace"))
for arg in sys.argv[1:]:
    if arg.endswith(".conf"):
        try:
            ET.parse(arg)
        except Exception:
            print("XML\t" + arg)
    else:
        try:
            raw = open(arg, encoding="utf-8").read()
            clean = re.sub(r"^\s*//.*$", "", raw, flags=re.M)
            clean = re.sub(r",(\s*[}\]])", r"\1", clean)
            json.loads(clean)
        except Exception:
            print("JSONC\t" + arg)
' "$PROJECT_DIR/default/quattro/quattro-menu.jsonc" \
  "$PROJECT_DIR/config/quattro/extensions/quattro-menu.jsonc" \
  "$PROJECT_DIR/default/fontconfig/conf.avail/50-quattro.conf")
if [[ -n $json_bad ]]; then
  while IFS=$'\t' read -r kind jf; do
    echo "  Invalid $kind: $jf" >&2
    json_errors=$((json_errors + 1))
  done <<<"$json_bad"
fi
(( json_errors == 0 )) && pass "All JSON, JSONC & XML config files parse cleanly" || fail "$json_errors JSON/XML error(s)"

echo "==> 4. Checking CLI metadata, menu commands & repository hygiene..."
if "$PROJECT_DIR/bin/quattro" commands --check >/dev/null 2>&1; then
  pass "All quattro-* CLI command metadata & routes are valid"
else
  fail "quattro commands --check failed"
fi

if python3 -B - "$PROJECT_DIR" <<'PY'
import glob, json, os, re, sys
root = sys.argv[1]
bins = {os.path.basename(p) for p in glob.glob(os.path.join(root, "bin/*"))}
plugin_ids = set()
for mf in glob.glob(os.path.join(root, "shell/plugins/**/*manifest.json"), recursive=True):
    try:
        plugin_ids.add(json.load(open(mf)).get("id", ""))
    except Exception:
        pass

raw = open(os.path.join(root, "default/quattro/quattro-menu.jsonc")).read()
clean = re.sub(r"^\s*//.*$", "", raw, flags=re.M)
clean = re.sub(r",(\s*[}\]])", r"\1", clean)
menu = json.loads(clean)
errors = 0
for k, v in menu.items():
    for field in ("action", "when", "checked", "disabled"):
        text = v.get(field, "")
        for m in re.finditer(r"\b(quattro-[a-z0-9-]+)\b", text):
            cmd = m.group(1)
            if cmd == "quattro-hypr":
                continue
            if cmd not in bins:
                print(f"  Menu entry '{k}' ({field}) references missing command: {cmd}", file=sys.stderr)
                errors += 1
sys.exit(1 if errors else 0)
PY
then
  pass "All quattro-* commands in quattro-menu.jsonc exist in bin/"
else
  fail "Menu references missing quattro-* command(s)"
fi

hygiene_hits=$(grep -rnI -iE "omarchy|quattro-platform|quattro-settings|quattro-pkgs|quattro-1password|quattro-webapp-handler|\ban [Qq]uattro\b|skip-cursor-theme-changes|whatsapp-slim" \
  --exclude-dir=.git --exclude=REVISION_PLAN.md --exclude=verify.sh "$PROJECT_DIR" || true)
if [[ -z $hygiene_hits ]]; then
  pass "Repository is clean of Omarchy, removed-tool, and fictional package references"
else
  echo "$hygiene_hits" | sed 's/^/  Hygiene violation: /' >&2
  fail "Found forbidden legacy references"
fi

strict_missing=()
while IFS= read -r -d '' bin_file; do
  shebang=""
  IFS= read -r shebang <"$bin_file" || true
  [[ $shebang == *bash* ]] || continue
  grep -qE '^[[:space:]]*set -[eu]+o pipefail' "$bin_file" || strict_missing+=("${bin_file#"$PROJECT_DIR"/}")
done < <(find "$PROJECT_DIR/bin" -maxdepth 1 -type f -print0)
if (( ${#strict_missing[@]} == 0 )); then
  pass "Every Bash script in bin/ enables strict mode (set -[e]uo pipefail)"
else
  printf '  Missing strict mode: %s\n' "${strict_missing[@]}" >&2
  fail "${#strict_missing[@]} bin/ script(s) without strict mode"
fi

# Any quattro-* name that once lived in bin/ but is gone now must not be
# referenced anymore (catches callers left behind by consolidation).
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  if python3 -B - "$PROJECT_DIR" <<'PY'
import os, re, subprocess, sys
root = sys.argv[1]
hist = subprocess.run(["git", "-C", root, "log", "--all", "--name-only", "--format=", "--", "bin/"],
                      capture_output=True, text=True).stdout.split()
gone = {p[4:] for p in hist if p.startswith("bin/quattro-")} - set(os.listdir(os.path.join(root, "bin")))
# Desktop entry / icon ids (applications/<id>.desktop) share the prefix legitimately.
gone -= {f[:-8] for f in os.listdir(os.path.join(root, "applications")) if f.endswith(".desktop")}
pat = re.compile(r"(?<![\w.-])(quattro-[a-z0-9]+(?:-[a-z0-9]+)*)(?![\w-]|\.[A-Za-z])")
errors = 0
for top in ("bin", "default", "config", "shell", "etc", "applications", "install.sh"):
    base = os.path.join(root, top)
    files = [base] if os.path.isfile(base) else [os.path.join(d, f) for d, _, fs in os.walk(base) for f in fs]
    for path in files:
        try:
            lines = open(path, encoding="utf-8").read().splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        for n, line in enumerate(lines, 1):
            for m in pat.finditer(line):
                if m.group(1) in gone:
                    print(f"  {os.path.relpath(path, root)}:{n}: removed command {m.group(1)}", file=sys.stderr)
                    errors += 1
sys.exit(1 if errors else 0)
PY
  then
    pass "No references to removed/consolidated quattro-* commands"
  else
    fail "Found references to removed quattro-* commands"
  fi
else
  echo "SKIP: not a git checkout (skipping removed-command reference check)"
fi

echo "==> 5. Verifying Arch repository package lists..."
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

echo "==> 6. Running isolated sandbox install & theme rendering test..."
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
  "$tmp_home/.config/foot/foot.ini"
  "$tmp_home/.config/btop/btop.conf"
  "$tmp_home/.config/btop/themes/current.theme"
  "$tmp_home/.config/starship.toml"
  "$tmp_home/.config/satty/config.toml"
  "$tmp_home/.config/gtk-3.0/bookmarks"
  "$tmp_home/.config/tmux/tmux.conf"
  "$tmp_home/.config/brave-origin-flags.conf"
  "$tmp_home/.local/share/quattro/bin/quattro"
  "$tmp_home/.local/share/quattro/bin/quattro-build-titlebars"
  "$tmp_home/.local/share/quattro/default/hypr/titlebars/main.cpp"
  "$tmp_home/.local/share/quattro/config/quattro/shell.json"
  "$tmp_home/.local/bin/quattro"
  "$tmp_home/.local/state/quattro/current/theme/colors.toml"
  "$tmp_home/.local/state/quattro/current/theme/foot.ini"
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
