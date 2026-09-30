#!/usr/bin/env bash
# Work state for /jira-flow:work: one JSON file per issue key, kept out of the
# tree (under the repo's git dir by default, so nothing is committed and no
# protected folder is written at every step). `work.stateDir` in the config
# moves it.
#
#   state.sh dir                      print the state directory (created)
#   state.sh current [KEY]            print the current key, or set it
#   state.sh get KEY                  print the state JSON (exit 1 if none)
#   state.sh set KEY                  read JSON on stdin, validate, stamp, write; make it current
#   state.sh merge KEY '<jq filter>'  apply a jq filter to the stored state and write it back
#   state.sh list                     keys that have a state file
#   state.sh clear KEY                remove the state (and current, if it was this key)
set -u
. "$(dirname "$0")/config.sh"

jf_state_dir() {
  local d root gitdir
  root="$(jf_project_root)"
  d="$(jf_get '.work.stateDir')"
  if [ -z "$d" ]; then
    gitdir="$(git -C "$root" rev-parse --git-dir 2>/dev/null)"
    [ -z "$gitdir" ] && gitdir=".git"
    case "$gitdir" in /*) ;; *) gitdir="$root/$gitdir" ;; esac
    d="$gitdir/jira-flow"
  else
    case "$d" in /*) ;; *) d="$root/$d" ;; esac
  fi
  mkdir -p "$d" 2>/dev/null
  printf '%s' "$d"
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

cmd="${1:-}"
key="${2:-}"
dir="$(jf_state_dir)"

case "$cmd" in
  dir)
    printf '%s\n' "$dir" ;;
  current)
    if [ -n "$key" ]; then printf '%s\n' "$key" > "$dir/current"; fi
    if [ -f "$dir/current" ]; then cat "$dir/current"; fi ;;
  get)
    [ -n "$key" ] || { echo "state.sh get: a key is needed" >&2; exit 2; }
    if [ -f "$dir/$key.json" ]; then cat "$dir/$key.json"; else exit 1; fi ;;
  set)
    [ -n "$key" ] || { echo "state.sh set: a key is needed" >&2; exit 2; }
    tmp="$(mktemp)"
    cat > "$tmp"
    if jq -e --arg key "$key" --arg now "$(now)" \
         '.key = $key | .updatedAt = $now | .startedAt //= $now' "$tmp" > "$dir/$key.json.tmp" 2>/dev/null; then
      mv "$dir/$key.json.tmp" "$dir/$key.json"
      printf '%s\n' "$key" > "$dir/current"
      rm -f "$tmp"
    else
      rm -f "$tmp" "$dir/$key.json.tmp"
      echo "state.sh set: the input is not valid JSON" >&2
      exit 1
    fi ;;
  merge)
    [ -n "$key" ] || { echo "state.sh merge: a key is needed" >&2; exit 2; }
    filter="${3:-.}"
    [ -f "$dir/$key.json" ] || { echo "state.sh merge: no state for $key" >&2; exit 1; }
    if jq -e --arg now "$(now)" "($filter) | .updatedAt = \$now" "$dir/$key.json" > "$dir/$key.json.tmp" 2>/dev/null; then
      mv "$dir/$key.json.tmp" "$dir/$key.json"
    else
      rm -f "$dir/$key.json.tmp"
      echo "state.sh merge: the filter failed: $filter" >&2
      exit 1
    fi ;;
  list)
    for f in "$dir"/*.json; do
      [ -f "$f" ] || continue
      b="$(basename "$f")"
      printf '%s\n' "${b%.json}"
    done ;;
  clear)
    [ -n "$key" ] || { echo "state.sh clear: a key is needed" >&2; exit 2; }
    rm -f "$dir/$key.json"
    if [ "$(cat "$dir/current" 2>/dev/null)" = "$key" ]; then rm -f "$dir/current"; fi ;;
  *)
    echo "usage: state.sh dir | current [KEY] | get KEY | set KEY | merge KEY FILTER | list | clear KEY" >&2
    exit 2 ;;
esac
