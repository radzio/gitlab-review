# gitlab-review

Part of [Plugin Patisserie](https://github.com/radzio/plugin-patisserie) — artisanal Claude Code plugins, slow-proofed to perfection.

Claude Code plugin that triages unresolved GitLab MR review comments — analyze, plan, and reply.

## What it does

1. Fetches all unresolved discussions from the current branch's MR via `glab`
2. Reads referenced files for context
3. Categorizes each comment: **Actionable**, **Informational**, **Already addressed**, or **Needs clarification**
4. Produces a consolidated action plan
5. Optionally posts clarification replies directly to MR discussion threads

## Install

### Via marketplace (recommended)

```bash
claude plugin marketplace add https://github.com/radzio/plugin-patisserie
claude plugin install gitlab-review
```

### Standalone

```bash
claude plugin add https://github.com/radzio/gitlab-review
```

## Usage

On a branch with an open MR, run:

```
/triage
```

## Prerequisites

- [glab](https://gitlab.com/gitlab-org/cli) — `brew install glab`
- [jq](https://jqlang.github.io/jq/) — `brew install jq`
- Authenticated with GitLab: `glab auth login`
