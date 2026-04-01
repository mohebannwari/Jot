#!/bin/bash
# Route Claude Code notifications through cmux's native notification system.

INPUT=$(cat)
TITLE=$(echo "$INPUT" | jq -r '.title // "Claude Code"')
BODY=$(echo "$INPUT" | jq -r '.body // "Needs your attention"')

cmux notify --title "$TITLE" --body "$BODY" 2>/dev/null
exit 0
