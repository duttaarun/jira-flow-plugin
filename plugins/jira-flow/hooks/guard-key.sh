#!/usr/bin/env bash
# PreToolUse on Bash: refuse `git commit`, `git push` and `gh pr create`
# unless the branch name or the command carries the project's issue key.
# Protected branches (`git.protectedBranches`, default main) are never
# committed to or pushed from. Exit 2 blocks, with the reason on stderr.
#
# Silent in a project without a jira-flow config. With `git.requireKey`
# false, only the protected-branch check remains.
. "$(dirname "$0")/../lib/config.sh"
[ -z "$(jf_config)" ] && exit 0

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# What may stand before the verb: the start, a separator, or a quote.
b='(^|[;&|`("'"'"'[:space:]])'
if ! printf '%s' "$cmd" | grep -qE "${b}git[[:space:]]+(commit|push)([[:space:]]|$)" \
   && ! printf '%s' "$cmd" | grep -qE "${b}gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)"; then
  exit 0
fi

cd "$(jf_project_root)" || exit 0
pk="$(jf_project_key)"
key_re="$(jf_key_regex)"
branch="$(git branch --show-current 2>/dev/null)"

if [ -n "$branch" ] && jf_has '.git.protectedBranches' "$branch"; then
  echo "jira-flow guard: never commit or push on '$branch'. Branch as ${pk}-<n>-<slug> first (/jira-flow:pr does this)." >&2
  exit 2
fi
[ "$(jf_get '.git.requireKey' 'true')" = "false" ] && exit 0
if [ -n "$key_re" ]; then
  printf '%s' "$branch" | grep -qE "$key_re" && exit 0
  printf '%s' "$cmd" | grep -qE "$key_re" && exit 0
fi
echo "jira-flow guard: branch '${branch:-detached}' carries no ${pk}-<n> key and neither does the command. Name the issue (/jira-flow:status, /jira-flow:plan), branch as ${pk}-<n>-<slug>, then retry." >&2
exit 2
