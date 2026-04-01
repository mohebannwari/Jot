#!/bin/bash
# Block log-based debugging (NSLog, print(), os_log, Logger.)
# Rule: Never add temporary logging statements to diagnose issues.

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')

# Skip if no content to check
[[ -z "$CONTENT" ]] && exit 0

# Only check Swift files
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ "$FILE" != *.swift ]] && exit 0

# Match debug logging patterns (but not legitimate uses in logging infrastructure)
if echo "$CONTENT" | grep -qE '^\s*(NSLog\(|print\(|os_log\(|Logger\.\w+\()'; then
  echo "BLOCKED: No log-based debugging. Use subagents to research the root cause, read documentation, and reason about the architecture." >&2
  exit 2
fi
exit 0
