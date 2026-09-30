---
name: track
description: >-
  Record work in Jira as it happens: move the story to In Progress when
  editing starts, comment on it with the files changed, the gates run and
  what was verified when a change lands, and create linked follow-up issues
  for anything discovered. Use when starting on a story outside
  /jira-flow:work, before reporting any change as done, when asked to "log
  this", "update the ticket", "track this in Jira", or when the jira-flow
  rule says the issue must record the change.
argument-hint: "[start KEY-n | note <text> | land] [--dry-run]"
---

# Track work in Jira

Every change is recorded on the issue it belongs to. Do not commit here;
`/jira-flow:pr` and `/jira-flow:ship` do that when asked.

## Step 0: the config

Read `.claude/jira-flow.json` (missing: stop, `/jira-flow:init`). Take
`jira.projectKey`, `jira.cloudId`, `jira.transitions`, `jira.taxonomy`,
`gates`, `approvals.comments`.

**Transitions.** Use the id from `jira.transitions` when it is set. When it
is empty, `discover` the operation that lists an issue's transitions, run it
with `executeRead` for the issue, and pick the one whose target status name
matches (progress, review); say which id was used.

## Mode A: starting (`start [KEY-n]`)

1. Resolve the key: the argument, else the branch name, else `/jira-flow:status`
   for the best match, confirmed with the reader in one line.
2. `getJiraIssue` it. If its status is `To Do`, `transitionJiraIssue` to In
   Progress. If another story is already In Progress on this branch, say so;
   do not silently run two.
3. Read the acceptance criteria aloud in your plan. They are the definition of
   done for the work that follows.
4. If the branch has no key and the reader wants one, the branch name is
   `<KEY>-<n>-<slug>` (from `git.branch`, lower-case, hyphens, at most five
   words). Creating the branch is a git write; do it through `/jira-flow:pr`
   or `/jira-flow:work`, or on explicit request.

## Mode B: landing (`land`, or no argument with changes in the tree)

1. Gather the evidence:

   ```bash
   git status --short
   git diff --stat
   git rev-parse --short HEAD
   ```

2. Run the gates from the config whose `paths` match a changed file (a gate
   without `paths` always applies). Run each `run` in its `cwd`; record pass
   or fail with the counts the tool prints. A gate marked `"manual": true`
   is not run: ask the reader for its result, or record it as "not run".
   No gates configured: say so; never invent a result.

3. Classify the files with the taxonomy's path table when it has one. If a
   file belongs to a different epic than the story's, that is either a
   second story or a note in the comment; say which.

4. Write the comment from the taxonomy's comment template, else
   `${CLAUDE_PLUGIN_ROOT}/templates/comment.md` (Change, Files, Gates,
   Verified, Open, Branch). Evidence directories are paths, not attachments,
   unless the reader asks for uploads.

5. Follow-ups discovered while working (a port, a gap, a bug) become issues
   now: `/jira-flow:plan` or `/jira-flow:bug`, then `createJiraIssueLink`
   (`Relates`, or `Blocks` when it truly blocks). List the new keys under
   **Open** in the comment.

6. **Approval.** Show the comment. With `--dry-run` stop there. With
   `approvals.comments: true` in the config, `AskUserQuestion` before
   posting; otherwise post it with `addOrEditJiraIssueComment`.

7. If the acceptance criteria are all met and the reader has said the change
   is complete, leave the status at `In Progress` and say that
   `/jira-flow:pr` will move it to `In Review`. Do not move to `Done`.

## Mode C: a note (`note <text>`)

A one-line comment on the current issue. For decisions made mid-work ("chose
X over Y because ...") so the reasoning lives with the ticket, not in the chat.

## Report

```
Jira:    KEY-57 In Progress -> commented (gates: app 3/3 ok)
Open:    KEY-122 created (Relates): port the type variant
Next:    /jira-flow:pr when ready to raise the PR
```
