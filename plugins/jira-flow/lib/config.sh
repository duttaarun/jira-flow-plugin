#!/usr/bin/env bash
# Shared by the hooks: find the project's jira-flow config and read from it.
# Sourced, never executed. Needs jq.
#
# The config is `.claude/jira-flow.json` at the project root (written by
# /jira-flow:init); JIRA_FLOW_CONFIG points somewhere else when set. Every
# reader treats a missing config as "this project is not traced": the guard
# and the context hook stay silent, the ship gate falls back to its defaults.
#
# The project root is found from where the call runs, not where the session
# started: a session opened in ~/projects that works in ~/projects/app must
# read app's config. In order:
#   1. the repo holding the call's folder (its git toplevel, or the folder
#      itself outside git), when that root has a config. The call's folder is
#      the hook input's `cwd` (see jf_use_input), else this process's $PWD.
#   2. CLAUDE_PROJECT_DIR, the folder the session started in.
#   3. the git toplevel of $PWD, else $PWD.
# A call's root without a config falls through to 2, so a session started in
# a configured repo keeps its config from a sub-folder or a scratch folder.

# The call's folder, set by jf_use_input; empty means $PWD.
JF_CWD=""

# jf_use_input <hook JSON>: take the call's folder from the input's `cwd`.
# Each hook calls this once, before its first jf_* lookup.
jf_use_input() {
  JF_CWD="$(printf '%s' "$1" | jq -r '.cwd // empty' 2>/dev/null)"
}

jf_project_root() {
  local cwd="${JF_CWD:-$PWD}" root
  if [ -n "$cwd" ]; then
    root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || root="$cwd"
    if [ -f "$root/.claude/jira-flow.json" ]; then printf '%s' "$root"; return; fi
  fi
  root="${CLAUDE_PROJECT_DIR:-}"
  if [ -z "$root" ]; then root="$(git rev-parse --show-toplevel 2>/dev/null)"; fi
  if [ -z "$root" ]; then root="$PWD"; fi
  printf '%s' "$root"
}

# The config path, or nothing when the project has none.
jf_config() {
  local p="${JIRA_FLOW_CONFIG:-}"
  if [ -z "$p" ]; then p="$(jf_project_root)/.claude/jira-flow.json"; fi
  if [ -f "$p" ]; then printf '%s' "$p"; fi
}

# jf_get <jq path> [default]: one scalar from the config, else the default.
jf_get() {
  local cfg v="" dflt="${2:-}"
  cfg="$(jf_config)"
  # `false` is a value, not an absence: only null and a missing key fall back.
  if [ -n "$cfg" ]; then v="$(jq -r "if ($1) == null then empty else ($1) end" "$cfg" 2>/dev/null)"; fi
  printf '%s' "${v:-$dflt}"
}

# jf_has <jq path> <value>: true when the array at the path holds the value.
jf_has() {
  local cfg
  cfg="$(jf_config)"
  [ -n "$cfg" ] && jq -e --arg v "$2" "($1 // []) | index(\$v) != null" "$cfg" >/dev/null 2>&1
}

jf_project_key() { jf_get '.jira.projectKey'; }

# The regex an issue key of this project matches, e.g. `SCRUM-[0-9]+`.
jf_key_regex() {
  local k
  k="$(jf_project_key)"
  if [ -n "$k" ]; then printf '%s-[0-9]+' "$k"; fi
}

jf_site() { jf_get '.jira.site' "${JIRA_SITE_URL:-}"; }

# jf_asks <act>: whether the ship gate asks before this act (pr, merge, close).
# Without a config, or without the list, every act asks.
jf_asks() {
  local cfg
  cfg="$(jf_config)"
  if [ -z "$cfg" ]; then return 0; fi
  if ! jq -e '.ship.askBefore | type == "array"' "$cfg" >/dev/null 2>&1; then return 0; fi
  jf_has '.ship.askBefore' "$1"
}
