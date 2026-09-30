---
name: plan
description: >-
  Turn a request, a plan, a design comment or a discovered gap into Jira
  issues with the right shape for this project: the epic it belongs to, the
  story template with acceptance criteria, the project's labels, story
  points, priority, and links. Also creates a new epic when a capability has
  none. Use when asked to "create a story", "add to the backlog", "plan
  this", "break this down", "make tickets for", or whenever the jira-flow
  rule requires an issue that does not exist yet.
argument-hint: "<what to plan> [--epic KEY-n] [--type Story|Task] [--points n] [--dry-run]"
---

# Plan work into Jira

Request: $ARGUMENTS

## Step 0: the config and the taxonomy

Read `.claude/jira-flow.json` (missing: stop, `/jira-flow:init`). Take
`jira.projectKey`, `jira.cloudId`, `jira.issueTypes`, `jira.fields.storyPoints`,
`jira.fields.sprint`, `jira.labels`, `jira.taxonomy`, `approvals.createIssues`.

Read the taxonomy file if it exists: it has the epic keys, the path-to-epic
table, the labels and the templates. Do not query Jira for what it already
answers. Without a taxonomy, the story template is the one in
`${CLAUDE_PLUGIN_ROOT}/templates/taxonomy.md` and the epics come from
`searchJiraIssuesUsingJql` (`project = <KEY> AND issuetype = Epic ORDER BY
Rank`, fields `summary,labels`).

## Step 1: understand the ask in the repo's terms

Before writing an issue, name:

- **Which part of the product** it changes, in the taxonomy's own words
  (its surfaces, platforms or modules), and which parts must not move.
- **What arrives for free** through shared code, and what is a separate hand
  port. A change that also needs a port elsewhere is two stories linked
  `Relates`, never one.
- **Whether it is a bug** (something built behaves wrongly): then use
  `/jira-flow:bug` instead.

## Step 2: avoid duplicates

`searchJiraIssuesUsingJql` with `project = <KEY> AND summary ~ "<two or three
distinctive words>" AND statusCategory != Done`. If a match exists, update
or comment on it rather than creating a twin; tell the reader which.

## Step 3: place it

Pick the epic from the taxonomy's path table, else from the epic list by
summary; `--epic` overrides. Ask only when the epic is genuinely ambiguous.
If no epic fits and the capability is real and multi-story, create an epic
with the epic template and add its row to the taxonomy. One new epic per
session at most without asking.

## Step 4: write it

`createJiraIssue` with:

| Field | Value |
| --- | --- |
| `projectKey` | `jira.projectKey` |
| `issueType` | `jira.issueTypes.story` (user-visible outcome) or `jira.issueTypes.task` (engineering or process work); `--type` overrides |
| `parent` | the epic key |
| `summary` | outcome in plain words, no em dashes |
| `description` | the story template, filled |
| `labels` | as the taxonomy prescribes (platform and theme labels when it has them; `tech-debt`, `future` as they read) |
| `priority` | Highest, High, Medium (default), Low |
| `additional_fields` | `{"<jira.fields.storyPoints>": <points>}` when the field is configured; `duedate` only for real deadlines |
| `assignToSprint` | `"active"` only if the reader says it is for this sprint |

Story points: 1 trivial, 2 small, 3 half a day, 5 a day or two, 8 several
days with verification in more than one place, 13 uncertain outcome (split
if it can be split). `--points` overrides.

Breaking down: an ask that spans more than one platform or more than one
epic becomes one story per platform (or per epic), linked `Relates`, with the
shared story first and the dependent stories `Blocks`-linked from it.

**Approval.** Creating issues needs no asking by the standing rule. Two
exceptions: `--dry-run`, and `approvals.createIssues: true` in the config.
In either case show every issue in full (type, epic, summary, description,
labels, points, links) and, unless dry-running, `AskUserQuestion` before
creating any.

## Step 5: link and report

`createJiraIssueLink` to the story currently in progress (`Relates`) when the
new issue was found while working on it. Report:

```
Created: KEY-122 Story "Port the reading type variant to the web" (epic KEY-8, web, theme-design, 3 pts)
Linked:  Relates KEY-57
```

## Also

- Every issue's summary and description avoid em dashes.
- Do not delete or close anything from here.
