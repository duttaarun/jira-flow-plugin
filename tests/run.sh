#!/usr/bin/env bash
# Tests for the hooks and the state store. No Jira, no GitHub: every hook is
# fed the JSON Claude Code would send, in a throwaway git repo with a config.
#   bash tests/run.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
plugin="$here/../plugins/jira-flow"
tmp="$here/.tmp"
rm -rf "$tmp"
mkdir -p "$tmp"

pass=0
fail=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n       %s\n' "$1" "$2"; }

# check <name> <expected exit> <actual exit> <stdout> <stdout must contain (or "" for empty)> [<stderr> <stderr must contain>]
check() {
  local name="$1" want="$2" got="$3" out="$4" want_out="$5" err="${6:-}" want_err="${7:-}"
  if [ "$want" != "$got" ]; then bad "$name" "exit $got, wanted $want; stdout: $out; stderr: $err"; return; fi
  if [ -z "$want_out" ]; then
    [ -z "$out" ] || { bad "$name" "wanted no stdout, got: $out"; return; }
  else
    printf '%s' "$out" | grep -qF -- "$want_out" || { bad "$name" "stdout lacks '$want_out': $out"; return; }
  fi
  if [ -n "$want_err" ]; then
    printf '%s' "$err" | grep -qF -- "$want_err" || { bad "$name" "stderr lacks '$want_err': $err"; return; }
  fi
  ok "$name"
}

# run_hook <script> <json> -> sets OUT, ERR, RC
run_hook() {
  local errf="$tmp/err"
  OUT="$(printf '%s' "$2" | bash "$plugin/hooks/$1" 2>"$errf")"
  RC=$?
  ERR="$(cat "$errf")"
}

bash_json() { jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}'; }

# A project with a config.
proj="$tmp/proj"
mkdir -p "$proj/.claude"
git -C "$proj" init -q -b main
git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cat > "$proj/.claude/jira-flow.json" <<'EOF'
{
  "version": 1,
  "jira": { "site": "https://example.atlassian.net", "projectKey": "TEST",
            "transitions": { "todo": "11", "inProgress": "21", "inReview": "31", "done": "41" } },
  "git": { "baseBranch": "main", "protectedBranches": ["main"], "requireKey": true },
  "ship": { "askBefore": ["pr", "merge", "close"] }
}
EOF
# A project without one.
bare="$tmp/bare"
mkdir -p "$bare"
git -C "$bare" init -q -b main
git -C "$bare" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

export CLAUDE_PROJECT_DIR="$proj"
unset JIRA_FLOW_CONFIG JIRA_SITE_URL

echo "guard-key"
CLAUDE_PROJECT_DIR="$bare" run_hook guard-key.sh "$(bash_json 'git commit -m x')"
check "no config: silent" 0 "$RC" "$OUT" ""
run_hook guard-key.sh "$(bash_json 'ls -la')"
check "unrelated command: silent" 0 "$RC" "$OUT" ""
run_hook guard-key.sh "$(bash_json 'git commit -m "x"')"
check "commit on main: blocked" 2 "$RC" "$OUT" "" "$ERR" "never commit or push on 'main'"
run_hook guard-key.sh "$(bash_json 'git push origin main')"
check "push on main: blocked" 2 "$RC" "$OUT" "" "$ERR" "never commit or push on 'main'"
git -C "$proj" checkout -q -b feature-x
run_hook guard-key.sh "$(bash_json 'git commit -m "x"')"
check "commit on keyless branch: blocked" 2 "$RC" "$OUT" "" "$ERR" "carries no TEST-<n> key"
run_hook guard-key.sh "$(bash_json 'git commit -m "TEST-12: x"')"
check "key in the command: allowed" 0 "$RC" "$OUT" ""
run_hook guard-key.sh "$(bash_json 'gh pr create --title x')"
check "gh pr create without a key: blocked" 2 "$RC" "$OUT" "" "$ERR" "carries no TEST-<n> key"
run_hook guard-key.sh "$(bash_json 'git commitment-note')"
check "git commitment-note is not git commit: silent" 0 "$RC" "$OUT" ""
git -C "$proj" checkout -q -b TEST-12-slug
run_hook guard-key.sh "$(bash_json 'git commit -m "x"')"
check "commit on a keyed branch: allowed" 0 "$RC" "$OUT" ""
run_hook guard-key.sh "$(bash_json 'git push -u origin TEST-12-slug')"
check "push on a keyed branch: allowed" 0 "$RC" "$OUT" ""
# requireKey false keeps only the protected-branch check.
jq '.git.requireKey = false' "$proj/.claude/jira-flow.json" > "$tmp/c.json" && mv "$tmp/c.json" "$proj/.claude/jira-flow.json"
git -C "$proj" checkout -q feature-x
run_hook guard-key.sh "$(bash_json 'git commit -m "x"')"
check "requireKey false: keyless branch allowed" 0 "$RC" "$OUT" ""
git -C "$proj" checkout -q main
run_hook guard-key.sh "$(bash_json 'git commit -m "x"')"
check "requireKey false: main still blocked" 2 "$RC" "$OUT" "" "$ERR" "never commit or push on 'main'"
jq '.git.requireKey = true' "$proj/.claude/jira-flow.json" > "$tmp/c.json" && mv "$tmp/c.json" "$proj/.claude/jira-flow.json"
git -C "$proj" checkout -q TEST-12-slug

