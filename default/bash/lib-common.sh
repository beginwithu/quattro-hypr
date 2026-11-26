#!/bin/bash

# Shared Quattro Bash helper functions for QUATTRO_PATH resolution, logging,
# argument checks, gum theme environment export, sudo keepalive, and TUI prompts.

quattro_resolve_path() {
  if [[ -n ${QUATTRO_PATH:-} && -d $QUATTRO_PATH ]]; then
    export QUATTRO_PATH
    return 0
  fi

  local candidate
  for candidate in "$HOME/.local/share/quattro" "/usr/share/quattro"; do
    if [[ -d $candidate ]]; then
      export QUATTRO_PATH="$candidate"
      return 0
    fi
  done

  export QUATTRO_PATH="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")")/.." && pwd)"
}

quattro_log_info() {
  printf '==> %s\n' "$*"
}

quattro_log_warn() {
  printf 'Warning: %s\n' "$*" >&2
}

quattro_die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

quattro_require_args() {
  local min_args="$1"
  local usage_msg="$2"
  shift 2
  if (( $# < min_args )); then
    printf 'Usage: %s\n' "$usage_msg" >&2
    exit 1
  fi
}

quattro_restart_gum() {
  local gum_env="$HOME/.local/state/quattro/current/theme/gum_env.lua"
  [[ -f $gum_env ]] || return 0
  local line key value
  while IFS= read -r line; do
    if [[ $line =~ hl\.env\(\"([A-Z0-9_]+)\",[[:space:]]*\"([^\"]+)\"\) ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      export "$key=$value"
    fi
  done <"$gum_env"
}

quattro_show_logo() {
  clear
  if [[ -f $QUATTRO_PATH/logo.txt ]]; then
    printf '\033[32m\n%s\n\033[0m\n\n' "$(<"$QUATTRO_PATH/logo.txt")"
  else
    printf '\033[32m\n\033[0m\n\n'
  fi
}

quattro_show_done() {
  local code="${1:-0}"
  : 2>/dev/null <>/dev/tty || return 0
  while read -rsn 1 -t 0.1 _ </dev/tty; do :; done
  if (( code == 0 )); then
    printf '\n\033[32m● \033[0m%s' "$(quattro-i18n done.success)" >/dev/tty
  else
    printf '\n\033[31m● \033[0m%s' "$(quattro-i18n done.failed "$code")" >/dev/tty
  fi
  read -rsn 1 </dev/tty || true
  echo >/dev/tty
}

quattro_sudo_keepalive() {
  sudo -v
  while true; do sudo -n true; sleep 60; done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null || true" EXIT
}

quattro_theme_osc() {
  local theme="${1:-$HOME/.local/state/quattro/current/theme/colors.toml}"
  [[ -f $theme ]] || return 0
  local -A colors=()
  local key value i
  while IFS=$'\t' read -r key value; do
    colors[$key]="$value"
  done < <(quattro-theme-color --file "$theme" --all)

  emit_osc() {
    [[ -n ${colors[$2]:-} ]] && printf '\033]%s;%s\007' "$1" "${colors[$2]}" || true
  }

  emit_osc 10 foreground
  emit_osc 11 background
  emit_osc 12 cursor
  emit_osc 17 selection_background
  emit_osc 19 selection_foreground

  for i in {0..15}; do
    [[ -n ${colors[color$i]:-} ]] || continue
    printf '\033]4;%d;%s\007' "$i" "${colors[color$i]}"
  done
}

quattro_resolve_path
