---
name: init
description: >-
  Configure this project for jira-flow: discover the Jira site, project key,
  issue types, transition ids, fields and epics through the Atlassian MCP,
  detect the repo's gates, base branch and GitHub route, and write
  .claude/jira-flow.json plus the taxonomy, the rules file, the PR template and
  the jira-key workflow. Nothing is written before it has been shown and
  approved. Use when asked to "set up jira-flow", "configure Jira tracking for
  this repo", "init jira", "connect this project to Jira", or when another
  jira-flow skill finds no config. --refresh re-discovers ids for an existing
  config; --check only reports.
argument-hint: "[PROJECT-KEY] [--site https://x.atlassian.net] [--base main] [--check] [--refresh]"
---

# Set this project up for jira-flow

Request: $ARGUMENTS

Everything the other jira-flow skills and the plugin's hooks need lives in
`.claude/jira-flow.json` at the project root. This skill discovers the values,
shows them, and writes the files only after the reader has approved each one.
Never guess an id: what cannot be discovered stays empty and is said so.

## Step 0: preconditions

Run and report, one line each; stop at the first hard failure:

```bash
git rev-parse --show-toplevel
jq --version
gh auth status 2>&1 | head -3
```

- No git repo: stop; jira-flow tracks branches and PRs.
- No `jq`: stop; the hooks need it (`brew install jq`).
- The Atlassian MCP must be connected: call `getAccessibleAtlassianResources`.
  If the tool is missing or fails, stop and say the MCP must be connected
  (`/mcp`) before setup.
- GitHub: `gh auth status` succeeding is the preferred route. If `gh` is
  absent, try `mcp__github__get_me`; note which worked. Neither is not fatal:
  the config records `"route": "auto"` and `/jira-flow:pr` reports the gap
  when it is reached.

`--check` stops after this step with the report.

If `.claude/jira-flow.json` already exists and `--refresh` was not given,
show its `jira.projectKey`, `jira.site` and the number of gates, and ask
whether to re-discover (`--refresh`), edit one part, or stop.

## Step 1: the site

From `getAccessibleAtlassianResources`: `url` and `id` (the cloudId). One
site: take it. Several: `AskUserQuestion` with the site URLs as options
(`--site` picks without asking).

## Step 2: the project

- Key from `$ARGUMENTS` (the first token matching `^[A-Z][A-Z0-9]+$`), else
  `executeRead` the operation `listJiraProjects` (inputs `cloudId`, optional
  `query`) and `AskUserQuestion` with the projects (key and name) as options.
- Record `projectKey`, `projectName`, and whether the project is team-managed
  or company-managed if the listing says so.

The operation names below were confirmed with `discover`; if one is
rejected, `discover` again with the goal in words and use what it returns.

## Step 3: issue types and fields

- `executeRead` `listJiraProjectIssueTypesMetadata` (inputs `cloudId`,
  `projectIdOrKey`): each entry has an id, a name and a subtask flag. Fill
  `jira.issueTypes` with the names that exist among Epic, Story, Task, Bug,
  Subtask; leave a missing one as `""` and say it is missing (a project
  without a Bug type files bugs as Task + the bug label).
- `executeRead` `getJiraIssueTypeMetaWithFields` (inputs `cloudId`,
  `projectIdOrKey`, `issueTypeId` of the story type, `requiredFieldsOnly:
  false`, `maxResults` 200): among its fields, the one whose name matches
  `story point` (case-insensitive) and the one matching `sprint`. Record
  their `fieldId`s under `jira.fields`; empty when absent.

## Step 4: transitions

The ship gate and the tracking skills need the ids of the moves To Do, In
Progress, In Review and Done.

1. `searchJiraIssuesUsingJql` with `project = <KEY> AND statusCategory != Done
   ORDER BY created DESC`, `maxResults` 1, fields `summary,status`.
2. If an issue came back, `executeRead` `listJiraIssueTransitions` (inputs
   `cloudId`, `issueIdOrKey`, `includeUnavailableTransitions: true`,
   `sortByOpsBarAndStatus: true`). Each transition has an id, a name and the
   status it leads to (with its category). `listJiraStatuses` (mode
   `project`, `projectKey`) lists the project's statuses and categories when
   a name is ambiguous.
3. Map by the target status, in this order of preference:
   - `todo`: category `new`/`To Do`, or name matching `to do|backlog|open`
   - `inProgress`: category `indeterminate` with name matching `progress|doing|develop`
   - `inReview`: name matching `review|qa|test|verify`
   - `done`: category `done`, or name matching `done|close|resolve|complete`
4. Show the table (id, name, target) and the mapping, and `AskUserQuestion`:
   confirm, or the reader corrects a row in their own words.
5. If the project has no open issue, leave the four ids empty and say so: the
   skills then look transitions up on the issue at hand, and the ship gate
   matches the closing move by name.

## Step 5: epics and labels

