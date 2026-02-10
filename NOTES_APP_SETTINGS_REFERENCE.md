# Notes App Settings Reference

Comprehensive research on settings from leading notes applications. Organized by category with mandatory/optional designation for quick reference.

---

## Quick Reference Matrix

| Category | Notion | Apple Notes | Evernote | OneNote | Obsidian | Bear | Slite | Confluence |
|----------|--------|------------|----------|---------|----------|------|-------|-----------|
| **Theme/Appearance** | M | O | UI | UI | M | O | O | - |
| **Default Font** | UI | UI | M | M | - | - | - | - |
| **Account/Auth** | M | M | M | M | M | M | M | - |
| **Encryption** | - | - | - | - | M | O | - | - |
| **Sync Settings** | - | - | O | O | M | M | - | - |
| **Sharing** | - | - | - | M | - | - | M | M |
| **Permissions** | - | - | - | M | - | - | M | M |
| **Auto-Format** | - | - | O | M | - | - | - | - |
| **Markdown** | O | - | - | - | M | - | - | - |

**M = Mandatory | O = Optional | UI = UI/Visual only | - = Not Applicable**

---

## 1. ACCOUNT & AUTHENTICATION SETTINGS

### 1.1 Mandatory

| Setting | Apps | Description | Impact |
|---------|------|-------------|--------|
| **Account Creation** | All | Email-based account setup (password required) | Core functionality—blocks cloud sync without it |
| **Default Account** | Notion, Apple Notes, Evernote | Specifies account for Siri-created notes or quick capture | Routes notes to correct location |
| **Account Password** | All | Primary authentication credential | Prevents unauthorized access |

### 1.2 Optional

| Setting | Apps | Description | Impact |
|---------|------|-------------|--------|
| **Two-Factor Authentication (2FA)** | Obsidian, Bear, Standard Notes | Additional security layer | Prevents account compromise |
| **Single Sign-On (SSO)** | Slite, Confluence | OAuth/identity provider integration | Enterprise adoption requirement |
| **Session Management** | Bear, Standard Notes | Trust this device, auto-logout timers | Security vs. convenience tradeoff |

---

## 2. APPEARANCE & THEME SETTINGS

### 2.1 Mandatory

| Setting | Apps | Description | UI Impact |
|---------|------|-------------|----------|
| **Theme Selection** | Notion, Obsidian, Drafts | Light/dark mode choice (often includes system preference) | Foundation for entire UI—affects readability |
| **Language Selection** | Notion | Determines UI language across all workspaces | Critical for international users |

### 2.2 Optional (UI/Visual Only)

| Setting | Apps | Description | Visual Impact |
|---------|------|-------------|--------|
| **Page Width** | Notion | Column width adjustment for reading comfort | Visual formatting, not functional |
| **Text Size** | Apple Notes, OneNote, Drafts | Global text scaling (separate from font size) | Accessibility, doesn't affect data |
| **Small Text Toggle** | Notion | Reduces text rendering size globally | Visual preference only |
| **Theme Customization** | Drafts, MarkEdit | Custom CSS or preset theme selection | Visual only—no functional change |
| **Font Selection** | Evernote (defaults), OneNote (defaults), Drafts | Choose between sans-serif, serif, mono | Presentation only |
| **Font Color** | Notion, Apple Notes | Text color customization | Visual customization |
| **Group by Date** | Apple Notes | Timeline organization view | Display only—data unchanged |

---

## 3. EDITOR & FORMATTING SETTINGS

### 3.1 Mandatory

| Setting | Apps | Description | Functional Impact |
|---------|------|-------------|------------------|
| **Default Font Family** | Evernote, OneNote | System font selection for new notes | Core editing experience |
| **Base Font Size** | Drafts, Evernote, OneNote | Pixel or unit-based sizing | Readability foundation |
| **Syntax Highlighting** | Drafts, MarkEdit | Code language selection per draft | Required for code display |
| **Auto-Numbering** | OneNote | Automatic list formatting (type "1." + space) | Productivity feature enabled by default |
| **Auto-Bullet Lists** | OneNote | Automatic bullet creation (type "-" or "*" + space) | Productivity feature enabled by default |
| **Calculate Math Expressions** | OneNote | Auto-solve calculations (type "1+1=" + enter) | Computational feature always on |

