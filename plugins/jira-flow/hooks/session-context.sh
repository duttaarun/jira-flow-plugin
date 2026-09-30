#!/usr/bin/env bash
# SessionStart: say which issue the branch carries and whether a story is
# mid-flow, so the session picks up where the last one stopped. Silent in a
# project without a jira-flow config.
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../lib/config.sh"
cfg="$(jf_config)"
[ -z "$cfg" ] && exit 0
root="$(jf_project_root)"
cd "$root" || exit 0

pk="$(jf_project_key)"
key_re="$(jf_key_regex)"
site="$(jf_site)"
branch="$(git branch --show-current 2>/dev/null)"
key=""
[ -n "$key_re" ] && key="$(printf '%s' "$branch" | grep -oE "$key_re" | head -1)"
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

echo "jira-flow: project ${pk:-?} at ${site:-?} (config .claude/jira-flow.json)"
echo "  branch: ${branch:-detached}"
if [ -n "$key" ]; then
  echo "  issue:  $key  ($site/browse/$key)"
else
  echo "  issue:  none in the branch name. Before editing, name the story: /jira-flow:status shows the board, /jira-flow:work <key> picks one up."
fi
echo "  tree:   ${dirty} changed file(s)"

current="$(bash "$here/../lib/state.sh" current 2>/dev/null)"
if [ -n "$current" ]; then
  bash "$here/../lib/state.sh" get "$current" 2>/dev/null | jq -r '
    "  work:   \(.key) \"\(.summary // "")\": phase \(.phase // "?"), "
    + "\((.plan // []) | map(select(.status == "done")) | length)/\((.plan // []) | length) steps done"
    + (if .checkpoint == "phase" then ", running to the gates" else "" end)
    + ". Resume with /jira-flow:work \(.key); /jira-flow:work --status shows the plan."
  ' 2>/dev/null
fi
others="$(bash "$here/../lib/state.sh" list 2>/dev/null | grep -v -x -F "${current:-__none__}" | tr '\n' ' ')"
if [ -n "${others// /}" ]; then
  echo "  parked: ${others}(each resumes with /jira-flow:work <key>)"
fi
exit 0
