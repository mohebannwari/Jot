# Smart Code Paste Detection — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When code is pasted, show a popup offering "Code Block (Language)" vs "Plain Text", cloning the URL paste popup pattern.

**Architecture:** Notification-driven. `InlineNSTextView.paste()` detects code, posts `.codePasteDetected`. SwiftUI `TodoRichTextEditor` displays popup. User choice fires back a notification handled by the Coordinator.

**Tech Stack:** AppKit (NSTextView, NSPasteboard), SwiftUI (popup view), NotificationCenter

**Spec:** `docs/superpowers/specs/2026-03-13-smart-code-paste-design.md`

---

## File Map

| File | Changes |
|------|---------|
| `Jot/Views/Components/TodoEditorRepresentable.swift` | Detection logic, notification constants, paste() branch, keyDown() handling, Coordinator observers, replacement methods, static flag |
| `Jot/Views/Components/TodoRichTextEditor.swift` | @State properties, .onReceive handler, CodePasteOptionMenu view, overlay rendering, clamping function |

---

## Chunk 1: TodoEditorRepresentable — Detection + Notifications + Paste Branch

### Task 1: Add Notification Constants

**Modify:** `TodoEditorRepresentable.swift:7349-7356` (after URL paste notification constants)

- [ ] **Step 1:** Add 7 new notification constants after the URL paste set:

```swift
    // Code paste option menu notifications
    static let codePasteDetected = Notification.Name("CodePasteDetected")
    static let codePasteSelectCodeBlock = Notification.Name("CodePasteSelectCodeBlock")
    static let codePasteSelectPlainText = Notification.Name("CodePasteSelectPlainText")
    static let codePasteDismiss = Notification.Name("CodePasteDismiss")
    static let codePasteNavigateUp = Notification.Name("CodePasteNavigateUp")
    static let codePasteNavigateDown = Notification.Name("CodePasteNavigateDown")
    static let codePasteSelectFocused = Notification.Name("CodePasteSelectFocused")
```

### Task 2: Add Static Flag

**Modify:** `TodoEditorRepresentable.swift:6356` (after `isURLPasteMenuShowing`)

- [ ] **Step 1:** Add the static flag:

```swift
    static var isCodePasteMenuShowing = false
```

### Task 3: Add `isLikelyCode()` and `detectCodeLanguage()` Static Methods

**Modify:** `TodoEditorRepresentable.swift` — after `isLikelyURL()` (line ~6430)

- [ ] **Step 1:** Add the two detection methods:

```swift
    /// Detect if pasted text is likely source code.
    /// Returns (isCode, detectedLanguage) where language is from CodeBlockData.supportedLanguages.
    private static func isLikelyCode(_ text: String) -> (isCode: Bool, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "plaintext") }

        let lines = trimmed.components(separatedBy: .newlines)
        let isMultiline = lines.count > 1

        // Strong signals — any one is sufficient for multi-line, required for single-line
        let strongPatterns: [String] = [
            #"^import\s+"#, #"^from\s+\S+\s+import"#,
            #"^func\s+"#, #"^def\s+"#, #"^class\s+"#, #"^struct\s+"#,
            #"^enum\s+"#, #"^#include\s+"#, #"^package\s+"#,
            #"^use\s+"#, #"^module\s+"#,
            #"=>\s*\{"#, #"->\s*\{"#,
        ]
        let lineEndPatterns: [String] = [
            #"\{\s*$"#, #"\};\s*$"#,
        ]

        var strongCount = 0
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            for pattern in strongPatterns {
                if t.range(of: pattern, options: .regularExpression) != nil {
                    strongCount += 1
                    break
                }
            }
            for pattern in lineEndPatterns {
                if t.range(of: pattern, options: .regularExpression) != nil {
                    strongCount += 1
                    break
                }
            }
        }

        // Medium signals — need 2+ to trigger
        var mediumCount = 0
        let fullText = trimmed

        if fullText.contains("{") && fullText.contains("}") { mediumCount += 1 }
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix(";") }) { mediumCount += 1 }
        if fullText.contains("->") { mediumCount += 1 }
        if lines.contains(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("//") || t.hasPrefix("#") && !t.hasPrefix("# ") && !t.hasPrefix("## ")
        }) { mediumCount += 1 }
        if fullText.range(of: #"(let|var|const|val)\s+\w+\s*="#, options: .regularExpression) != nil { mediumCount += 1 }
        // Indentation: 2+ leading spaces on 50%+ of non-empty lines
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if nonEmptyLines.count > 1 {
            let indentedCount = nonEmptyLines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
            if Double(indentedCount) / Double(nonEmptyLines.count) >= 0.5 { mediumCount += 1 }
        }
        if fullText.range(of: #"\w+\("#, options: .regularExpression) != nil { mediumCount += 1 }

        // Negative signals — veto for prose
        var negativeCount = 0
        for line in lines {
            let words = line.split(separator: " ")
            let hasOperators = line.contains("{") || line.contains("}") || line.contains(";")
                || line.contains("=") || line.contains("(") || line.contains("->")
            if words.count >= 5 && !hasOperators {
                negativeCount += 1
            }
        }
        if lines.contains(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }) { negativeCount += 1 }
        // Very short with no strong signals
        if trimmed.count < 8 && strongCount == 0 { return (false, "plaintext") }

        // Scoring
        let isCode: Bool
        if isMultiline {
            isCode = strongCount > 0 || (mediumCount >= 2 && negativeCount < nonEmptyLines.count / 2)
        } else {
            // Single line requires a strong signal
            isCode = strongCount > 0
        }

        if !isCode { return (false, "plaintext") }

        let language = detectCodeLanguage(trimmed)
        return (true, language)
    }

    /// Detect programming language from keyword clusters.
    private static func detectCodeLanguage(_ text: String) -> String {
        struct LangScore {
            let language: String
            let exclusiveKeywords: [String]
            let keywords: [String]
        }

        let languages: [LangScore] = [
            LangScore(language: "swift", exclusiveKeywords: ["guard ", "@State", "@Published", "import SwiftUI", "import UIKit"], keywords: ["func ", "let ", "var "]),
            LangScore(language: "go", exclusiveKeywords: [":=", "fmt.", "go func", "package main"], keywords: ["func ", "package "]),
            LangScore(language: "python", exclusiveKeywords: ["elif ", "__init__", "self."], keywords: ["def ", "import "]),
            LangScore(language: "javascript", exclusiveKeywords: ["===", "console.log", "require("], keywords: ["function ", "const ", "=> "]),
            LangScore(language: "typescript", exclusiveKeywords: [": string", ": number", ": boolean", "interface "], keywords: ["function ", "const ", "=> "]),
            LangScore(language: "rust", exclusiveKeywords: ["fn ", "mut ", "impl ", "pub fn"], keywords: ["::"]),
            LangScore(language: "java", exclusiveKeywords: ["public static void", "System.out", "@Override"], keywords: ["class ", "import "]),
            LangScore(language: "cpp", exclusiveKeywords: ["#include", "std::", "nullptr", "int main"], keywords: ["::", "cout"]),
            LangScore(language: "sql", exclusiveKeywords: ["SELECT ", "INSERT INTO", "CREATE TABLE"], keywords: ["FROM ", "WHERE ", "JOIN "]),
            LangScore(language: "html", exclusiveKeywords: ["<div", "<span", "<html", "className="], keywords: ["</"]),
            LangScore(language: "css", exclusiveKeywords: ["font-size:", "margin:", "padding:", "display:"], keywords: ["{", "}"]),
            LangScore(language: "bash", exclusiveKeywords: ["#!/bin/bash", "#!/bin/sh", "elif ", "fi\n"], keywords: ["echo ", "export "]),
            LangScore(language: "ruby", exclusiveKeywords: ["puts ", "require '", "attr_accessor"], keywords: ["def ", "end\n"]),
            LangScore(language: "yaml", exclusiveKeywords: [], keywords: [":\n", ": "]),
            LangScore(language: "json", exclusiveKeywords: [], keywords: ["\":", "{\n"]),
        ]

        var bestLang = "plaintext"
        var bestScore = 0

        for lang in languages {
            var score = 0
            for kw in lang.exclusiveKeywords {
                if text.contains(kw) { score += 3 }
            }
            for kw in lang.keywords {
                if text.contains(kw) { score += 1 }
            }
            if score > bestScore {
                bestScore = score
                bestLang = lang.language
            }
        }

        return bestScore > 0 ? bestLang : "plaintext"
    }
```