- `searchJiraIssuesUsingJql` with `project = <KEY> AND issuetype = Epic ORDER
  BY Rank`, fields `summary,status,labels`, `maxResults` 50. This becomes the
  epics table in the taxonomy (key, summary, labels).
- `searchJiraIssuesUsingJql` with `project = <KEY> ORDER BY updated DESC`,
  fields `labels`, `maxResults` 50; the distinct labels become the labels
  section. Record the label used for bugs (`bug` unless the project uses
  another; ask if unsure).

## Step 6: the gates

Propose one gate per build root found, from the repo's own files. Look at
the root and one directory level down (skip `node_modules`, `.git`, build
output):

| Found | Proposed `run` |
| --- | --- |
| `package.json` with scripts | `npm run <lint> && npm run <typecheck> && npm run <test>` using only the scripts that exist (`lint`, `typecheck`/`check`/`tsc`, `test`, `build`) |
| `Makefile` with `lint`/`test` targets | `make lint && make test` |
| `pyproject.toml` / `setup.cfg` | `ruff check . && pytest` (or `pytest` alone when ruff is not configured) |
| `Package.swift` | `swift build && swift test` |
| `gradlew` | `./gradlew test` |
| `Cargo.toml` | `cargo clippy -- -D warnings && cargo test` |
| `go.mod` | `go vet ./... && go test ./...` |

Each gate: `name` (the directory, or `app` at the root), `cwd`, `run`,
`paths` (globs whose change makes the gate apply; `<dir>/**` plus the
manifest). Show the list and `AskUserQuestion`: accept, or the reader edits
in their own words (a project with an Xcode build or a device test will name
it here). Gates the reader names but the repo cannot run headlessly are
recorded with `"manual": true` so the tracking comment asks for their result
instead of running them.

## Step 7: git and GitHub

```bash
git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || git branch --show-current
git remote get-url origin 2>/dev/null
gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner + " " + .defaultBranchRef.name' 2>/dev/null
```

- `baseBranch`: `--base`, else the remote HEAD, else `main`. `protectedBranches`: the base.
- `route`: `gh` when `gh repo view` succeeded; `mcp` when only the GitHub MCP
  sees the repo; else `auto`.
- Patterns stay at their defaults (`{key}-{slug}`, `{key}: {subject}`,
  `[{key}] {title}`) unless the reader asks otherwise.

## Step 8: show the config, then write

Compose the config from the discovered values in the shape of
`${CLAUDE_PLUGIN_ROOT}/templates/jira-flow.example.json` (every key present;
empty strings where discovery found nothing). Show it whole. `AskUserQuestion`
to approve it, or take corrections and show it again.

Then `AskUserQuestion` (multiSelect) for which files to write; the config is
always written when approved, the rest are offered:

| File | From | Placeholders |
| --- | --- | --- |
| `.claude/jira-flow.json` | the approved config | |
| `<jira.taxonomy>` (default `.claude/jira/taxonomy.md`) | `templates/taxonomy.md` | `{{PROJECT_NAME}}`, `{{SITE}}`, `{{CLOUD_ID}}`, `{{KEY}}`, `{{DATE}}`, `{{EPICS_TABLE}}`, `{{LABELS}}`, `{{BUG_LABEL}}`, `{{T_TODO}}`, `{{T_IN_PROGRESS}}`, `{{T_IN_REVIEW}}`, `{{T_DONE}}` |
| `.claude/rules/jira-flow.md` | `templates/rules.md` | `{{KEY}}`, `{{PROJECT_NAME}}`, `{{SITE}}`, `{{TAXONOMY}}`, `{{PR_TEMPLATE}}` |
| `<git.prTemplate>` (default `.github/pull_request_template.md`) | `templates/pull_request_template.md` | `{{KEY}}`, `{{SITE}}`, `{{GATES}}` (one `- [ ] <name>: \`<run>\`` line per gate) |
| `.github/workflows/jira-key.yml` | `templates/jira-key.yml` | `{{KEY}}` |

Read each template from `${CLAUDE_PLUGIN_ROOT}/templates/`, fill the
placeholders, and write with the Write tool. A file that already exists is
never replaced silently: show what would change (a short diff) and ask.
Claude Code protects the `.claude/` folder, so the reader is asked to approve
those writes; if a write is refused, print the filled-in file so they can save
it themselves, and do not write it any other way.

The work state lives under the repo's git dir by default (nothing to ignore).
If the reader sets `work.stateDir` inside the tree, add it to `.gitignore`.

## Step 9: report

One line each: the site and project, the transition ids found (or "looked up
per issue"), the gates, the route, and every file written or skipped. Then how
the setup travels with the repo: commit the files, and install the plugin for
the project (`claude plugin marketplace add duttaarun/jira-flow-plugin`, then
`claude plugin install jira-flow@jira-flow --scope project`) or keep it at
user scope. Rules in `.claude/rules/` load from the next session on; in this
one, follow them from now. Suggest `/jira-flow:status` as the first thing to
run.
