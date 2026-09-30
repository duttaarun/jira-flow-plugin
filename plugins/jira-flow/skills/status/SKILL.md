---
name: status
description: >-
  Read the state of the project's Jira backlog and relate it to the working
  tree: which story the current branch belongs to, what is In Progress, what
  is In Review waiting on a merge, what is next by priority, open bugs, and
  any story mid-flow in /jira-flow:work. Use at the start of a session, when
  asked "what am I working on", "what's next", "show the board", "status", or
  before picking up any work that has no issue key yet.
argument-hint: "[--epic KEY-n] [--label x] [--mine]"
---

# Jira status

Read-only. Nothing here edits an issue.

## Step 0: the config

Read `.claude/jira-flow.json` at the project root. If it is missing, say so
and stop: `/jira-flow:init` writes it. Take from it `jira.projectKey`,
`jira.site`, `jira.cloudId`, `jira.labels.bug`, `jira.taxonomy`. If the
taxonomy file exists, its JQL section and path table are used below.

## Step 1: the branch

```bash
git branch --show-current
git status --short | wc -l
git log --oneline -5
bash "${CLAUDE_PLUGIN_ROOT}/lib/state.sh" current
```

Extract `<KEY>-[0-9]+` from the branch name. If present, `getJiraIssue` it
(view `compact`) and show summary, status, parent epic. If a work state is
current (`state.sh current`), read it (`state.sh get <key>`) and note the
phase and the steps done.

## Step 2: the board, in four queries

Run these with `searchJiraIssuesUsingJql` (fields
`summary,status,issuetype,parent,priority,labels`, `maxResults` 20), with
`<KEY>` the project key and `<bug>` the bug label:

1. In flight: `project = <KEY> AND status = "In Progress" ORDER BY updated DESC`
2. Waiting on merge: `project = <KEY> AND status = "In Review" ORDER BY updated DESC`
3. Next up: `project = <KEY> AND status = "To Do" AND issuetype != Epic ORDER BY priority DESC, Rank ASC` (first 10)
4. Bugs: `project = <KEY> AND (issuetype = Bug OR labels = <bug>) AND statusCategory != Done`

`--epic KEY-n` adds `AND parent = KEY-n`; `--label x` adds `AND labels = x`;
`--mine` adds `AND assignee = currentUser()`. If the project's statuses are
not literally "In Progress" / "In Review" / "To Do" (the taxonomy's status
table says), use its names.

## Step 3: report

One block, no preamble:

```
Branch:        feature/x (no key)  |  KEY-57-service-worker -> KEY-57 "..." (In Progress, epic KEY-10)
Working tree:  clean | 4 files changed
Mid-flow:      KEY-57 phase build, 2/5 steps done (resume: /jira-flow:work KEY-57)  | none
In progress:   KEY-57 Service worker ...  (epic KEY-10)
In review:     none
Next up:       KEY-31 Calibration harness (Highest, 13 pts)
               KEY-102 Performance budgets (Highest, 3 pts)
               ...
Bugs open:     KEY-50 conic gradient rings 90 degrees behind (High)
```

Then one line of advice: which story the uncommitted changes look like they
belong to (match paths against the taxonomy's path table when it has one),
or that a story should be created with `/jira-flow:plan` before continuing,
or which key `/jira-flow:work` should pick up next.