### 3.2 Optional

| Setting | Apps | Description | Functional Impact |
|---------|------|-------------|------------------|
| **Markdown Support** | Obsidian, MarkEdit, Drafts | Live markdown typing or paste-only | Workflow choice—affects note-taking speed |
| **Auto-Matching** | Drafts, Apple Notes | Auto-pair brackets, quotes, parentheses | Convenience—doesn't affect output |
| **Spell Check** | Drafts, OneNote | Enable/disable spelling validation | Quality control preference |
| **Grammar Check** | Drafts | Enable/disable grammar suggestions | Optional enhancement (macOS only) |
| **Text Suggestions** | Evernote, OneNote | Word prediction during typing | Convenience feature |
| **Smart Quotes/Dashes** | Drafts, Apple Notes | Automatic typography fixes | Cosmetic improvement—optional |
| **Auto-Save Delay** | MarkEdit | Idle timer before auto-save trigger | Performance/safety preference |
| **Indent Behavior** | MarkEdit, Drafts | Paragraph vs. line-level indentation | Editing preference—affects workflow |
| **Visible Whitespace** | MarkEdit | Show spaces and line breaks | Debug/reference aid—visual only |
| **Typewriter Scrolling** | Drafts | Center cursor mid-screen during edit | Comfort preference |
| **Cursor Placement** | Drafts | Resume at last position, top, or bottom of draft | User preference |

---

## 4. CONTENT STRUCTURE & TEMPLATES

### 4.1 Mandatory

| Setting | Apps | Description | Impact |
|---------|------|-------------|--------|
| **Default Note Format** | Apple Notes | Title + body structure | Determines note composition |
| **New Note Style** | Apple Notes, Evernote | Title, heading, or normal paragraph start | Affects initial content entry |

### 4.2 Optional

| Setting | Apps | Description | Impact |
|---------|------|-------------|--------|
| **Collapsible Sections** | Apple Notes, Notion | Headings/subheadings fold for document navigation | Organization aid—improves UX |
| **Table Support** | Apple Notes, Notion | Native table creation and editing | Structured data—optional |
| **Checklist Format** | Apple Notes, Notion | Pre-formatted checkbox lists | Task management convenience |
| **Paragraph Styles** | Apple Notes, Drafts | Preset formatting (title, heading, body) | Quick styling without manual formatting |
| **Text Alignment** | Apple Notes | Left, center, right, justify | Cosmetic preference |
| **Header Font Sizing** | MarkEdit | Custom scaling array for H1–H6 | Visual hierarchy customization |

---

## 5. DATA STORAGE & SYNC SETTINGS

### 5.1 Mandatory

| Setting | Apps | Description | Functional Impact |
|---------|------|-------------|------------------|
| **Storage Location** | Obsidian (declares local) | User aware of whether data is local or cloud | Critical for data portability/control |

### 5.2 Optional

| Setting | Apps | Description | Functional Impact |
|---------|------|-------------|------------------|
| **Cloud Sync Toggle** | Obsidian, Bear, Evernote | Enable/disable cloud synchronization | Determines sync behavior across devices |
| **Selective Sync** | Obsidian | Choose specific folders/file types to sync | Bandwidth/storage optimization |
| **Sync Encryption Password** | Obsidian | User-managed encryption for synced data | Security enhancement—optional |
| **Auto-Sync Frequency** | MarkEdit | Configure save-on-idle timing | Performance tuning |
| **Device Trust Settings** | Bear, Standard Notes | Remember this device to skip re-login | Convenience vs. security tradeoff |

---

## 6. SECURITY & ENCRYPTION SETTINGS

### 6.1 Mandatory

