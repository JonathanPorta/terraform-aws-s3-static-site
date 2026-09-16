# Pull request labels

`pr-labels.yml` replaces the separate auto-label workflow. It preserves both
check names: **Auto-Label Based on Branch Name** and **Validate Version Labels**.
The validator waits for the labeler and still runs if labeling fails. Existing
branch/domain mappings and case-insensitive matching are retained unchanged.

Each PR has its own concurrency group. The workflow reads PR metadata using
`pull_request_target`; it never checks out or executes PR code and does not load
deployment or Slack credentials. Label changes rerun the checks.

The validator comes from [blessed-cicd at `c065d9448ae7`](https://github.com/JonathanPorta/blessed-cicd/blob/c065d9448ae79f92008393ae8f1bdc3410b601e7/.github/workflows/pr-labels.yml).
Local adaptations preserve both existing check names, set its required policy
and default heading explicitly, and retain the existing bare `major` / `minor`
/ `patch` vocabulary. Exactly one is required; `version:*` labels do not satisfy
this repository's gate. Only `github-actions[bot]` owns reminder comments.

When refreshing, preserve these compatibility adaptations and the original
auto-label mappings. A direct reusable-workflow call changes check names; do not
switch without reconciling required checks. The obsolete `pr-auto-label.yml`
must stay removed so a second independent labeler cannot race this workflow.
