#!/usr/bin/env bash
# PreToolUse: nothing ships or closes without the reader's yes.
#
# Raising a pull request, merging one, and moving a Jira issue to Done are
# outward-facing and hard to take back, so each stops at a permission prompt
# however the session got there. Everything before them (branching,
# committing, pushing a feature branch, creating and updating issues) is left
# alone, so the whole flow can be prepared automatically and the reader is
# asked once, at the end, for the step that publishes it.
#
# Reads the PreToolUse JSON on stdin; prints a permission decision of "ask"
# for the gated calls and stays silent (exit 0) for everything else. Covers
# the shell (`gh pr create`, `gh pr ready`, `gh pr merge`, `git merge`, the
# merge API), the GitHub MCP tools, and the Atlassian MCP when a transition
# targets a done-like status.
#
# `ship.askBefore` in the project's config (default ["pr", "merge", "close"])
# chooses which acts ask; `jira.transitions.done` names the closing
# transition id, with done/close/resolve/complete matched by name as well.
. "$(dirname "$0")/../lib/config.sh"

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"

ask() {
  jq -cn --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

rule="The rule (jira-flow ship gate) is that this only happens when you have asked for it in the prompt that is running."

case "$tool" in
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    # What may stand before the verb: the start, a separator, or a quote. A
    # command wrapped in `bash -c "..."` or `ssh host "..."` ships just as
    # surely as a bare one. A mention inside a grep pattern asks too; a
    # needless prompt is the cheap side of this trade.
    b='(^|[;&|`("'"'"'[:space:]])'
    if jf_asks pr; then
      if printf '%s' "$cmd" | grep -qE "${b}gh[[:space:]]+pr[[:space:]]+(create|ready)([[:space:]]|\"|'|$)"; then
        ask "Raising a pull request. $rule"
      fi
    fi
    if jf_asks merge; then
      if printf '%s' "$cmd" | grep -qE "${b}gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|\"|'|$)"; then
        ask "Merging a pull request. $rule"
      fi
      if printf '%s' "$cmd" | grep -qE "${b}git[[:space:]]+merge([[:space:]]|\"|'|$)"; then
        ask "Merging a branch. $rule"
      fi
      if printf '%s' "$cmd" | grep -qE 'gh[[:space:]]+api' && printf '%s' "$cmd" | grep -qE '/pulls/[0-9]+/merge'; then
        ask "Merging a pull request through the GitHub API. $rule"
      fi
    fi
    ;;
  mcp__github__create_pull_request)
    jf_asks pr && ask "Raising a pull request (GitHub MCP). $rule"
    ;;
  mcp__github__merge_pull_request)
    jf_asks merge && ask "Merging a pull request (GitHub MCP). $rule"
    ;;
  mcp__atlassian__transitionJiraIssue)
    # Issues may be created and moved along freely; only CLOSING one asks.
    jf_asks close || exit 0
    done_id="$(jf_get '.jira.transitions.done')"
    id="$(printf '%s' "$input" | jq -r '.tool_input.transitionId // empty' 2>/dev/null)"
    name="$(printf '%s' "$input" | jq -r '(.tool_input.transitionName // .tool_input.transition.name // "") | ascii_downcase' 2>/dev/null)"
    key="$(printf '%s' "$input" | jq -r '.tool_input.issueIdOrKey // "the issue"' 2>/dev/null)"
    if { [ -n "$done_id" ] && [ "$id" = "$done_id" ]; } || printf '%s' "$name" | grep -qE 'done|close|resolve|complete'; then
      ask "Closing $key in Jira. $rule Issues may be created and moved along without asking; closing one waits for your word."
    fi
    # Without a config there is no closing id to compare against, and an id
    # alone says nothing: ask, and let the reader answer. /jira-flow:init
    # makes this precise.
    if [ -z "$done_id" ] && [ -z "$name" ]; then
      ask "Transitioning $key in Jira (id ${id:-?}). No jira-flow config names the closing transition, so this may be a close; run /jira-flow:init to make the gate precise."
    fi
    ;;
  mcp__atlassian__executeWrite|mcp__atlassian__executeDestructive)
    # A transition run through the generic execute tools cannot be read for
    # its target, so it asks whenever the operation is a transition.
    jf_asks close || exit 0
    op="$(printf '%s' "$input" | jq -r '(.tool_input.name // "") | ascii_downcase' 2>/dev/null)"
    if printf '%s' "$op" | grep -qE 'transition'; then
      key="$(printf '%s' "$input" | jq -r '.tool_input.inputs.issueIdOrKey // .tool_input.inputs.issueKey // "the issue"' 2>/dev/null)"
      ask "Transitioning $key through $op. $rule If this closes the issue it needs your word; use transitionJiraIssue for ordinary moves so the gate can read the target."
    fi
    ;;
esac
exit 0