| Setting | Apps | Description | Security Impact |
|---------|------|-------------|------------------|
| **Encryption Algorithm** | Standard Notes (XChaCha20-Poly1305) | Encryption enforced—not optional | End-to-end data protection |

### 6.2 Optional (User Choice)

| Setting | Apps | Description | Security Impact |
|---------|------|-------------|------------------|
| **Encryption Password** | Obsidian (for Sync) | User can manage or let app manage encryption | Full vs. delegated control |
| **Individual Note Encryption** | Bear (Pro), Roam (blocks) | Password-protect specific notes | Granular security |
| **Advanced Data Protection** | Bear | Zero-knowledge encryption for iCloud | Maximum privacy—requires 2FA |
| **Passcode Lock** | Standard Notes | Local encryption separate from account password | Offline security |
| **Password Protection** | Apple Notes | Lock specific notes with passcode/Touch ID | Selective security |
| **Touch ID/Biometric** | Apple Notes | Biometric unlock for password-protected notes | Convenience security |

### 6.3 Optional (Administrative)

| Setting | Apps | Description | Impact |
|---------|------|-------------|--------|
| **Lock Sections on Navigation** | OneNote | Auto-lock password-protected sections when leaving | Security automation |
| **Lock Duration Timer** | OneNote | Set auto-lock after inactivity (1 min–1 day) | Convenience + security tradeoff |

---

## 7. SHARING & COLLABORATION SETTINGS

### 7.1 Mandatory (For Shared Content)

| Setting | Apps | Description | Functional Impact |
|---------|------|-------------|------------------|
| **Sharing Toggle** | OneNote, Slite, Confluence | Enable/disable sharing for notebooks/documents | Core collaboration feature |
| **Permission Levels** | OneNote, Slite, Confluence | View-only, edit, or admin roles | Access control—critical for team use |

### 7.2 Optional (Sharing Configuration)

| Setting | Apps | Description | Impact |
|---------|------|-------------|--------|
| **Link-Based Sharing** | OneNote, Slite | Generate shareable links with restrictions | Public/internal sharing option |
| **Individual User Sharing** | OneNote, Google Keep | Add collaborators by email/name | Fine-grained access |
| **Group-Based Sharing** | Slite, Confluence | Assign permissions to user groups | Bulk access management |
| **Anyone/Anyone in Org Links** | OneNote, Slite | Preset access levels for quick sharing | Convenience feature |
| **Section/Page-Level Permissions** | OneNote (sections), Confluence (pages) | Override notebook/space permissions | Granular access control |
| **Permission Inheritance** | Confluence | Control cascading permissions from parent to child | Structural—required for hierarchy |
| **Collaborator Removal** | All (sharing apps) | Revoke access for specific users | Access management |
| **External User Support** | OneNote, Slite | Allow/disallow sharing with outside organization | Admin control—optional |
| **SSO Integration** | Slite, Confluence | Connect via identity providers (Okta, Azure AD) | Enterprise integration |

---

## 8. NOTIFICATION & MENTION SETTINGS

### 8.1 Optional

| Setting | Apps | Description | Impact |
|---------|------|-------------|--------|
| **@Mention Notifications** | Apple Notes, Slite | Toggle alerts when name is mentioned | Engagement control |
| **Email Digests** | Evernote | Toggle notification email subscriptions | Communication preference |
| **Activity Alerts** | Slite, Confluence | Notifications for document changes/comments | Awareness control |
| **Watch/Unwatch Pages** | Confluence | Subscribe/unsubscribe from page updates | Selective notifications |

---

## 9. CONTENT ORGANIZATION SETTINGS

### 9.1 Optional