echo "ask-before-ship"
ASK='"permissionDecision":"ask"'
run_hook ask-before-ship.sh "$(bash_json 'gh pr create --title "[TEST-12] x" --body-file b.md')"
check "gh pr create: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh "$(bash_json 'gh pr ready 12')"
check "gh pr ready: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh "$(bash_json 'gh pr merge 12 --merge --delete-branch')"
check "gh pr merge: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh "$(bash_json 'git merge TEST-12-slug')"
check "git merge: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh "$(bash_json 'gh api -X PUT repos/o/r/pulls/12/merge')"
check "merge through the API: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh "$(bash_json 'bash -c "cd x && gh pr merge 12"')"
check "wrapped gh pr merge: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh "$(bash_json 'git push -u origin TEST-12-slug')"
check "git push: silent" 0 "$RC" "$OUT" ""
run_hook ask-before-ship.sh "$(bash_json 'git commit -m "TEST-12: x"')"
check "git commit: silent" 0 "$RC" "$OUT" ""
run_hook ask-before-ship.sh "$(bash_json 'gh pr list --state open')"
check "gh pr list: silent" 0 "$RC" "$OUT" ""
run_hook ask-before-ship.sh "$(bash_json 'git merge-base main HEAD')"
check "git merge-base: silent" 0 "$RC" "$OUT" ""
run_hook ask-before-ship.sh '{"tool_name":"mcp__github__create_pull_request","tool_input":{"title":"x"}}'
check "GitHub MCP create PR: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh '{"tool_name":"mcp__github__merge_pull_request","tool_input":{"pullNumber":12}}'
check "GitHub MCP merge PR: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh '{"tool_name":"mcp__atlassian__transitionJiraIssue","tool_input":{"issueIdOrKey":"TEST-12","transitionId":"41"}}'
check "transition to the done id: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh '{"tool_name":"mcp__atlassian__transitionJiraIssue","tool_input":{"issueIdOrKey":"TEST-12","transitionId":"21"}}'
check "transition to In Progress: silent" 0 "$RC" "$OUT" ""
run_hook ask-before-ship.sh '{"tool_name":"mcp__atlassian__transitionJiraIssue","tool_input":{"issueIdOrKey":"TEST-12","transitionId":"99","transitionName":"Resolve"}}'
check "transition named Resolve: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh '{"tool_name":"mcp__atlassian__transitionJiraIssue","tool_input":{"issueIdOrKey":"TEST-12","transitionId":"31","transitionName":"In Review"}}'
check "transition named In Review: silent" 0 "$RC" "$OUT" ""
run_hook ask-before-ship.sh '{"tool_name":"mcp__atlassian__executeWrite","tool_input":{"name":"transitionJiraIssueV2","inputs":{"issueIdOrKey":"TEST-12"}}}'
check "executeWrite transition: asks" 0 "$RC" "$OUT" "$ASK"
run_hook ask-before-ship.sh '{"tool_name":"mcp__atlassian__executeWrite","tool_input":{"name":"editIssueLabels","inputs":{"issueIdOrKey":"TEST-12"}}}'
check "executeWrite edit: silent" 0 "$RC" "$OUT" ""
run_hook ask-before-ship.sh '{"tool_name":"Read","tool_input":{"file_path":"x"}}'
check "other tool: silent" 0 "$RC" "$OUT" ""
# askBefore narrowed to merge and close.
jq '.ship.askBefore = ["merge", "close"]' "$proj/.claude/jira-flow.json" > "$tmp/c.json" && mv "$tmp/c.json" "$proj/.claude/jira-flow.json"
run_hook ask-before-ship.sh "$(bash_json 'gh pr create --title x')"
check "askBefore without pr: gh pr create silent" 0 "$RC" "$OUT" ""
run_hook ask-before-ship.sh "$(bash_json 'gh pr merge 12')"
check "askBefore with merge: gh pr merge asks" 0 "$RC" "$OUT" "$ASK"
jq '.ship.askBefore = ["pr", "merge", "close"]' "$proj/.claude/jira-flow.json" > "$tmp/c.json" && mv "$tmp/c.json" "$proj/.claude/jira-flow.json"
# No config: every act asks; a bare transition id asks too.
CLAUDE_PROJECT_DIR="$bare" run_hook ask-before-ship.sh "$(bash_json 'gh pr create')"
check "no config: gh pr create asks" 0 "$RC" "$OUT" "$ASK"
CLAUDE_PROJECT_DIR="$bare" run_hook ask-before-ship.sh '{"tool_name":"mcp__atlassian__transitionJiraIssue","tool_input":{"issueIdOrKey":"X-1","transitionId":"41"}}'
check "no config: bare transition id asks" 0 "$RC" "$OUT" "$ASK"
CLAUDE_PROJECT_DIR="$bare" run_hook ask-before-ship.sh '{"tool_name":"mcp__atlassian__transitionJiraIssue","tool_input":{"issueIdOrKey":"X-1","transitionId":"21","transitionName":"In Progress"}}'
check "no config: named In Progress silent" 0 "$RC" "$OUT" ""

