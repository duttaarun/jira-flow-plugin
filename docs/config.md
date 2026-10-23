# `.claude/jira-flow.json`

Written by `/jira-flow:init`, read by every skill and hook. Lives at the
project root; `JIRA_FLOW_CONFIG` points elsewhere when set. A project
without the file is not traced: the guard and the session hook stay silent,
the ship gate falls back to asking on every act.

The hooks find the project root from where each call runs, not from where
the session started, so a session opened in `~/projects` that works in
`~/projects/app` reads `app`'s config. In order:

1. `JIRA_FLOW_CONFIG`, when set.
2. The repo holding the call's folder (the hook input's `cwd`; its git
   toplevel, or the folder itself outside git), when it has the file.
3. `CLAUDE_PROJECT_DIR`, the folder the session started in.
4. The git toplevel of the hook process's working directory, else that
   directory.

A call's repo without a config falls through to 3, so a session started in a
configured repo keeps its config while it works in a sub-folder or a scratch
folder. `lib/state.sh` gets no hook input; the folder it runs in stands for
the call's folder. The call's folder is where the command starts: in
`cd ../other && gh pr create` the gate reads the config of the repo before
the `cd`.

```json
{
  "version": 1,
  "jira": { ... },
  "git": { ... },
  "gates": [ ... ],
  "work": { ... },
  "approvals": { ... },
  "ship": { ... }
}
```

## `jira`

| Key | Type | Meaning |
| --- | --- | --- |
| `site` | url | The Atlassian site, for browse links. Fallback: `JIRA_SITE_URL`, then the `self` URL in a tool response. |
| `cloudId` | string | Passed to the Atlassian MCP's execute-family tools. |
| `projectKey` | string | The project. The hooks' key regex is `<projectKey>-[0-9]+`. |
| `projectName` | string | For the rules and the taxonomy heading. |
| `issueTypes.{epic,story,task,bug,subtask}` | string | The type names as the project has them; `""` when the project lacks one (bugs then go as `task` plus the bug label). |
| `transitions.{todo,inProgress,inReview,done}` | string | Transition ids. An empty id is looked up on the issue by name when needed; `done` empty makes the ship gate match closes by name only. |
| `fields.storyPoints`, `fields.sprint` | string | Custom field ids; empty when the project has none. |
| `labels.bug` | string | The label bugs also carry (default `bug`). |
| `labels.platforms`, `labels.themes` | string[] | The label families the taxonomy prescribes; informational. |
| `taxonomy` | path | The epics, the path-to-epic table, the templates and the JQL (default `.claude/jira/taxonomy.md`). Skills fall back to the plugin's templates when the file is absent. |

## `git`

| Key | Type | Meaning |
| --- | --- | --- |
| `baseBranch` | string | Where PRs go (default `main`). |
| `protectedBranches` | string[] | The guard refuses `git commit` and `git push` on these. |
| `requireKey` | bool | The guard refuses a commit, push or `gh pr create` without the key in the branch or the command (default true). |
| `branch` | pattern | Branch name, `{key}-{slug}`. |
| `commit` | pattern | Commit subject, `{key}: {subject}`. |
| `prTitle` | pattern | PR title, `[{key}] {title}`. |
| `prTemplate` | path | The PR body template (default `.github/pull_request_template.md`). |
| `route` | `auto`, `gh`, `mcp` | How PRs are raised and merged. `auto` tries `gh`, then the GitHub MCP. |

## `gates[]`

| Key | Type | Meaning |
| --- | --- | --- |
| `name` | string | Shown in the tracking comment and the PR body. |
| `cwd` | path | Where `run` executes (relative to the project root). |
| `run` | shell | The command; its exit code is the result, its counts are quoted. |
| `paths` | glob[] | The gate applies when a changed file matches one; absent means always. |
| `manual` | bool | Not run: the reader is asked for the result (device tests, store builds). |

## `work`

| Key | Type | Meaning |
| --- | --- | --- |
| `checkpoint` | `step`, `phase` | Where `/jira-flow:work` stops during the build: after every step, or only at the gates. A checkpoint answer can switch to `phase` for the rest of the story. |
| `commitEach` | `never`, `step` | Commit after every approved step (`{key}: step k, ...`), or leave the tree for the ship phase. |
| `stateDir` | path | Where the per-key state JSON lives. Default: `<git dir>/jira-flow`, outside the tree. Inside the tree, add it to `.gitignore`. |

## `approvals`

| Key | Type | Meaning |
| --- | --- | --- |
| `createIssues` | bool | Ask before `plan` and `bug` create an issue (default false: filing is free). |
| `comments` | bool | Ask before `track` posts a comment (default false). `work` always shows and asks at its record checkpoint. |

## `ship`

| Key | Type | Meaning |
| --- | --- | --- |
| `askBefore` | subset of `["pr", "merge", "close"]` | Which acts the ship gate turns into a permission prompt (default all three). |
| `mergeMethod` | `merge`, `squash`, `rebase` | For `gh pr merge --<method>`. |
| `deleteBranchOnMerge` | bool | `--delete-branch` on merge. Stacked PRs based on the branch close with it: retarget first. |
| `waitForChecks` | bool | Wait for the PR's checks before merging (default true). |

## The state file

`<stateDir>/<KEY>.json`, managed by `lib/state.sh`; `current` holds the key
in flight. Never committed.

```json
{
  "key": "KEY-57", "summary": "...", "type": "Story", "epic": "KEY-10",
  "branch": "KEY-57-slug", "base": "main",
  "phase": "plan | build | verify | record | ship | done",
  "checkpoint": "step | phase",
  "plan": [{"n": 1, "what": "...", "files": [], "verify": "...", "status": "todo | doing | done | skipped"}],
  "outOfScope": [], "notes": [],
  "gates": [{"name": "app", "result": "pass | fail | not run", "at": "sha", "detail": "..."}],
  "followUps": [], "pr": {"url": "...", "number": 12},
  "startedAt": "...", "updatedAt": "..."
}
```
