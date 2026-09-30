# jira-flow

A Claude Code plugin that makes Jira the ledger of a repo's work and puts a
door at the end of every story: each change is a story or a bug, each PR
carries its key, and nothing is raised, merged or closed until you say so.
Configured per project, so one install serves every repo.

- `/jira-flow:init` discovers the site, project, transition ids, fields and
  epics through the Atlassian MCP, the gates and base branch from the repo,
  and writes `.claude/jira-flow.json` with the taxonomy, rules, PR template
  and CI check. Every write is shown and approved first.
- `/jira-flow:work KEY-n` takes a story or bug from a plan you approve to a
  PR you ask for, stopping at a checkpoint after every phase and every step,
  where you continue, adjust, run through, or stop. It resumes across
  sessions.
- `/jira-flow:status`, `plan`, `bug`, `track`, `pr`, `ship` are the pieces
  on their own.
- Four hooks: the branch's issue at session start; a guard that refuses a
  commit or push without the key; the ship gate that turns a PR, a merge or
  a close into a permission prompt whatever route is tried (the shell, a
  wrapped shell, the GitHub MCP, the Atlassian MCP); and the issue's link
  after every Jira write.

## Install

```bash
claude plugin marketplace add duttaarun/jira-flow-plugin
claude plugin install jira-flow@jira-flow            # user scope: the ship gate holds in every project
claude plugin install jira-flow@jira-flow --scope project   # or just this repo
```

Needs `jq`, `git`, the Atlassian MCP connected in Claude Code, and `gh`
signed in (the GitHub MCP works as the PR route too; `git.route` picks).

Then, in each repo you want traced:

```
/jira-flow:init
```

and commit `.claude/jira-flow.json`, `.claude/jira/taxonomy.md`,
`.claude/rules/jira-flow.md`, `.github/pull_request_template.md` and
`.github/workflows/jira-key.yml`.

## The flow

```
/jira-flow:work KEY-57
  1 read and plan      getJiraIssue, read the code, 3-8 steps      -> Plan: approve | run through | adjust | hold
  2 start              branch KEY-57-slug, In Progress, plan comment  (covered by the approval)
  3 build              one step at a time                            -> Step k/N: continue | run through | adjust | stop
  4 verify             the configured gates, honestly                -> Gates (red only): fix | continue as draft | stop
  5 record             tracking comment + follow-up issues           -> Record: post and file | post only | adjust | skip
  6 ship               commit, push, then ONE ask                    -> Ship: raise+merge+close | raise+merge | raise | hold
```

Every checkpoint takes a free-text answer as a steer note. Between sessions,
`/jira-flow:work` alone resumes the current story; `--status` shows the plan;
`--replan`, `--stop`, `--abandon` do what they say. The state lives under the
repo's `.git/jira-flow/` (one JSON per key), never in the tree.

## The ship gate

| Act | Needs your word, in the running turn |
| --- | --- |
| Raise a PR (`gh pr create`, `gh pr ready`, the GitHub MCP) | yes |
| Merge (`gh pr merge`, `git merge`, the merge API) | yes |
| Move an issue to Done (or any close/resolve) | yes |
| Branch, commit, push a `KEY-n-slug` branch | no |
| Create an issue, comment, move to In Progress or In Review | no |

The skills ask once, at the end, naming everything that would happen. The
`ask-before-ship` hook is the backstop: it prompts on each act however it is
attempted. `ship.askBefore` in the config narrows the set (a solo repo may
drop `pr`).

## Configuration

`.claude/jira-flow.json`, written by `init`; every key is documented in
[docs/config.md](docs/config.md). The important ones:

| Key | Meaning |
| --- | --- |
| `jira.projectKey`, `jira.site`, `jira.cloudId` | where the issues live; the key regex the hooks use is `<projectKey>-[0-9]+` |
| `jira.transitions.{todo,inProgress,inReview,done}` | transition ids; empty ones are looked up on the issue by name |
| `jira.issueTypes`, `jira.fields.storyPoints`, `jira.labels.bug` | how issues are written |
| `jira.taxonomy` | the file with the epics, the path-to-epic table and the templates |
| `git.baseBranch`, `git.protectedBranches`, `git.requireKey` | what the guard refuses |
| `git.branch`, `git.commit`, `git.prTitle`, `git.prTemplate`, `git.route` | naming and the PR route (`auto`, `gh`, `mcp`) |
| `gates[]` | `{name, cwd, run, paths, manual}`; a gate runs when a changed file matches `paths` |
| `work.checkpoint`, `work.commitEach` | `step` or `phase`; `never`, `step` |
| `approvals.createIssues`, `approvals.comments` | gate issue creation and comments too (off by default) |
| `ship.askBefore`, `ship.mergeMethod`, `ship.deleteBranchOnMerge`, `ship.waitForChecks` | the door |

## Migrating from a hand-rolled setup

If a repo already carries its own copies of these hooks and skills (a
`.claude/hooks/ask-before-ship.sh`, `jira-*` skills, a user-level hook in
`~/.claude/settings.json`), remove them once the plugin is installed, or
every gated act prompts twice. `init --refresh` reads the ids from Jira
again; the taxonomy file you already have is kept when you say so.

## Recipes the skills know

- **Stacked PRs.** Merging with branch deletion closes the PRs based on the
  deleted branch: retarget them first.
- **Shipping one story while another session works the same checkout.**
  Commit from a separate worktree (`git worktree add -b KEY-n-slug <dir>
  origin/main`), build the story's patch with `git diff --binary`, and after
  the merge sync the checkout with a guarded `git update-ref refs/heads/main
  NEW OLD` plus `git reset -q -- <paths>`, leaving the working tree alone.
- **Many stories from one tested tree.** Write each story's state into a
  detached scratch worktree, prove every intermediate state with the gates,
  then ship one branch per story; keep `git commit`, `gh pr create` and
  `gh pr merge` visible in the command so the hooks can read them.

## Tests

```bash
bash tests/run.sh
```

Feeds every hook the JSON Claude Code sends, in a throwaway repo, and
exercises the state store. No Jira or GitHub access is needed.

## Layout

```
.claude-plugin/marketplace.json
plugins/jira-flow/
  .claude-plugin/plugin.json
  hooks/hooks.json, session-context.sh, guard-key.sh, ask-before-ship.sh, jira-link.sh
  lib/config.sh, state.sh
  skills/init, work, status, plan, bug, track, pr, ship
  templates/jira-flow.example.json, rules.md, taxonomy.md, pull_request_template.md, jira-key.yml, comment.md, plan-comment.md
docs/config.md
tests/run.sh
```

MIT.