| Setting | Apps | Description | Impact |
|---------|------|-------------|--------|
| **Sort Order** | Apple Notes, Evernote | By date created, date edited, title, or custom | View preference |
| **Sort by Date** | Apple Notes | Group notes by creation/edit timeline | Display organization |
| **Default Notebook/Collection** | Evernote, Slite | Specify where new notes land | Workflow convenience |
| **Tag Management** | Evernote, Bear | Organize via custom tags and tags summary | Navigation aid |
| **Channels/Collections** | Slite, Confluence | Create sub-workspaces for organization | Hierarchical organization |
| **Custom Views/Filters** | Slite, Confluence | Customize content display and sorting | Information architecture |

---

## 10. ADVANCED FEATURES & PRODUCTIVITY

### 10.1 Optional

| Setting | Apps | Description | Functional Impact |
|---------|------|-------------|------------------|
| **AI Features Toggle** | Evernote (2025+) | Enable/disable individual AI tools | Feature control |
| **Focus Mode** | Evernote | Distraction-free editing | Productivity enhancement |
| **Calculation Suggestions** | Evernote | Show auto-calculation hints | Optional productivity aid |
| **OCR/Text Recognition** | Apple Notes, OneNote, Evernote | Extract text from images | Optional feature—off by default in some apps |
| **Audio/Video Recording** | OneNote | Control quality settings and playback behavior | Performance tuning |
| **Audio Search** | OneNote | Speech recognition in recordings | Optional (off by default for performance) |
| **Ink Support** | OneNote | Handwritten annotation settings | Platform-specific feature |
| **Include Web Source Links** | OneNote | Auto-paste source URL when clipping web content | Citation automation |
| **Link Creation Shortcut** | OneNote | Create links via bracket syntax [[phrase]] | Convenience feature |
| **Show Text Suggestions** | OneNote | Word prediction while typing | UX enhancement |
| **When Images Move, Also Move Ink** | OneNote | Keep handwritten annotations with moved images | Usability refinement |
| **History/Revision Tracking** | Standard Notes (paid), Roam | Version control and undo depth | Data recovery and audit trail |
| **Email Backups** | Standard Notes (paid) | Daily encrypted backups delivered to email | Data safety—paid feature |

---

## 11. IMPORT/EXPORT & BACKUP SETTINGS

### 11.1 Optional

| Setting | Apps | Description | Functional Impact |
|---------|------|-------------|------------------|
| **Backup Format** | Standard Notes | Encrypted vs. decrypted export | Security/accessibility tradeoff |
| **Data Export** | All | Single file, Markdown, JSON, or multi-file export | Portability |
| **Automatic Backups** | Bear, Roam | Native backup generation | Data safety |
| **Third-Party Integration** | Obsidian | GitHub, Dropbox, Google Drive backup | Extended backup options |
| **Refresh Font Defaults** | Evernote | Reset all text styling to defaults via UI button | Quick reset option |

---

## 12. PLATFORM-SPECIFIC & ACCESSIBILITY

### 12.1 Optional

| Setting | Apps | Description | Impact |
|---------|------|-------------|--------|
| **Desktop Startup Behavior** | Notion | Continue where you left off vs. specific default page | Workflow preference |
| **Always Resume to Last Quick Note** | Apple Notes | Auto-reopen previous session | Convenience |
| **Automatically Sort Checked Items** | Apple Notes | Move completed checklist items in sort order | Task management refinement |
| **Show Mention Notifications Badge** | Apple Notes | Visual indicator for collaborative mentions | Engagement signal |
| **Quick Notes Window Docking** | OneNote | Customize Quick Notes float position and behavior | Workspace customization |
| **Show OneNote Icon in Taskbar** | OneNote | System tray notification icon | Accessibility |
| **Profile Discoverability** | Notion | Make profile discoverable to others | Social/sharing preference |
| **Orientation Lock** | Drafts | Restrict device orientation | Mobile UX preference |
| **Maximum Line Width** | MarkEdit | Readability improvement for wide screens | Reading comfort |
| **Paragraph Spacing & Margins** | MarkEdit, Drafts | Visual spacing customization | Readability preference |
| **Status Bar Visibility** | Drafts | Toggle status bar display | UI preference |
| **Toolbar Customization** | Drafts, MarkEdit | Custom items and icon selection | UX personalization |
| **Custom Keyboard Shortcuts** | Evernote, Drafts, MarkEdit | Rebind keyboard commands | Workflow efficiency |
| **Global Hotkey** | MarkEdit | System-wide window toggle | Quick access |
| **Alternate App Icons** | Drafts (Pro) | Change app icon appearance | Cosmetic preference |

