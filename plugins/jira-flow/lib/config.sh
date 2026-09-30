#!/usr/bin/env bash
# Shared by the hooks: find the project's jira-flow config and read from it.
# Sourced, never executed. Needs jq.
#
# The config is `.claude/jira-flow.json` at the project root (written by
# /jira-flow:init); JIRA_FLOW_CONFIG points somewhere else when set. Every
# reader treats a missing config as "this project is not traced": the guard
# and the context hook stay silent, the ship gate falls back to its defaults.

jf_project_root() {
  local root="${CLAUDE_PROJECT_DIR:-}"
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
