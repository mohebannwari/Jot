#!/bin/bash
# Block hardcoded Color() literals in Swift files.
# Rule: No hardcoded colors -- use asset catalog names or design tokens.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check Swift files
[[ "$FILE" != *.swift ]] && exit 0

CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')
[[ -z "$CONTENT" ]] && exit 0

# Match Color(red:green:blue:) or Color(.init(red:)) -- the RGB constructor pattern
# Allow Color("AssetName"), Color.primary, Color.white, etc.
if echo "$CONTENT" | grep -qE 'Color\(\s*red\s*:|Color\(\.init\(\s*red\s*:|NSColor\(\s*red\s*:'; then
  echo "BLOCKED: Hardcoded RGB Color() detected. Use asset catalog color names (e.g. Color(\"TokenName\")) or semantic colors (NSColor.labelColor)." >&2
  exit 2
fi
exit 0