### Task 4: Add Code Detection Branch to `paste()`

**Modify:** `TodoEditorRepresentable.swift:6373-6420` — the `paste()` override

- [ ] **Step 1:** Extend `paste()` to check for code after the URL check. The full replacement:

After the existing `if isURL && !pastedText.isEmpty { ... }` block closes (line ~6419), add:

```swift
        // Code paste detection — only if URL detection didn't trigger
        if !isURL && !pastedText.isEmpty {
            // Tier 1: check pasteboard for code-specific types
            let pb = NSPasteboard.general
            let hasCodeType = pb.types?.contains(where: { type in
                let raw = type.rawValue
                return raw == "com.apple.dt.Xcode.pboard.source-code"
                    || raw == "public.source-code"
            }) ?? false

            // Tier 2: heuristic detection
            let (isCode, language) = hasCodeType
                ? (true, Self.detectCodeLanguage(pastedText))
                : Self.isLikelyCode(pastedText)

            if isCode {
                let afterLocation = selectedRange().location
                let pastedLength = afterLocation - beforeLocation
                if pastedLength > 0 {
                    let pastedRange = NSRange(location: beforeLocation, length: pastedLength)

                    // Read back the actually-inserted text from textStorage
                    let insertedText: String
                    if let storage = textStorage,
                       pastedRange.location + pastedRange.length <= storage.length {
                        insertedText = (storage.string as NSString).substring(with: pastedRange)
                    } else {
                        insertedText = pastedText
                    }

                    // Subtle gray background highlight
                    textStorage?.addAttribute(
                        .backgroundColor,
                        value: NSColor.labelColor.withAlphaComponent(0.08),
                        range: pastedRange)

                    if let layoutManager = layoutManager, let textContainer = textContainer {
                        let glyphRange = layoutManager.glyphRange(
                            forCharacterRange: pastedRange, actualCharacterRange: nil)
                        let rect = layoutManager.boundingRect(
                            forGlyphRange: glyphRange, in: textContainer)
                        let adjustedRect = CGRect(
                            x: rect.origin.x + textContainerOrigin.x,
                            y: rect.origin.y + textContainerOrigin.y,
                            width: rect.width,
                            height: rect.height
                        )

                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .codePasteDetected,
                                object: [
                                    "code": insertedText,
                                    "range": NSValue(range: pastedRange),
                                    "rect": NSValue(rect: adjustedRect),
                                    "language": language,
                                ] as [String: Any]
                            )
                        }
                    }
                }
            }
        }
```

- [ ] **Step 2:** Build and verify no errors: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build`

- [ ] **Step 3:** Commit: `git commit -m "feat(paste): add code detection logic and notification constants"`

---

## Chunk 2: TodoEditorRepresentable — Keyboard Handling + Coordinator

### Task 5: Add `keyDown()` Code Paste Menu Handling

**Modify:** `TodoEditorRepresentable.swift:6714-6734` — after the URL paste menu block in keyDown()

- [ ] **Step 1:** Add code paste keyboard handling right after the URL paste block:

```swift
        // Handle code paste menu keyboard navigation
        if InlineNSTextView.isCodePasteMenuShowing {
            switch event.keyCode {
            case 126:  // Up Arrow
                NotificationCenter.default.post(name: .codePasteNavigateUp, object: nil, userInfo: eidInfo)
                return
            case 125:  // Down Arrow
                NotificationCenter.default.post(name: .codePasteNavigateDown, object: nil, userInfo: eidInfo)
                return
            case 36, 76:  // Return/Enter
                NotificationCenter.default.post(name: .codePasteSelectFocused, object: nil, userInfo: eidInfo)
                return
            case 53:  // Escape
                NotificationCenter.default.post(name: .codePasteDismiss, object: nil)
                return
            default:
                NotificationCenter.default.post(name: .codePasteDismiss, object: nil)
                super.keyDown(with: event)
                return
            }
        }
