#!/usr/bin/env python3
"""One-shot generator for docs/Jot_Application_Scope.pdf (reportlab)."""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_JUSTIFY
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate

OUT = Path(__file__).resolve().parent / "Jot_Application_Scope.pdf"


def main() -> None:
    styles = getSampleStyleSheet()
    title = ParagraphStyle(
        name="ScopeTitle",
        parent=styles["Heading1"],
        fontSize=22,
        spaceAfter=14,
        textColor=colors.HexColor("#1a1a1a"),
    )
    h2 = ParagraphStyle(
        name="ScopeH2",
        parent=styles["Heading2"],
        fontSize=14,
        spaceBefore=16,
        spaceAfter=8,
        textColor=colors.HexColor("#1a1a1a"),
    )
    body = ParagraphStyle(
        name="ScopeBody",
        parent=styles["Normal"],
        fontSize=10,
        leading=14,
        alignment=TA_JUSTIFY,
        spaceAfter=6,
    )
    meta = ParagraphStyle(
        name="ScopeMeta",
        parent=styles["Normal"],
        fontSize=9,
        leading=12,
        textColor=colors.HexColor("#444444"),
        spaceAfter=12,
    )
    bullet = ParagraphStyle(
        name="ScopeBullet",
        parent=body,
        leftIndent=18,
        bulletIndent=8,
    )

    story: list = []

    story.append(Paragraph("Jot Application Scope", title))
    story.append(
        Paragraph(
            "macOS note-taking app | Bundle ID <b>com.mohebanwari.Jot</b> | "
            "Document generated from repository state (README, roadmap, onboarding spec, project layout). "
            "<b>April 12, 2026</b>",
            meta,
        )
    )
    story.append(
        Paragraph(
            "Jot is a native macOS 26+ (Tahoe) application built with SwiftUI and AppKit interop "
            "(NSTextView-based rich editor), SwiftData persistence, and Apple&rsquo;s Liquid Glass "
            "design language. Data is local-first; iCloud sync is explicitly out of scope.",
            body,
        )
    )

    story.append(Paragraph("1. Current product capabilities (shipped)", h2))
    caps = [
        "Liquid Glass UI: morphing glass effects, semantic colors from asset catalog, light/dark/system appearance.",
        "Notes model: create, edit, autosave, pin, archive, soft-delete (trash with restore), tags, sorting, full-text search with debouncing and recent queries.",
        "Folders: color-coded organization, archive support; Quick Notes inbox folder for global capture.",
        "Split-pane editing: side-by-side notes with adjustable divider; properties panel (fixed slot in layout).",
        "Rich text: bold, italic, underline, strikethrough; headings H1&ndash;H3; alignment; custom text color; lists and tables; inline links.",
        "Block editor: slash-driven insertion for code blocks, callouts, tables, tab containers, cards, stickers, block quotes, dividers, file links, images, voice blocks, and related block types.",
        "Code blocks: syntax highlighting for 20+ languages with language detection on paste.",
        "Todos: inline checkbox items with serialized markup round-trip.",
        "Cross-notes: @-mention other notes for navigable links.",
        "Attachments: images (inline, width ratio, gallery-style treatment); generic file attachments with QuickLook-style preview renderers (e.g. PDF, audio, video, text).",
        "Web content: Web Clips (Open Graph metadata); Link Card paste option with async metadata via WebMetadataFetcher and dedicated serialization tag.",
        "Audio and meetings: inline voice capture with waveform; live transcription; meeting recordings support multi-session storage with AI-generated meeting summaries and transcript tabs.",
        "Meetings: meeting notes with multi-session support (dedicated models and UI slots in note detail).",
        "Version history: automatic note snapshots (debounced), browse/restore prior versions from the note toolbar.",
        "Privacy: per-note locking with biometric re-auth patterns (Touch ID / system biometric) and title-only exposure where applicable (e.g. Spotlight).",
        "AI writing tools: summarization, key points, proofreading, and rewrite flows via Apple Intelligence / FoundationModels integration.",
        "Import / export: export to PDF, Markdown, HTML (and plain text workflows); import pipeline covers Markdown (including setext headings, indented code, blockquote rules), PDF, HTML, RTF, DOCX, CSV per onboarding documentation.",
        "Backups: configurable automatic backups (manual/daily/weekly), JSON payloads with assets, pruning, restore with safety snapshot (per onboarding spec).",
        "Themes & typography: Charter (default body), SF Pro system, SF Mono; adjustable sizing; line spacing presets (compact, default, relaxed).",
        "Platform integration: App Intents for Shortcuts (create note, open note, search notes, append to note); Spotlight indexing with content search; macOS Share extension target (ShareExtension.appex).",
        "Quick Notes: user-configurable global hotkey (default Control-Shift-J) opens floating NSPanel for plain-text capture; Carbon RegisterEventHotKey (sandbox-friendly); settings UI for shortcut recording.",
        "Power UX: comprehensive keyboard shortcuts and menu commands; toast-based undo for destructive operations (delete, move, archive, pin changes) per feature roadmap batch work.",
        "Developer experience (Debug): BuildWatcherManager surfaces an in-sidebar update prompt when Jot.debug.dylib changes after xcodebuild.",
    ]
    for line in caps:
        story.append(Paragraph(f"&bull; {line}", bullet))

    story.append(Paragraph("2. Near-term roadmap (Linear DES-301)", h2))
    story.append(
        Paragraph(
            "<b>Not implemented yet:</b> Smart folders (saved filter predicates in sidebar). "
            "<b>Editor research:</b> collapsible sections under headings (fold to next heading). "
            "<b>Exploration:</b> MapKit inline map pin snapshots. "
            "<b>Deferred:</b> real-time collaboration, document scanner, WidgetKit widgets, deeper Siri/voice beyond existing App Intents.",
            body,
        )
    )

    story.append(Paragraph("3. Explicitly excluded", h2))
    excluded = [
        "iCloud / cloud sync (local-first by design)",
        "Math Notes",
        "Drawing / handwriting (PencilKit) and handwriting search",
        "Apple Watch or phone-centric capture features",
    ]
    for line in excluded:
        story.append(Paragraph(f"&bull; {line}", bullet))

    story.append(PageBreak())
    story.append(Paragraph("4. Engineering scope", h2))
    story.append(
        Paragraph(
            "<b>Primary targets:</b> macOS 26+ with Xcode 26+ / macOS 26 SDK. "
            "<b>Stack:</b> SwiftUI, SwiftData, AVFoundation (audio), Speech (transcription), "
            "FoundationModels (where available for AI), AppKit bridges for NSTextView and overlays. "
            "<b>Major code areas:</b> ContentView (shell, sidebar, split sessions), "
            "TodoEditorRepresentable / TodoRichTextEditor (editor), SimpleSwiftDataManager (persistence), "
            "TextFormattingManager, RichTextSerializer, NoteExportService, NoteImportService, ThemeManager, GlassEffects.",
            body,
        )
    )
    story.append(
        Paragraph(
            "<b>Quality bar:</b> design tokens from xcassets (no ad-hoc hex in UI code), "
            "NSColor.labelColor for AppKit text, concentric corner radii, documented rich-text tag grammar for serialization.",
            body,
        )
    )

    story.append(Paragraph("5. References in repo", h2))
    story.append(
        Paragraph(
            "README.md (feature list), Linear DES-301 (phases and backlog), "
            "docs/plans/ONBOARDING_PLAN.md (full feature inventory), "
            "AGENTS.md at repository root (architecture and conventions; `.claude/CLAUDE.md` symlinks here), "
            "Jot/Intents/*.swift (Shortcuts surface area).",
            body,
        )
    )

    doc = SimpleDocTemplate(
        str(OUT),
        pagesize=letter,
        rightMargin=0.75 * inch,
        leftMargin=0.75 * inch,
        topMargin=0.75 * inch,
        bottomMargin=0.75 * inch,
        title="Jot Application Scope",
        author="Jot",
    )
    doc.build(story)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
