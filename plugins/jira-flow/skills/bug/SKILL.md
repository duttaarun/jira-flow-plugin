---
name: bug
description: >-
  File a bug in the project's Jira with the evidence that makes it fixable:
  where it shows, the build, steps, actual and expected, a screenshot or log
  path, the suspect file. Uses the Bug work type when the project has it and
  Task + the bug label until then. Use when something built behaves wrongly,
  when a test or gate fails for a reason outside the current story, when the
  reader says "this is broken", "bug", "regression", or when a screenshot
  shows a defect.
argument-hint: "<what is wrong> [--priority Highest|High|Medium|Low] [--blocks KEY-n] [--dry-run]"
---

# File a bug

Request: $ARGUMENTS

## Step 0: the config and the taxonomy

Read `.claude/jira-flow.json` (missing: stop, `/jira-flow:init`). Take
`jira.projectKey`, `jira.cloudId`, `jira.issueTypes.bug`, `jira.issueTypes.task`,
`jira.labels.bug`, `jira.taxonomy`, `approvals.createIssues`. The taxonomy's
bug template and path table apply when the file exists; otherwise the bug
template in `${CLAUDE_PLUGIN_ROOT}/templates/taxonomy.md`.

## Step 1: pin it down

A bug report without a place is a rumour. Establish, from the conversation
or by asking one question:

- **Where**: the surface, platform, module or environment, in the taxonomy's
  words.
- **Build**: branch and short sha (`git rev-parse --short HEAD`), device,
  runtime or browser and its version, any mode that matters (locale, theme).
- **Evidence**: a screenshot path, a failing test name, or a log excerpt.
  Take one if none exists and the surface is reachable headlessly.

Check it is not already filed: `project = <KEY> AND (issuetype = Bug OR
labels = <bug>) AND statusCategory != Done AND summary ~ "<words>"`.

## Step 2: the type

`issueType` = `jira.issueTypes.bug` when the project has it, else
`jira.issueTypes.task`; always plus the bug label, so the standing JQL
(`issuetype = Bug OR labels = <bug>`) keeps matching.

## Step 3: create it

`createJiraIssue` with the epic of the place as `parent` (the taxonomy's path
table; else the epic whose summary fits, else none), the bug template as
description, the taxonomy's labels plus the bug label, priority:

| Priority | Meaning |
| --- | --- |
| Highest | wrong results, a crash, data loss |
| High | visibly wrong on something shipped |
| Medium | wrong only in an edge case or on something unshipped |
| Low | cosmetic, documented gap |

Summary starts with the place when it is not obvious: "Web phone: orb ring
sits 90 degrees behind its beads".

**Approval.** As in `/jira-flow:plan`: no asking by default; with
`--dry-run` or `approvals.createIssues: true`, show the issue in full and
`AskUserQuestion` before creating.

## Step 4: link and report

`createJiraIssueLink` `Relates` to the story in progress if it was found while
working on one; `Blocks` if the story cannot finish without the fix
(`--blocks KEY-n` says which).

```
Bug:      KEY-123 "iPad: Slide Over pane picks the wide hero" High, epic KEY-11
Evidence: shots/2026-09-17/ipad-slideover.png
Linked:   Blocks KEY-70
```

Do not fix the bug inside an unrelated story's branch without saying so; the
fix is its own `<KEY>-<n>-<slug>` branch and PR unless the reader folds it in.