```

### Task 6: Add `textDidChange` Dismiss

**Modify:** `TodoEditorRepresentable.swift:3249` — after the URL paste dismiss line

- [ ] **Step 1:** Add code paste dismiss:

```swift
            NotificationCenter.default.post(name: .codePasteDismiss, object: nil)
```

### Task 7: Add Coordinator Notification Observers

**Modify:** `TodoEditorRepresentable.swift:2038-2069` — after the URL paste observers, before the `observers = [...]` array

- [ ] **Step 1:** Add 3 observer registrations (select code block, plain text, dismiss):

```swift
            let codePasteSelectCodeBlock = NotificationCenter.default.addObserver(
                forName: .codePasteSelectCodeBlock, object: nil, queue: .main
            ) { [weak self] notification in
                guard let info = notification.object as? [String: Any],
                      let code = info["code"] as? String,
                      let rangeValue = info["range"] as? NSValue,
                      let language = info["language"] as? String else { return }
                let range = rangeValue.rangeValue
                Task { @MainActor [weak self] in
                    self?.replaceCodePasteWithCodeBlock(code: code, range: range, language: language)
                }
            }

            let codePasteSelectPlainText = NotificationCenter.default.addObserver(
                forName: .codePasteSelectPlainText, object: nil, queue: .main
            ) { [weak self] notification in
                guard let info = notification.object as? [String: Any],
                      let rangeValue = info["range"] as? NSValue else { return }
                let range = rangeValue.rangeValue
                Task { @MainActor [weak self] in
                    self?.clearCodePasteHighlight(range: range)
                }
            }

            let codePasteDismissObserver = NotificationCenter.default.addObserver(
                forName: .codePasteDismiss, object: nil, queue: .main
            ) { [weak self] notification in
                let range = (notification.object as? [String: Any])?["range"] as? NSValue
                Task { @MainActor [weak self] in
                    if let r = range?.rangeValue { self?.clearCodePasteHighlight(range: r) }
                }
            }
```

- [ ] **Step 2:** Add the 3 new observer tokens to the `observers` array:

```swift
                codePasteSelectCodeBlock, codePasteSelectPlainText, codePasteDismissObserver,
```

### Task 8: Add Replacement and Highlight Methods

**Modify:** `TodoEditorRepresentable.swift` — after `clearURLPasteHighlight()` (line ~4020)

- [ ] **Step 1:** Add the two new methods:

```swift
        private func replaceCodePasteWithCodeBlock(code: String, range: NSRange, language: String) {
            guard let textView = textView, let textStorage = textView.textStorage else { return }

            // Clear highlight
            if range.location + range.length <= textStorage.length {
                textStorage.removeAttribute(.backgroundColor, range: range)
            }

            // Select the pasted text range and replace with code block
            textView.setSelectedRange(range)
            let data = CodeBlockData(language: language, code: code)
            let attachment = makeCodeBlockAttachment(codeBlockData: data)

            let baseAttrs = Self.baseTypingAttributes(for: currentColorScheme)
            let composed = NSMutableAttributedString()

            // Ensure newline before
            let nsString = textStorage.string as NSString
            if range.location > 0 {
                let prevChar = nsString.character(at: range.location - 1)
                if let scalar = Unicode.Scalar(prevChar),
                   !CharacterSet.newlines.contains(scalar) {
                    composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                }
            }
            composed.append(attachment)
            composed.append(NSAttributedString(string: "\n", attributes: baseAttrs))

            replaceSelection(with: composed)
            syncText()
        }

        private func clearCodePasteHighlight(range: NSRange) {
            guard let textStorage = textView?.textStorage else { return }
            guard range.location + range.length <= textStorage.length else { return }
            textStorage.removeAttribute(.backgroundColor, range: range)
        }
```

- [ ] **Step 2:** Build and verify: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build`

- [ ] **Step 3:** Commit: `git commit -m "feat(paste): add code paste keyboard handling, observers, and replacement logic"`

