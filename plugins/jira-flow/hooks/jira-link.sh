#!/usr/bin/env bash
# PostToolUse: after any Atlassian MCP call that creates, edits, moves,
# comments on or deletes a Jira issue, show the issue's direct link so the
# change can be checked in the browser. Reads the hook JSON on stdin, prints
# a {"systemMessage": ...} for the UI. Never fails the tool call.
#
# The site comes from the project's config, else JIRA_SITE_URL, else the
# `self` URL in the tool's response; with none of those the key alone shows.
set -u
. "$(dirname "$0")/../lib/config.sh"

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""')"

# The key: from the input (edit/transition/comment/execute*), else from the
# response (create returns the new key).
key="$(printf '%s' "$input" | jq -r '
  .tool_input.issueIdOrKey
  // .tool_input.inputs.issueIdOrKey
  // .tool_input.inputs.issueKey
  // empty' 2>/dev/null)"
if ! printf '%s' "$key" | grep -qE '^[A-Z][A-Z0-9]*-[0-9]+$'; then
  key="$(printf '%s' "$input" | jq -r '.tool_response | tostring' 2>/dev/null \
    | tr -d '\\' | grep -oE '"key":"[A-Z][A-Z0-9]*-[0-9]+"' | head -1 | grep -oE '[A-Z][A-Z0-9]*-[0-9]+')"
fi
[ -z "$key" ] && exit 0

site="$(jf_site)"
if [ -z "$site" ]; then
  site="$(printf '%s' "$input" | jq -r '.tool_response | tostring' 2>/dev/null \
    | tr -d '\\' | grep -oE 'https://[a-z0-9.-]+\.atlassian\.net' | head -1)"
fi

case "$tool" in
  *createJiraIssue)            what="created" ;;
  *editJiraIssue)              what="edited" ;;
  *transitionJiraIssue)
    status="$(printf '%s' "$input" | jq -r '.tool_response | tostring' 2>/dev/null \
      | grep -oE '"statusName":"[^"]+"' | head -1 | cut -d'"' -f4)"
    what="moved to ${status:-a new status}" ;;
  *addOrEditJiraIssueComment)  what="commented" ;;
  *executeDestructive)
    op="$(printf '%s' "$input" | jq -r '.tool_input.name // "destructive op"')"
    what="$op (destructive)" ;;
  *executeWrite)
    op="$(printf '%s' "$input" | jq -r '.tool_input.name // "write op"')"
    what="$op" ;;
  *)                           what="changed" ;;
esac

if [ -n "$site" ]; then
  jq -cn --arg msg "Jira ${key} ${what}: ${site}/browse/${key}" '{systemMessage: $msg}'
else
  jq -cn --arg msg "Jira ${key} ${what} (set jira.site in .claude/jira-flow.json for a link)" '{systemMessage: $msg}'
fi
