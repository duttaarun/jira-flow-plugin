# jira-flow

Jira tracing, PR gates and steered story work for any project.

- `/jira-flow:init` writes the project's `.claude/jira-flow.json` (site, key,
  transition ids, gates, base branch) and its taxonomy, rules, PR template
  and CI check, each shown and approved first.
- `/jira-flow:work KEY-n` runs a story from plan to PR with a checkpoint
  after every phase and step; resumes across sessions.
- `/jira-flow:status`, `plan`, `bug`, `track`, `pr`, `ship`.
- Hooks: the branch's issue at session start; the key guard on commits and
  pushes; the ship gate on PRs, merges and closes; the issue link after every
  Jira write.

Needs `jq`, `git`, the Atlassian MCP, and `gh` (or the GitHub MCP). See the
[repository README](../../README.md) for install, the flow, the ship gate and
every config key.
