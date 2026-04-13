#!/bin/bash
# Re-inject critical project rules after context compaction.
cat <<'EOF'
POST-COMPACTION CONTEXT REFRESH:
1. NO log-based debugging -- no print(), NSLog, os_log. Dispatch subagents to research root causes.
2. NO fix without root cause -- specificity or silence.
3. Run xcodebuild only when the user asks for a build, verification, tests, or the DEBUG update-panel flow -- not after every Swift edit.
4. Do NOT relaunch the app after a build -- user handles relaunch via in-app update panel when applicable.
5. Use NSColor.labelColor everywhere -- no hardcoded dark/light RGB tuples.
6. Sidebar row height: 34pt. Concentric radii: outer 16, inner = outer - padding.
7. Design tokens live in .claude/rules/design-system.md -- reference before any UI work.
8. Meeting sessions: [MeetingSession] JSON-encoded Data on NoteEntity.
9. Rich text serialization: [[b]], [[i]], [[u]], [[s]], [[h1-3]], [[align:X]], [[color|hex]], etc.
10. Workflow is auto-ingested from .claude/rules/workflow.md.
EOF
