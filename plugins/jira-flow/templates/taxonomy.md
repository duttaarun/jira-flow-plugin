# Jira taxonomy for {{PROJECT_NAME}}

Site `{{SITE}}`, cloudId `{{CLOUD_ID}}`, project key `{{KEY}}`. Written by
`/jira-flow:init` on {{DATE}}; edit it as the backlog grows. The ids the
tools need (transitions, fields) live in `.claude/jira-flow.json`; this file
holds what a person decides: where work goes, how issues are written.

## Hierarchy

| Level | Jira type | Meaning here |
| --- | --- | --- |
| Feature | **Epic** | One shippable capability |
| Story / Task / Bug | Story, Task, Bug | One PR-sized unit of work |
| Subtask | Subtask | Only when a story needs a checklist tracked separately |

## Epics

{{EPICS_TABLE}}

Where a change goes, by path (fill this in as the repo's shape settles):

| Path | Epic |
| --- | --- |
| `src/**` | |
| `.github/**`, `.claude/**`, repo docs | |

## Labels

{{LABELS}}

Bugs are type `Bug` and also carry the `{{BUG_LABEL}}` label so one JQL
covers them.

## Statuses and transitions

| Status | transitionId | When |
| --- | --- | --- |
| To Do | {{T_TODO}} | created |
| In Progress | {{T_IN_PROGRESS}} | first edit for the story |
| In Review | {{T_IN_REVIEW}} | PR raised |
| Done | {{T_DONE}} | PR merged (only when asked) |

## Story template

```
As <the user | the developer | the operator> I want <outcome> so that <why>.

**Where.** <paths>
**Acceptance.**
- <observable result 1>
- <observable result 2>
- Gates: <lint/typecheck/test/build ...>; verified on <what>
**Depends on.** <keys, or none>
```

## Bug template (issue type Bug, plus label `{{BUG_LABEL}}`)

```
**Where.** <surface, platform, environment>
**Version / build.** <branch or commit, device or runtime, OS version>
**Steps.** 1. ... 2. ...
**Actual.** ...
**Expected.** ...
**Evidence.** <screenshot path, failing test name, log excerpt>
**Suspect.** <file:line if known>
```

## Epic template

```
**Goal.** <one paragraph>
**Where.** <paths>
**Done when.** <the observable end state>
**Rules.** <the .claude/rules and skills that apply>
```

## Comment template (on landing a change)

```
**Change.** <one line>
**Files.** <list, grouped>
**Gates.** <name: result, ...>
**Verified.** <what was looked at; evidence path>
**Open.** <follow-up keys created, or none>
**Branch.** <name> at <short sha>
```

## JQL you will use

- In flight: `project = {{KEY}} AND status = "In Progress" ORDER BY updated DESC`
- Waiting on merge: `project = {{KEY}} AND status = "In Review" ORDER BY updated DESC`
- Next up: `project = {{KEY}} AND status = "To Do" AND issuetype != Epic ORDER BY priority DESC, Rank ASC`
- An epic's children: `project = {{KEY}} AND parent = {{KEY}}-<n> ORDER BY status, Rank`
- Bugs: `project = {{KEY}} AND (issuetype = Bug OR labels = {{BUG_LABEL}}) AND statusCategory != Done`
- Duplicate check before creating: `project = {{KEY}} AND summary ~ "<two or three words>"`
