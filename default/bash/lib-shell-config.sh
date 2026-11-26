#!/bin/bash

# Shared helpers for editing ~/.config/quattro/shell.json (source this, don't run it).

QUATTRO_PATH="${QUATTRO_PATH:-$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/../.." && pwd)}"
CONFIG_FILE="$HOME/.config/quattro/shell.json"
DEFAULTS_FILE="$QUATTRO_PATH/config/quattro/shell.json"

fail() {
  echo "${0##*/}: $*" >&2
  exit 1
}

refresh_shell_config() {
  if ! quattro-shell shell reloadConfig >/dev/null 2>&1; then
    quattro-shell -q shell rescanPlugins >/dev/null 2>&1 || true
  fi
}

source_file() {
  if [[ -s $CONFIG_FILE ]]; then
    printf '%s\n' "$CONFIG_FILE"
  else
    printf '%s\n' "$DEFAULTS_FILE"
  fi
}

NORMALIZE='
  def object_or_empty: if type == "object" then . else {} end;
  def array_or_empty: if type == "array" then . else [] end;
  object_or_empty
  | .version = 1
  | .bar = (.bar | object_or_empty)
  | .bar.layout = (.bar.layout | object_or_empty)
  | .bar.layout.left = (.bar.layout.left | array_or_empty)
  | .bar.layout.centerBegin = (.bar.layout.centerBegin | array_or_empty)
  | .bar.layout.center = (.bar.layout.center | array_or_empty)
  | .bar.layout.centerEnd = (.bar.layout.centerEnd | array_or_empty)
  | .bar.layout.right = (.bar.layout.right | array_or_empty)
  | .plugins = (.plugins | array_or_empty)
'

_SHELL_CONFIG_TMP=""
cleanup_shell_config_tmp() {
  if [[ -n $_SHELL_CONFIG_TMP ]]; then rm -f "$_SHELL_CONFIG_TMP"; fi
}
trap cleanup_shell_config_tmp EXIT

commit() {
  local program="$1"
  shift
  mkdir -p "${CONFIG_FILE%/*}"
  _SHELL_CONFIG_TMP=$(mktemp)
  jq -S -e "$@" "$program" "$(source_file)" >"$_SHELL_CONFIG_TMP" || fail "could not update shell config"
  mv "$_SHELL_CONFIG_TMP" "$CONFIG_FILE"
  _SHELL_CONFIG_TMP=""
  refresh_shell_config
}