---

## 13. ENTERPRISE & ADMIN SETTINGS

### 13.1 Workspace Level

| Setting | Apps | Description | Required/Optional |
|---------|------|-------------|------------------|
| **External Sharing Toggle** | Google Keep (admin), Slite | Enable/disable sharing outside organization | Admin-controlled (optional) |
| **Sharing Suggestions** | Google Keep (admin) | Turn suggestions on/off | Admin-controlled (optional) |
| **Keep Enable/Disable** | Google Keep (admin) | Turn app on/off for all users | Admin-controlled (mandatory for org) |
| **User Groups** | Slite, Confluence | Manage team member access in bulk | Optional but efficient |
| **Space Admin** | Confluence | Assign administrators per space | Required (functional) |
| **Permission Hierarchy** | Confluence | Control cascading permissions | Required (structural) |

---

## 14. SUMMARY BY USE CASE

### Personal Note-Taker (Single User)
**Mandatory:** Theme, default font, account authentication
**Recommended Optional:** Backup format, auto-save frequency, markdown support, collapsible sections

### Team Collaborator
**Mandatory:** Account auth, sharing toggle, permission levels, notifications
**Recommended Optional:** SSO, user groups, activity alerts, @mentions, revision history

### Privacy-Conscious User
**Mandatory:** Encryption algorithm, account password
**Recommended Optional:** 2FA, zero-knowledge encryption, individual note encryption, local storage preference

### Power User/Researcher
**Mandatory:** Markdown support, syntax highlighting, tagging/organization
**Recommended Optional:** Custom keyboard shortcuts, theme customization, multi-format export, OCR

### Enterprise Deployment
**Mandatory:** SSO/identity provider, permission inheritance, admin controls, user groups
**Recommended Optional:** Audit trails, revision history, data loss prevention (DLP), compliance features

---

## 15. JOT RECOMMENDATION FRAMEWORK

### Absolute Must-Haves
- Account authentication (email/password)
- Theme selection (light/dark)
- Default font family + size
- Account specification (where new notes land)

### High-Priority Optional
- Cloud sync toggle
- Markdown support
- Password protection for notes
- Basic sharing (view/edit permissions)
- Auto-save timing

### Medium-Priority Optional
- 2FA
- Selective sync
- Encryption password management
- Collapsible sections
- @mentions + notifications

### Lower-Priority (Nice-to-Have)
- Custom keyboard shortcuts
- Color themes
- Advanced permission hierarchy
- OCR/text recognition
- Revision history

### Consider Deferring v1
- SSO/OAuth
- User groups
- Group-based permissions
- Audit trails
- Advanced analytics

---

## Sources & References

- Notion Account Settings: https://www.notion.com/help/account-settings
- Apple Notes Support: https://support.apple.com/guide/notes/
- Evernote Preferences: https://help.evernote.com/hc/
- Microsoft OneNote: https://support.microsoft.com/office/onenote/
- Obsidian Documentation: https://help.obsidian.md/
- Bear App: https://bear.app/faq/
- Standard Notes: https://standardnotes.com/help/
- Slite Features: https://slite.com/features
- Confluence Documentation: https://support.atlassian.com/confluence-cloud/
- Drafts: https://docs.getdrafts.com/
- MarkEdit: https://github.com/MarkEdit-app/MarkEdit/wiki/

---

**Last Updated:** 2026-02-08
**Research Scope:** 8 major notes applications (Notion, Apple Notes, Evernote, OneNote, Obsidian, Bear, Standard Notes, Drafts, MarkEdit, Slite, Confluence, Google Keep)
