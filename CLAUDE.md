# CLAUDE.md

## Project Overview

`gitlab-review` is a Claude Code plugin that triages unresolved GitLab merge request review comments. When invoked on a branch with an open MR, it fetches all unresolved discussions, reads the referenced source files for context, categorizes each comment (Actionable, Informational, Already addressed, Needs clarification), and produces a consolidated action plan. It can optionally post clarification replies back to MR discussion threads.

The plugin is **read-only with respect to code** -- it never modifies source files. The only write action it may perform is posting clarification comments to the MR, and only with explicit user approval.

## Project Structure

```
.claude-plugin/
  plugin.json          # Plugin manifest (name, version, description)
commands/
  triage.md            # The /triage slash command definition (prompt + tool permissions)
scripts/
  fetch-mr-discussions.sh  # Bash script that fetches MR metadata and discussions via glab CLI
README.md              # User-facing installation and usage docs
CLAUDE.md              # This file
```

### .claude-plugin/plugin.json

Minimal manifest declaring the plugin identity:
- **name:** `gitlab-review`
- **version:** `0.1.0`
- **description:** Triage unresolved GitLab MR review comments

### commands/triage.md

The sole command this plugin exposes: `/triage`. This is a Markdown file with YAML frontmatter that defines:
- **description** -- shown in command listings
- **allowed-tools** -- `Bash(glab:*)`, `Bash(bash:*)`, `Read`, `Grep`, `Glob`

The body is a structured prompt that instructs Claude through a 5-step workflow (see "How the Plugin Works" below).

### scripts/fetch-mr-discussions.sh

A standalone Bash script that:
1. Checks for required tools (`glab`, `jq`)
2. Fetches MR metadata via `glab mr view -F json`
3. Fetches all discussions via `glab api "projects/:fullpath/merge_requests/{iid}/discussions"`
4. Filters and formats them with `jq` into two categories:
   - **Inline unresolved** -- threaded, resolvable, not-yet-resolved, non-system notes
   - **General human** -- individual, non-system, non-resolvable notes
5. Outputs a single JSON object to stdout

Exit codes: `0` success, `1` no MR found, `2` missing tool, `3` API error.

## How the Plugin Works

The `/triage` command drives a 5-step workflow:

1. **Fetch MR Discussions** -- Runs `scripts/fetch-mr-discussions.sh` using `${CLAUDE_PLUGIN_ROOT}` to locate the script. Handles errors by exit code with user-friendly messages.

2. **Summarize MR** -- Displays MR number, title, branch info, URL, and unresolved comment counts. Stops early if zero discussions.

3. **Read Context** -- For inline comments, reads the referenced file around the specified line (plus/minus 20 lines). For general comments, checks if the body references files or code patterns and reads those if found. Bot-generated summaries are noted but skipped for file context.

4. **List Comments** -- Presents each comment in a structured format grouped by file, with an assessment category:
   - **Actionable** -- valid issue that should be fixed
   - **Informational** -- bot summary or FYI, no action needed
   - **Already addressed** -- the code already handles the concern
   - **Needs clarification** -- ambiguous, would need to ask the reviewer

5. **Action Plan** -- Produces three sections:
   - **Changes Required** -- file, line, what to change, why
   - **No Action Needed** -- informational/addressed items with one-line reasons
   - **Needs Clarification** -- ambiguous items with suggested questions; offers to post them as replies via `glab api POST`

Posting replies uses the GitLab API through glab:
```
glab api POST "projects/:fullpath/merge_requests/{iid}/discussions/{discussion_id}/notes" -f body="{message}"
```

## Development Conventions and Patterns

- **Single-command plugin.** The entire plugin surface is one slash command (`/triage`) defined as a Markdown prompt file.
- **Shell scripts for data fetching.** External tooling interaction is isolated in `scripts/`. The script is self-contained with dependency checks, structured JSON output, and semantic exit codes.
- **Prompt-driven logic.** All reasoning, categorization, and presentation logic lives in the command Markdown file as instructions to Claude, not in code.
- **`${CLAUDE_PLUGIN_ROOT}` variable.** Used in command prompts to reference scripts relative to the plugin installation directory.
- **Tool permissions are explicit.** The `allowed-tools` frontmatter in `triage.md` restricts which tools the command can use: only `Bash` (scoped to `glab` and `bash`), `Read`, `Grep`, and `Glob`.
- **Read-only by default.** The plugin never modifies source files. MR replies are the only write action and require explicit user approval.
- **jq for JSON processing.** The fetch script uses `jq` extensively for filtering and shaping GitLab API responses.
- **`:fullpath` shorthand.** glab's `:fullpath` is used in API calls so the script works without hardcoding project paths.

## Prerequisites and Local Testing

### Required tools

- [glab](https://gitlab.com/gitlab-org/cli) -- GitLab CLI (`brew install glab`)
- [jq](https://jqlang.github.io/jq/) -- JSON processor (`brew install jq`)
- Authenticated GitLab session: `glab auth login`

### Running locally

1. Install the plugin into Claude Code:
   ```bash
   claude plugin add /path/to/gitlab-review   # local path for development
   ```
2. Navigate to a Git repo with an open GitLab MR and check out the MR branch.
3. Run `/triage` inside Claude Code.

### Testing the fetch script standalone

```bash
cd /some/repo/with/open-mr
bash /path/to/gitlab-review/scripts/fetch-mr-discussions.sh
```

This outputs the raw JSON that the `/triage` command consumes. Verify the output includes `mr`, `summary`, and `discussions` keys.

## Notes for Contributors

- **Adding new commands:** Create a new `.md` file in `commands/` with YAML frontmatter (`description`, `allowed-tools`). The filename becomes the slash command name.
- **Modifying the fetch script:** Keep the JSON output contract stable -- the prompt in `triage.md` depends on the shape of the `mr`, `summary`, and `discussions` fields. If you change the schema, update the command prompt accordingly.
- **Exit code contract:** The command prompt maps exit codes 1, 2, 3 to specific user-facing error messages. New exit codes need corresponding handling in `triage.md`.
- **Plugin version:** Bump `version` in `.claude-plugin/plugin.json` when making changes.
- **No runtime dependencies beyond glab and jq.** Keep it that way -- the plugin should work on any macOS/Linux system with those two tools installed.
