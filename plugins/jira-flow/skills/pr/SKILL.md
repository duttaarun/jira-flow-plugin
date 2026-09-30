---
name: pr
description: >-
  Raise a pull request traced to its Jira story or bug: verify the gates,
  create or reuse the <KEY>-<n>-<slug> branch, commit with the key in the
  subject, push, open the PR from the project's template with the key in the
  title and the issue link in the body, comment the PR URL on the issue and
  move it to In Review. Runs only when the reader asked for a PR or a commit
  in the prompt that is running. Use when asked to "raise a PR", "open a pull
  request", "commit this", "push this", "ship this branch".
argument-hint: "[KEY-n] [--draft] [--base main]"
---

# Raise a traced PR

Request: $ARGUMENTS

This skill is the one route by which history is written for a story, and it
runs only when the reader asked for a PR or a commit **in the prompt that is
running** (or answered `/jira-flow:work`'s or `/jira-flow:ship`'s checkpoint
question with it). If they did not, do the work up to the branch and the
commit, then say what is ready and ask once. Never merge from here; never
rebase; never force-push. The plugin's `ask-before-ship` hook prompts on the
PR whatever route it is attempted by; that prompt is the backstop, not the
asking.

## Step 0: the config and the route

Read `.claude/jira-flow.json` (missing: stop, `/jira-flow:init`). Take
`jira.projectKey`, `jira.site`, `jira.transitions.inReview`, `git.*`,
`gates`.

The route, in order, stopping at the first that works (`git.route` pins one):

1. `gh auth status` and `gh repo view` succeed: `gh pr create` is preferred.
2. The GitHub MCP: only if `mcp__github__get_me` works and
   `mcp__github__list_branches` sees this repo (a 404 means the token's
   account is not a collaborator).
3. `git ls-remote --heads origin` must succeed either way for the push.

If none works, do everything up to the push locally (branch and commit),
then stop and say exactly what is missing. Do not work around it.

## Step 1: the issue

Key from the argument, else the branch, else the current work state
(`bash "${CLAUDE_PLUGIN_ROOT}/lib/state.sh" current`). `getJiraIssue` it: it
must be In Progress (or To Do; move it to In Progress). Read the acceptance
criteria; the PR body will tick them.

## Step 2: the gates, honestly

Run the configured gates that apply to the changed paths (as `/jira-flow:track`
does) unless a work state records them green at the current HEAD. A red gate
stops the PR unless the reader said `--draft`; then the body says which gate
is red and why.

## Step 3: branch

```bash
git branch --show-current
git status --short
git diff --stat
```

If the branch already carries the key, keep it. Otherwise create it from
`git.branch` (`{key}-{slug}`: slug lower-case, hyphens, at most five words
from the summary) with `git checkout -b` from the current HEAD.

Look at what will be committed before staging it. Stage the files of this
story only (`git add <paths>`; never `git add -A` without listing what it
adds). Anything belonging to another story stays unstaged and is named in
the report. Files changed that you did not touch mean another session is
working this tree: stop and ask which session finishes.

## Step 4: commit

Subject from `git.commit` (`{key}: {subject}`, imperative, under 72 chars);
body says why, names what was verified, and ends with the attribution lines
the session's system reminder specifies. One commit per PR is the norm;
several are fine when they are separable.

## Step 5: push and open

```bash
git push -u origin <branch>
```

Title from `git.prTitle` (`[{key}] {title}`). Body from `git.prTemplate` when
the file exists, else `${CLAUDE_PLUGIN_ROOT}/templates/pull_request_template.md`:
the issue link `<jira.site>/browse/<key>`, the summary, the acceptance
criteria as a checklist with the ones met ticked, what was verified with
evidence paths, the gates and their results, and the attribution footer from
the session's system reminder. Base `git.baseBranch` unless `--base` says
otherwise. Draft if a gate is red or `--draft` was given.

Keep `git commit`, `git push` and `gh pr create` visible in the Bash command,
never hidden inside a script: the guard and ship hooks read the command text.

## Step 6: trace it back

1. `addOrEditJiraIssueComment` on the issue: "PR raised: <url> from
   `<branch>` at `<sha>`."
2. `transitionJiraIssue` to In Review (id from the config, else looked up on
   the issue by name).
3. If a work state exists for the key, record the PR:
   `bash "${CLAUDE_PLUGIN_ROOT}/lib/state.sh" merge <key> '.pr = {url: "<url>", number: <n>} | .phase = "ship"'`.

## Report

```
PR:      https://github.com/org/repo/pull/12  [KEY-57] Service worker precaches the shell
Branch:  KEY-57-service-worker @ 3f2a9c1 -> main
Jira:    KEY-57 In Review (comment added)
Left:    2 files not staged (belong to KEY-42)
```

Merging and moving the issue to Done wait for the reader's word:
`/jira-flow:ship` asks for both once and does them.