---

## Chunk 3: TodoRichTextEditor — Popup View + Overlay

### Task 9: Add @State Properties

**Modify:** `TodoRichTextEditor.swift:70-74` — after URL paste state properties

- [ ] **Step 1:** Add code paste state:

```swift
    // Code paste option menu state
    @State private var showCodePasteMenu = false
    @State private var codePasteMenuPosition: CGPoint = .zero
    @State private var codePasteCode: String = ""
    @State private var codePasteRange: NSRange = NSRange(location: 0, length: 0)
    @State private var codePasteLanguage: String = "plaintext"
```

### Task 10: Add `.onReceive` Handlers

**Modify:** `TodoRichTextEditor.swift` — after the `.onReceive(.urlPasteDismiss)` handler (line ~410)

- [ ] **Step 1:** Add code paste receive handlers:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .codePasteDetected)) { notification in
            guard let info = notification.object as? [String: Any],
                  let code = info["code"] as? String,
                  let rangeValue = info["range"] as? NSValue,
                  let rectValue = info["rect"] as? NSValue,
                  let language = info["language"] as? String else { return }

            let range = rangeValue.rangeValue
            let rect = rectValue.rectValue

            codePasteCode = code
            codePasteRange = range
            codePasteLanguage = language

            let menuTotalWidth: CGFloat = 160 + CommandMenuLayout.outerPadding * 2
            let menuX = rect.midX - menuTotalWidth / 2
            let menuY = rect.maxY + 8

            codePasteMenuPosition = CGPoint(x: max(0, menuX), y: menuY)

            withAnimation(.smooth(duration: 0.2)) {
                showCodePasteMenu = true
            }
            InlineNSTextView.isCodePasteMenuShowing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .codePasteDismiss)) { _ in
            if showCodePasteMenu {
                withAnimation(.smooth(duration: 0.15)) { showCodePasteMenu = false }
                InlineNSTextView.isCodePasteMenuShowing = false
            }
        }
```

### Task 11: Add `clampedCodePasteMenuPosition()` and Overlay

**Modify:** `TodoRichTextEditor.swift` — after `clampedURLPasteMenuPosition()` (line ~488)

- [ ] **Step 1:** Add clamping function:

```swift
    private func clampedCodePasteMenuPosition(for containerSize: CGSize) -> CGPoint {
        let menuWidth: CGFloat = 160 + CommandMenuLayout.outerPadding * 2
        let menuHeight: CGFloat = 68 + CommandMenuLayout.outerPadding * 2
        let maxX = max(0, containerSize.width - menuWidth)
        let maxY = max(0, containerSize.height - menuHeight)
        let clampedX = min(max(codePasteMenuPosition.x, 0), maxX)
        let clampedY = min(max(codePasteMenuPosition.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }
```

- [ ] **Step 2:** Add overlay right after the URL paste menu overlay (line ~212):

```swift
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if showCodePasteMenu {
                    CodePasteOptionMenu(
                        language: codePasteLanguage,
                        onCodeBlock: {
                            withAnimation(.smooth(duration: 0.15)) { showCodePasteMenu = false }
                            InlineNSTextView.isCodePasteMenuShowing = false
                            NotificationCenter.default.post(
                                name: .codePasteSelectCodeBlock,
                                object: [
                                    "code": codePasteCode,
                                    "range": NSValue(range: codePasteRange),
                                    "language": codePasteLanguage,
                                ] as [String: Any]
                            )
                        },
                        onPlainText: {
                            withAnimation(.smooth(duration: 0.15)) { showCodePasteMenu = false }
                            InlineNSTextView.isCodePasteMenuShowing = false
                            NotificationCenter.default.post(
                                name: .codePasteSelectPlainText,
                                object: [
                                    "range": NSValue(range: codePasteRange),
                                ] as [String: Any]
                            )
                        }
                    )
                    .offset(
                        x: clampedCodePasteMenuPosition(for: geometry.size).x,
                        y: clampedCodePasteMenuPosition(for: geometry.size).y
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                        )
                    )
                    .zIndex(999)
                }
            }
        }
