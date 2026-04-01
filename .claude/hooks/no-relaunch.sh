#!/bin/bash
# Block launching/relaunching Jot.app.
# Rule: Do not relaunch the app after building. User handles relaunch via in-app updates panel.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$CMD" ]] && exit 0

if echo "$CMD" | grep -qE '(open\s+.*Jot\.app|open\s+-a\s+Jot|open\s+-a\s+"Jot")'; then
  echo "BLOCKED: Do not relaunch Jot. The user handles relaunch via the in-app updates panel." >&2
  exit 2
fi
exit 0
