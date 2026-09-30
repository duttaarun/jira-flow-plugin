---
name: ship
description: >-
  The door at the end of a story: commit and push what is ready, then ask
  once, naming everything that would happen, and on the reader's word raise
  the PR, wait for its checks, merge it, move the Jira issue to Done and sync
  the base branch. Each of the three outward acts stops at a permission prompt
  as well. Use when the reader says "ship it", "raise the PR and merge",
  "merge and close", "close KEY-n", or when /jira-flow:work reaches its last
  phase.
argument-hint: "[KEY-n] [--pr | --merge | --close | --all] [--hold]"
---

# Ship a story

Request: $ARGUMENTS

Three acts need the reader's word in the turn that is running: raising the
PR, merging, closing the issue. Everything before them is done without
asking. This skill takes the work to the door, asks once, and then does
exactly what was answered. The plugin's `ask-before-ship` hook prompts on
each act as well; that is the backstop.

## Step 0: the config and the facts

Read `.claude/jira-flow.json` (missing: stop, `/jira-flow:init`). Take
`jira.*`, `git.*`, `ship.*`.

Key: the argument, else the branch, else the current work state
(`bash "${CLAUDE_PLUGIN_ROOT}/lib/state.sh" current`).

```bash
git branch --show-current
git status --short
git log --oneline origin/<base>..HEAD
gh pr list --head "$(git branch --show-current)" --json number,url,isDraft,state,mergeable 2>/dev/null
```

Establish, and say in one line each: the branch and its key; uncommitted
files (this story's, or another's); commits ahead of the base; whether a PR
exists already and its state; the gates' last result (the work state, or
`/jira-flow:track`'s last comment, or run them now as `/jira-flow:pr` does).

## Step 1: to the door

Without asking, as the standing rule allows:

1. Commit this story's files if any are uncommitted (`/jira-flow:pr` steps
   3 and 4: the story's paths only, the key in the subject).
2. Push the branch (`git push -u origin <branch>`).
3. Run the gates if their last result is not at this HEAD. A red gate is
   reported, and the ask below offers the PR as a draft only.

## Step 2: the one ask

If `$ARGUMENTS` already names the acts (`--pr`, `--merge`, `--close`, or
`--all` for the three; `--merge` implies `--pr`, `--close` implies both), that
is the reader's word: skip to Step 3. `--hold` stops here with the report.

Otherwise `AskUserQuestion`, one question, the header "Ship", naming
everything:

> Ready to ship KEY-221: branch `KEY-221-slug` at `abc1234`, 3 commits, gates
> green (app 3/3). PR: none yet.

Options, in this order:
1. "Raise the PR, merge it, and close KEY-221"
2. "Raise the PR and merge it (leave KEY-221 In Review)"
3. "Raise the PR only"
4. "Hold"

Gates red: option 1 and 2 are replaced by "Raise as a draft PR" and "Hold".
PR already open: the options start from "Merge it and close", "Merge it",
"Hold". The answer is the asking; do only what it says.

## Step 3: the acts, in order

**Raise.** As `/jira-flow:pr` steps 5 and 6 (title, body from the template,
comment on the issue, In Review). Keep `gh pr create` visible in the command.

**Wait for checks** (`ship.waitForChecks`, default true). `gh pr checks`
straight after `gh pr create` reports no checks and exits, so loop until a
check line appears, then `gh pr checks <n> --watch`; give up after 20
minutes and say so. A failed check stops the merge; report it.

**Merge.** `gh pr merge <n> --<ship.mergeMethod>` (default `merge`), with
`--delete-branch` when `ship.deleteBranchOnMerge` is true. Through the GitHub
MCP when that is the route. A stacked PR whose base branch is deleted on
merge closes the PRs above it: retarget those first, and say so.

**Close.** `addOrEditJiraIssueComment`: "Merged as <PR url> (<merge sha>)."
Then `transitionJiraIssue` to Done (id from `jira.transitions.done`, else
looked up on the issue by name). Fix version if the project uses one and the
reader named it.

**Sync.** Only when the working tree is clean: `git fetch origin` then
`git checkout <base> && git pull --ff-only`. A dirty tree (another story's
files) is left as it is, and the report says the base is behind. Another
session working this checkout: use the guarded `git update-ref` recipe from
the README instead of a checkout, and say so.

**State.** `bash "${CLAUDE_PLUGIN_ROOT}/lib/state.sh" clear <key>` once the
issue is Done; after a raise or merge alone, `merge <key> '.phase = "ship" |
.pr = {...}'`.

## Report

```
PR:      https://github.com/org/repo/pull/221  [KEY-221] ...  merged 4e1c2a0 (checks: jira-key ok, ci ok)
Jira:    KEY-221 Done (comment: merged)
Base:    main at 4e1c2a0, checkout synced  | main is behind: 2 files of KEY-230 uncommitted
```

Or, after "Hold": one line saying what is ready and that nothing was raised,
merged or closed.
