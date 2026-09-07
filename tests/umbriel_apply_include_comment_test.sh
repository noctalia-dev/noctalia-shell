#!/usr/bin/env bash

# apply.sh must close include.files on the real array ']', not a '#' comment's
# brackets. Otherwise wallpaper apply moves noctalia.toml into the comment and
# empties the array (noctalia-dev/noctalia#4332).

set -euo pipefail

apply_sh=${1:?apply.sh path}

fail() {
  printf '%s\n' "umbriel_apply_include_comment_test: FAIL: $*" >&2
  exit 1
}

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

files_line() {
  sed -n '/^[[:space:]]*files[[:space:]]*=/,$p' "$1"
}

run_apply() {
  local name=$1
  shift
  local home="$work_dir/$name"
  mkdir -p "$home/umbriel"
  printf '%s\n' "$@" >"$home/umbriel/config.toml"
  XDG_CONFIG_HOME="$home" bash "$apply_sh" \
    || fail "$name: apply.sh exited non-zero"
  files_line "$home/umbriel/config.toml"
}

expect() {
  local name=$1
  shift
  local want=$1
  shift
  local got
  got=$(run_apply "$name" "$@")
  if [ "$got" != "$want" ]; then
    fail "$name: expected $(printf '%q' "$want") got $(printf '%q' "$got")"
  fi
}

expect reporter \
  'files = ["noctalia.toml"] # []' \
  '[include]' \
  'files = ["noctalia.toml"] # []'

expect control_nocomment \
  'files = ["noctalia.toml"]' \
  '[include]' \
  'files = ["noctalia.toml"]'

expect control_comment \
  'files = ["noctalia.toml"] # keep this' \
  '[include]' \
  'files = ["noctalia.toml"] # keep this'

expect user_comment \
  'files = ["user.toml", "noctalia.toml"] # []' \
  '[include]' \
  'files = ["user.toml"] # []'

expect multiline \
  $'files = [\n  "user.toml",\n  "noctalia.toml",\n]' \
  '[include]' \
  'files = [' \
  '  "user.toml",' \
  ']'