echo "jira-link"
run_hook jira-link.sh '{"tool_name":"mcp__atlassian__createJiraIssue","tool_input":{"projectKey":"TEST"},"tool_response":{"key":"TEST-13","id":"1"}}'
check "create: link from the config site" 0 "$RC" "$OUT" "Jira TEST-13 created: https://example.atlassian.net/browse/TEST-13"
run_hook jira-link.sh '{"tool_name":"mcp__atlassian__transitionJiraIssue","tool_input":{"issueIdOrKey":"TEST-12"},"tool_response":{"statusName":"In Review"}}'
check "transition: says the status" 0 "$RC" "$OUT" "Jira TEST-12 moved to In Review: https://example.atlassian.net/browse/TEST-12"
run_hook jira-link.sh '{"tool_name":"mcp__atlassian__executeWrite","tool_input":{"name":"addWatcher","inputs":{"issueIdOrKey":"TEST-12"}},"tool_response":{}}'
check "executeWrite: names the operation" 0 "$RC" "$OUT" "Jira TEST-12 addWatcher: "
run_hook jira-link.sh '{"tool_name":"mcp__atlassian__editJiraIssue","tool_input":{"issueIdOrKey":"nokey"},"tool_response":{}}'
check "no key anywhere: silent" 0 "$RC" "$OUT" ""
CLAUDE_PROJECT_DIR="$bare" JIRA_SITE_URL="https://env.atlassian.net" run_hook jira-link.sh '{"tool_name":"mcp__atlassian__editJiraIssue","tool_input":{"issueIdOrKey":"X-1"},"tool_response":{}}'
check "no config: site from the environment" 0 "$RC" "$OUT" "https://env.atlassian.net/browse/X-1"
CLAUDE_PROJECT_DIR="$bare" run_hook jira-link.sh '{"tool_name":"mcp__atlassian__editJiraIssue","tool_input":{"issueIdOrKey":"X-1"},"tool_response":{"self":"https://resp.atlassian.net/rest/api/3/issue/1"}}'
check "no config: site from the response" 0 "$RC" "$OUT" "https://resp.atlassian.net/browse/X-1"
CLAUDE_PROJECT_DIR="$bare" run_hook jira-link.sh '{"tool_name":"mcp__atlassian__editJiraIssue","tool_input":{"issueIdOrKey":"X-1"},"tool_response":{}}'
check "no site at all: key without a link" 0 "$RC" "$OUT" "Jira X-1 edited (set jira.site"

