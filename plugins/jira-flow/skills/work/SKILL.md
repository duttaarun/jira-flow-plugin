---
name: work
description: >-
  Work a Jira story or bug end to end with an approval checkpoint at every
  phase: read the issue and propose a plan, branch and move it to In
  Progress, build step by step, run the gates, record on the issue, then ask
  once before the PR, the merge and the close. The reader steers at each
  checkpoint (adjust, skip, run through, stop) and can resume in a later
  session. Use when asked to "work on KEY-n", "pick up KEY-n", "do KEY-n",
  "start the story", "resume", "what should I work on next", or to change
  course on a story in flight.
argument-hint: "[KEY-n] [steer note | --replan | --status | --stop | --abandon | --next]"
---

# Work a story, steered

Request: $ARGUMENTS

The reader chooses the story; the flow stops at a checkpoint after every
phase and after every step of the build, and nothing outward (a PR, a merge,
a close) happens without their word. State is kept per key outside the tree
(`lib/state.sh`), so a new session resumes where this one stopped.

## Step 0: the config and the state

Read `.claude/jira-flow.json` (missing: stop, `/jira-flow:init`). Take
`jira.*`, `git.*`, `gates`, `work.checkpoint` (default `step`),
`work.commitEach` (default `never`), `ship.*`.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state.sh" current
bash "${CLAUDE_PLUGIN_ROOT}/lib/state.sh" list
git branch --show-current
git status --short
```

Resolve the key:

- `KEY-n` in the arguments: that story. If another key is current in the
  state and mid-flow, say so and `AskUserQuestion`: switch to the new one
  (the old state stays parked, resumable later) or resume the old one.
- No key, a current state: resume it at its phase (tell the reader where it
  stands first).
- No key, no state, or `--next`: `searchJiraIssuesUsingJql` In Progress
  first, then To Do by priority (as `/jira-flow:status`), and `AskUserQuestion`
  with up to four candidates (key, summary, priority, points); "Other" takes
  a key.

Steering flags, applied before anything else:

| Flag | Does |
| --- | --- |
| `--status` | Print the state (phase, plan with each step's status, gates, PR) and stop. |
| `--replan` | Go back to Phase 1 with the current diff as context; keep the branch. |
| `--stop` | Keep the state, stop now, report what stands. |
| `--abandon` | `AskUserQuestion` to confirm; then comment on the issue why, move it back to To Do (id from the config, else by name), leave the branch, clear the state. |
| free text after the key | A steer note: fold it into the plan (or the next step) before the next checkpoint; record it under `notes` in the state. |

The state file's shape (all written through `state.sh set` / `merge`):

```json
{
  "key": "KEY-57", "summary": "...", "type": "Story", "epic": "KEY-10",
  "branch": "KEY-57-slug", "base": "main",
  "phase": "plan | build | verify | record | ship | done",
  "checkpoint": "step | phase",
  "plan": [{"n": 1, "what": "...", "files": ["..."], "verify": "...", "status": "todo | doing | done | skipped"}],
  "outOfScope": ["..."], "notes": ["..."],
  "gates": [{"name": "app", "result": "pass | fail | not run", "at": "sha", "detail": "..."}],
  "followUps": ["KEY-130"], "pr": {"url": "...", "number": 12},
  "startedAt": "...", "updatedAt": "..."
}
```

## Phase 1: read and plan

1. `getJiraIssue` (view `full`): summary, type, description, acceptance
   criteria, links, the last comments. For a bug, the steps and the suspect.
2. Read the repo where the issue lands: the taxonomy's path table for its
   epic, the project's rules in `.claude/rules/`, and the code the criteria
   name. Grep before guessing.
3. Draft the plan: three to eight numbered steps, each with what changes,
   the files, and how it is verified; the gates that will run (from the
   config, matched to the files); what is out of scope; open questions.
   Fold in any steer note from the arguments.
4. Save: `state.sh set <key>` with `phase: "plan"` and the plan's steps at
   `todo`.
5. **Checkpoint 1.** `AskUserQuestion`, header "Plan", the question naming
   the key, the step count and the branch that would be created:
   1. "Approve: branch, In Progress, then build step by step" (Recommended)
   2. "Approve and run through to the gates without stopping"
   3. "Adjust the plan" (the reader writes what changes; revise, save, ask again)
   4. "Hold" (the state stays at `plan`; report and stop)

   Option 2 sets `checkpoint: "phase"`; the build then stops only at the
   gates. An open question that decides the plan is asked here, as its own
   question, before the approval.

## Phase 2: start

Covered by the approval above; no second checkpoint.

1. Branch. If the current branch carries the key, keep it. Otherwise:
   - a clean tree: `git fetch origin <base>` then `git checkout -b <branch>
     origin/<base>`, the name from `git.branch` (`{key}-{slug}`);
   - a dirty tree: list the files. If they are this story's early edits,
     `git checkout -b <branch>` from HEAD carries them. If they belong to
     another story, `AskUserQuestion`: carry them, or stop so the reader can
     park them. Never stash silently. Files you did not touch mean another
     session works this tree: stop and ask which session finishes.
2. `transitionJiraIssue` to In Progress if the issue is To Do (id from the
   config, else `executeRead` `listJiraIssueTransitions` for the issue and
   take the one leading to the in-progress status).
3. Comment the approved plan on the issue from
   `${CLAUDE_PLUGIN_ROOT}/templates/plan-comment.md`.
4. `state.sh merge <key> '.phase = "build" | .branch = "<branch>"'`.

## Phase 3: build

For each step with status `todo`, in order:

1. `state.sh merge <key> '.plan[k].status = "doing"'`; do the step; verify it
   the way the plan says.
2. `state.sh merge <key> '.plan[k].status = "done"'`. With
   `work.commitEach: "step"`, commit the step's files now
   (`{key}: step k, <what>`); otherwise leave the tree uncommitted for the
   ship phase.
3. Report in four lines: what changed, `git diff --stat` for the step's
   files, what was verified, what the next step is.
4. **Checkpoint 3** (skipped while `checkpoint` is `phase`). `AskUserQuestion`,
   header "Step k/N":
   1. "Continue: step k+1, <what>" (Recommended)
   2. "Run through to the gates"
   3. "Adjust" (the reader writes; revise the remaining steps, save, continue)
   4. "Stop here" (the state stays; report and stop)

   A steer note given as the answer to any checkpoint is recorded under
   `notes` and applied from the next step on.

When every step is `done` or `skipped`: `state.sh merge <key> '.phase = "verify"'`.

## Phase 4: verify

1. Run the configured gates whose `paths` match the changed files (a gate
   without `paths` always runs; a `manual` gate asks for its result). Record
   each result at the current HEAD in the state's `gates`, with the counts
   the tool printed. No gates configured: say so, never invent a result.
2. Report the table honestly.
3. Green: `state.sh merge <key> '.phase = "record"'`, no checkpoint.
   Red: **Checkpoint 4.** `AskUserQuestion`, header "Gates":
   1. "Fix it and re-run" (propose the fix as a new plan step; back to Phase 3 for it)
   2. "Continue anyway; the PR will be a draft"
   3. "Stop here"

## Phase 5: record

1. Draft the tracking comment (Change, Files, Gates, Verified, Open, Branch;
   the taxonomy's template or `templates/comment.md`) and the follow-up
   issues found along the way (in the shape `/jira-flow:plan` and
   `/jira-flow:bug` use).
2. **Checkpoint 5.** Show the comment and the follow-ups in full, then
   `AskUserQuestion`, header "Record":
   1. "Post the comment and file N follow-ups" (Recommended)
   2. "Post the comment only"
   3. "Adjust" (the reader writes; revise and ask again)
   4. "Skip"
3. Post with `addOrEditJiraIssueComment`; create and link the follow-ups;
   record their keys under `followUps`. `state.sh merge <key> '.phase = "ship"'`.

## Phase 6: ship

Hand over to `/jira-flow:ship <key>`: it commits and pushes what is ready
without asking, then asks once (raise / raise and merge / raise, merge and
close / hold) and does exactly what was answered, with the `ask-before-ship`
hook prompting on each act as the backstop. On Done it clears the state.

## Report (at every stop)

```
Story:   KEY-57 "Service worker precaches the shell" (In Progress, epic KEY-10)
Branch:  KEY-57-service-worker @ 3f2a9c1, 4 files changed
Phase:   build, 2/5 steps done; next: step 3, register the worker in the layout
Gates:   not yet | app 3/3 ok @ 3f2a9c1
Resume:  /jira-flow:work KEY-57   (or --status, --replan, --stop, --abandon)
```
