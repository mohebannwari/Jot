# Jot Onboarding Flow

Universal features only -- no macOS 26 or Apple Intelligence gates.

---

## Feature Inventory (Ranked by Onboarding Value)

| # | Feature | What It Does | Why It's Onboarding Material |
|---|---------|-------------|------------------------------|
| 1 | **Slash Command Palette** | Type `/` anywhere to summon 20+ block types: code blocks, callouts, tables, tabs, cards, stickers, block quotes, dividers, lists, file links, images, voice recordings | The differentiator. Tells users in one gesture that Jot is a block editor, not a plain text box. Notion-level power, native Mac feel. |
| 2 | **Code Blocks with Syntax Highlighting** | Full syntax highlighting for 21 languages (Swift, Python, JS/TS, Rust, Go, SQL, HTML/CSS, and more) with language detection on paste | Developers immediately understand this isn't Apple Notes. Even non-developers find code blocks useful for snippets and config. |
| 3 | **Web Clips** | Paste a URL, choose "Web Clip," and get an embedded preview card with title, description, and domain -- fetched live | Visually striking. Turns a note into a research board. Most native Mac note apps can't do this. |
| 4 | **Split View** | Side-by-side note editing -- drag a note into the split picker, resize the divider, work on two notes simultaneously | Power users crave this. Demonstrates that Jot takes your workflow seriously. |
| 5 | **Version History** | Every note auto-snapshots up to 50 versions (30-second debounce, 30-day retention). Browse and restore any previous version from the toolbar. | The safety net. Users who've lost work in other apps feel immediate trust. |
| 6 | **Note Locking** | Per-note password protection with Touch ID / biometric auth. Auto-relock after 5 minutes. Locked notes are title-only in Spotlight. | Privacy-sensitive users (journals, sensitive meeting notes) need this. Table stakes for trust. |
| 7 | **@Note Mentions** | Type `@` to link to another note. Creates navigable cross-references between notes. | Turns a flat list into a connected knowledge base. Small feature, enormous depth signal. |
| 8 | **Drag-and-Drop Everything** | Drop images, PDFs, documents, any file directly into a note. | The most intuitive demo possible -- just drag something in. |
| 9 | **Flexible Export + Import** | Export: PDF, Markdown, HTML, Plain Text (single or bulk). Import: PDF, Markdown, HTML, RTF, DOCX, CSV. | Zero vendor lock-in. The anti-walled-garden message. |
| 10 | **Siri Shortcuts + Spotlight** | 4 App Intents (Create, Append, Open, Search). Full Spotlight indexing with content search. | Native Mac citizenship. Notes are part of the system, not trapped in an app. |
| 11 | **Automatic Backups** | Configurable: manual, daily, or weekly. Full JSON backups with images, files, and folders. Auto-pruning. Restore with safety snapshot. | Silent guardian. Users don't think about backups until they need one. |
| 12 | **Customization** | 3 themes (light/dark/auto), 3 font families (Charter serif, System/SF Pro, Monospace), adjustable font size, 3 line spacing options (compact/default/relaxed) | Personal. Makes the app feel yours in 10 seconds. |

---

## Onboarding Flow: 5 Screens

Principle: **capability, then confidence, then identity.** First show what it can do. Then show why your data is safe. Then show it adapts to you.

---

### Screen 1: "Your notes, unboxed"

**Hero feature:** Slash Command Palette

Show the `/` menu expanding with all block types. This single screen communicates: "This is a real editor."

**Supporting beats:**
- Code blocks with syntax highlighting
- Tables, callouts, tabs, cards
- Stickers (post-it notes)

**Visual direction:** Animated demo of typing `/` and the palette materializing. Cycle through inserting a code block, a callout, and a table in quick succession.

---

### Screen 2: "Bring it all in"

**Hero feature:** Drag-and-drop + Web Clips

Show content flowing into a note from multiple sources.

**Supporting beats:**
- Drag files and images directly in
- Paste a URL, get an embedded web clip preview
- @mention to link notes together
- Import from Markdown, DOCX, PDF, HTML, RTF, CSV

**Visual direction:** A note containing an embedded web clip, a dropped PDF, an inline image, and an @mention link -- all in one view. The "everything in one place" moment.

---

### Screen 3: "Work in parallel"

**Hero feature:** Split View

Show two notes side-by-side, referencing each other.

**Supporting beats:**
- Side-by-side editing with resizable divider
- Find on page (floating search overlay)
- Keyboard shortcuts for power navigation

**Visual direction:** A split view with a research note on the left and a draft on the right. Clean, functional, professional.

---

### Screen 4: "Your notes are safe"

**Hero feature:** Version History + Automatic Backups

The trust-building screen. Show the version timeline with restore capability.

**Supporting beats:**
- 50 auto-snapshots per note, browsable and restorable
- Automatic backups (daily/weekly) with one-click restore
- Note locking with Touch ID / password
- Export to PDF, Markdown, HTML -- your data is never trapped

**Visual direction:** The version history timeline with a before/after comparison of a restored note. A lock icon animation for the locking feature.

---

### Screen 5: "Make it yours"

**Hero feature:** Customization + System Integration

Show the settings panel morphing the editor's appearance.

**Supporting beats:**
- Light / Dark / Auto themes
- 3 font families (serif, sans, mono) with size and spacing controls
- Siri Shortcuts: "Hey Siri, create a note in Jot"
- Spotlight search: find any note from anywhere in macOS
- Folders with color coding, pinning, sorting options

**Visual direction:** Side-by-side comparison of the same note in Charter serif vs. Monospace, or light vs. dark theme. A quick flash of the Siri Shortcuts integration.

---

## Design Notes

- **Screen 1 is make-or-break.** The slash command palette is the single most demonstrable differentiator from Apple Notes, Bear, and other native Mac editors. If you animate nothing else, animate this.
- **Screen 4 (safety) converts skeptics.** Users burned by data loss in other apps will latch onto version history + backups as the reason to stay. Trust is the hardest thing to earn and the easiest to lose.
- **@mentions in Screen 2 is a sleeper hit.** It signals "knowledge graph" without saying it. Power users see Obsidian-like potential. Casual users ignore it harmlessly.
- **Deliberately absent: Apple Intelligence and Liquid Glass.** These are gated features that would make pre-macOS 26 users feel like second-class citizens during their first experience. Let those surface organically via contextual discovery (a subtle badge or tooltip when the user's system supports them).