echo "state"
st="$plugin/lib/state.sh"
dir="$(bash "$st" dir)"
check "dir is under the git dir" 0 $? "$dir" "$proj/.git/jira-flow"
OUT="$(printf '{"summary":"S","phase":"plan","plan":[{"n":1,"status":"todo"},{"n":2,"status":"todo"}]}' | bash "$st" set TEST-12 2>&1)"; RC=$?
check "set: accepts JSON" 0 "$RC" "$OUT" ""
OUT="$(bash "$st" current)"; check "set makes the key current" 0 $? "$OUT" "TEST-12"
OUT="$(bash "$st" get TEST-12 | jq -r '.key + " " + .phase + " " + (.startedAt | length | tostring)')"
check "get: key, phase and startedAt stamped" 0 $? "$OUT" "TEST-12 plan 20"
OUT="$(bash "$st" merge TEST-12 '.plan[0].status = "done" | .phase = "build"' 2>&1)"; RC=$?
check "merge: applies a filter" 0 "$RC" "$OUT" ""
OUT="$(bash "$st" get TEST-12 | jq -r '.phase + " " + .plan[0].status')"
check "merge: result stored" 0 $? "$OUT" "build done"
OUT="$(printf 'not json' | bash "$st" set TEST-13 2>&1)"; RC=$?
check "set: rejects bad JSON" 1 "$RC" "$OUT" "not valid JSON"
OUT="$(bash "$st" current)"; check "a rejected set leaves current alone" 0 $? "$OUT" "TEST-12"
printf '{"phase":"plan"}' | bash "$st" set TEST-14 >/dev/null
OUT="$(bash "$st" list | tr '\n' ' ')"; check "list: both keys" 0 $? "$OUT" "TEST-12 TEST-14"
OUT="$(bash "$st" current)"; check "the latest set is current" 0 $? "$OUT" "TEST-14"
bash "$st" clear TEST-14
OUT="$(bash "$st" current)"; check "clear drops current when it was that key" 0 $? "$OUT" ""
OUT="$(bash "$st" get TEST-14 2>&1)"; RC=$?; check "get after clear: exit 1" 1 "$RC" "$OUT" ""

echo "session-context"
run_hook session-context.sh '{"hook_event_name":"SessionStart"}'
check "prints the branch's issue and link" 0 "$RC" "$OUT" "issue:  TEST-12  (https://example.atlassian.net/browse/TEST-12)"
check "prints the parked work" 0 "$RC" "$OUT" "parked: TEST-12"
bash "$st" current TEST-12 >/dev/null
run_hook session-context.sh '{"hook_event_name":"SessionStart"}'
check "prints the current work's phase and steps" 0 "$RC" "$OUT" "work:   TEST-12 \"S\": phase build, 1/2 steps done"
git -C "$proj" checkout -q feature-x
run_hook session-context.sh '{"hook_event_name":"SessionStart"}'
check "keyless branch: says how to pick a story" 0 "$RC" "$OUT" "none in the branch name"
CLAUDE_PROJECT_DIR="$bare" run_hook session-context.sh '{"hook_event_name":"SessionStart"}'
check "no config: silent" 0 "$RC" "$OUT" ""

echo "manifests"
for f in "$here/../.claude-plugin/marketplace.json" "$plugin/.claude-plugin/plugin.json" "$plugin/hooks/hooks.json" "$plugin/templates/jira-flow.example.json"; do
  if jq -e . "$f" >/dev/null 2>&1; then ok "valid JSON: ${f#"$here/../"}"; else bad "valid JSON: $f" "jq could not parse it"; fi
done
for s in "$plugin"/skills/*/SKILL.md; do
  n="$(basename "$(dirname "$s")")"
  if sed -n '2,12p' "$s" | grep -q "^name: $n$"; then ok "skill $n names itself"; else bad "skill $n names itself" "frontmatter name differs from the directory"; fi
done
for h in "$plugin"/hooks/*.sh "$plugin"/lib/*.sh; do
  if bash -n "$h"; then ok "parses: ${h#"$plugin/"}"; else bad "parses: $h" "bash -n failed"; fi
done

echo
echo "$pass passed, $fail failed"
rm -rf "$tmp"
[ "$fail" -eq 0 ]