```

### Task 12: Add `CodePasteOptionMenu` View

**Modify:** `TodoRichTextEditor.swift` — after `URLPasteOptionMenu` struct (line ~647)

- [ ] **Step 1:** Add the new view struct:

```swift
struct CodePasteOptionMenu: View {
    let language: String
    let onCodeBlock: () -> Void
    let onPlainText: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var focusedOption: Int = 0
    @State private var hoveredOption: Int?

    private let optionCount = 2

    private var activeOption: Int {
        hoveredOption ?? focusedOption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            optionRow(
                iconName: "IconCode",
                label: "Code Block (\(CodeBlockData.displayName(for: language)))",
                index: 0,
                action: onCodeBlock
            )
            optionRow(
                iconName: "IconText",
                label: "Plain Text",
                index: 1,
                action: onPlainText
            )
        }
        .padding(CommandMenuLayout.outerPadding)
        .frame(width: 220)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .onReceive(NotificationCenter.default.publisher(for: .codePasteNavigateUp)) { _ in
            withAnimation(.smooth(duration: 0.1)) {
                hoveredOption = nil
                focusedOption = max(focusedOption - 1, 0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .codePasteNavigateDown)) { _ in
            withAnimation(.smooth(duration: 0.1)) {
                hoveredOption = nil
                focusedOption = min(focusedOption + 1, optionCount - 1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .codePasteSelectFocused)) { _ in
            if activeOption == 0 {
                onCodeBlock()
            } else {
                onPlainText()
            }
        }
    }

    private func optionRow(
        iconName: String,
        label: String,
        index: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(iconColor(for: index))

                Text(label)
                    .font(FontManager.heading(size: 13, weight: .regular))
                    .foregroundStyle(textColor(for: index))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                activeOption == index
                    ? Capsule().fill(Color("HoverBackgroundColor"))
                    : nil
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(.smooth(duration: 0.12)) {
                hoveredOption = isHovered ? index : (hoveredOption == index ? nil : hoveredOption)
            }
        }
    }

    private func iconColor(for index: Int) -> Color {
        activeOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("IconSecondaryColor")
    }

    private func textColor(for index: Int) -> Color {
        activeOption == index
            ? (colorScheme == .dark ? .white : Color("PrimaryTextColor"))
            : Color("PrimaryTextColor")
    }
}
```

**Note on icons:** The view references `"IconCode"` and `"IconText"` as image names. These must exist in Assets.xcassets. If they don't exist, check available icon assets with `ls Jot/Ressources/Assets.xcassets/` and use the closest match (e.g., `"IconCodeBlock"` or the code block icon used in the toolbar). The URL menu uses `"insert link"` and `"IconGlobe"` — find the code block equivalent.

**Note on width:** CodePasteOptionMenu uses `width: 220` (not 160 like URL) because "Code Block (JavaScript)" is longer than "Paste as URL". Update `clampedCodePasteMenuPosition` menuWidth to match: `220 + CommandMenuLayout.outerPadding * 2`.

- [ ] **Step 2:** Build and verify: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build`

- [ ] **Step 3:** Commit: `git commit -m "feat(paste): add CodePasteOptionMenu view and overlay rendering"`

---

## Chunk 4: Verification

### Task 13: Full Build + Manual Test

- [ ] **Step 1:** Full build: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build`
- [ ] **Step 2:** Relaunch app
- [ ] **Step 3:** Test: copy a Swift code snippet, paste into a note — popup should appear with "Code Block (Swift)" and "Plain Text"
- [ ] **Step 4:** Test: choose "Code Block" — code should be wrapped in a code block attachment
- [ ] **Step 5:** Test: paste again, choose "Plain Text" — text should remain as-is
- [ ] **Step 6:** Test: paste again, press Escape — popup should dismiss, text stays
- [ ] **Step 7:** Test: paste a plain English sentence — popup should NOT appear
- [ ] **Step 8:** Test: paste a URL — URL popup should appear (not code popup)
- [ ] **Step 9:** Final commit: `git commit -m "feat: smart code paste detection with popup"`
