#!/usr/bin/env bash
set -euo pipefail

# fetch-mr-discussions.sh
# Fetches MR metadata and unresolved discussions from GitLab via glab CLI.
#
# Exit codes:
#   0 - Success
#   1 - No MR found for current branch
#   2 - Missing required tools (glab or jq)
#   3 - API error

# --- Dependency check ---
for cmd in glab jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "{\"error\": \"Missing required tool: $cmd\"}" >&2
    exit 2
  fi
done

# --- Fetch MR metadata ---
mr_json=$(glab mr view -F json 2>/dev/null) || {
  echo "{\"error\": \"No merge request found for the current branch.\"}" >&2
  exit 1
}

iid=$(echo "$mr_json" | jq -r '.iid')
title=$(echo "$mr_json" | jq -r '.title')
web_url=$(echo "$mr_json" | jq -r '.web_url')
source_branch=$(echo "$mr_json" | jq -r '.source_branch')
target_branch=$(echo "$mr_json" | jq -r '.target_branch')

if [ -z "$iid" ] || [ "$iid" = "null" ]; then
  echo "{\"error\": \"Could not parse MR IID from glab output.\"}" >&2
  exit 1
fi

# --- Fetch discussions ---
discussions_json=$(glab api "projects/:fullpath/merge_requests/${iid}/discussions" 2>/dev/null) || {
  echo "{\"error\": \"Failed to fetch discussions from GitLab API.\"}" >&2
  exit 3
}

# --- Filter and format discussions ---
# Two categories:
#   1. Inline (unresolved): threaded discussions with resolvable, unresolved notes (not system)
#   2. General (human): individual notes that are not system and not resolvable
result=$(echo "$discussions_json" | jq --arg iid "$iid" \
  --arg title "$title" \
  --arg web_url "$web_url" \
  --arg source_branch "$source_branch" \
  --arg target_branch "$target_branch" '

  # Helper: extract notes with relevant fields
  def format_note:
    {
      author: .author.username,
      body: .body,
      created_at: .created_at,
      updated_at: .updated_at
    };

  # Inline unresolved discussions (threaded, resolvable, not resolved, not system)
  [.[] | select(
    .individual_note == false
    and (.notes | length > 0)
    and (.notes[0].system == false)
    and (.notes | any(.resolvable == true and .resolved == false))
  ) | {
    type: "inline",
    id: .id,
    file: (.notes[0].position.new_path // .notes[0].position.old_path // null),
    line: (.notes[0].position.new_line // .notes[0].position.old_line // null),
    notes: [.notes[] | select(.system == false) | format_note]
  }] as $inline |

  # General human comments (individual, not system, not resolvable)
  [.[] | select(
    .individual_note == true
    and (.notes | length > 0)
    and (.notes[0].system == false)
    and (.notes[0].resolvable == false)
  ) | {
    type: "general",
    id: .id,
    file: null,
    line: null,
    notes: [.notes[] | select(.system == false) | format_note]
  }] as $general |

  {
    mr: {
      iid: ($iid | tonumber),
      title: $title,
      web_url: $web_url,
      source_branch: $source_branch,
      target_branch: $target_branch
    },
    summary: {
      inline_unresolved: ($inline | length),
      general_comments: ($general | length),
      total: (($inline | length) + ($general | length))
    },
    discussions: ($inline + $general)
  }
')

echo "$result"
