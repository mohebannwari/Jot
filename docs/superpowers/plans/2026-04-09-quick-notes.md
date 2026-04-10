# Quick Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a system-wide hotkey that spawns a floating plain-text panel from any app, saving into an auto-created "Quick Notes" inbox folder. User-configurable chord via Settings. Default chord `⌃⌥⌘N`.

**Architecture:** Carbon `RegisterEventHotKey` (works under sandbox, no entitlements) + `NSPanel` subclass with `.nonactivatingPanel` style (doesn't steal focus from frontmost app) + SwiftUI plain-text editor hosted via `NSHostingView` + `QuickNoteService` that resolves or creates a "Quick Notes" folder and calls `SimpleSwiftDataManager.addNote`.

**Tech Stack:** SwiftUI, AppKit (`NSPanel`, `NSHostingView`, `NSEvent`, `NSWorkspace`), `Carbon.HIToolbox` (`RegisterEventHotKey`, virtual key codes), SwiftData via existing `SimpleSwiftDataManager`, XCTest.

**Spec:** `docs/superpowers/specs/2026-04-09-quick-notes-design.md`

**Xcode project note:** The project uses `PBXFileSystemSynchronizedRootGroup` — new `.swift` files dropped into any `Jot/` or `JotTests/` subdirectory are automatically included in their respective targets. No `project.pbxproj` edits required.

**Build commands:**

```bash
# Full build
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates

# Run all tests
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test

# Run a single test suite
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/QuickNoteTests test -allowProvisioningUpdates
```

**Critical rule:** Do NOT relaunch the app after building. The user handles relaunching via the in-app updates panel.

---

## File structure

### New files (6)

| File                                            | Responsibility                                         | Lines (approx) |
| ----------------------------------------------- | ------------------------------------------------------ | -------------- |
| `Jot/Utils/QuickNoteHotKey.swift`               | Value type + Cocoa↔Carbon translation + display string | ~120           |
| `Jot/Utils/GlobalHotKeyManager.swift`           | Carbon `RegisterEventHotKey` wrapper                   | ~150           |
| `Jot/Utils/QuickNoteService.swift`              | Folder resolution + save path                          | ~90            |
| `Jot/Views/Screens/QuickNotePanel.swift`        | NSPanel subclass + WindowController + SwiftUI view     | ~220           |
| `Jot/Views/Components/HotKeyRecorderView.swift` | Settings chord recorder                                | ~130           |
| `JotTests/QuickNoteTests.swift`                 | Unit tests                                             | ~200           |

### Modified files (3)

| File                                          | Change                                                              |
| --------------------------------------------- | ------------------------------------------------------------------- |
| `Jot/Utils/ThemeManager.swift`                | Add `quickNoteHotKey` and `quickNotesFolderID` persisted properties |
| `Jot/Views/Components/FloatingSettings.swift` | Add Quick Notes row to the General tab                              |
| `Jot/App/JotApp.swift`                        | Install hotkey and wire callback at launch                          |

### Runtime ownership tree

```
JotApp (@main)
├── GlobalHotKeyManager (singleton) ── installed at launch
│   └── on fire → QuickNoteWindowController.shared.showPanel()
├── QuickNoteWindowController (singleton, lazy)
│   └── owns QuickNotePanelWindow (NSPanel subclass)
│       └── contentView = NSHostingView<QuickNotePanelView>
└── SimpleSwiftDataManager.shared (existing)
```

---

## Task 1: `QuickNoteHotKey` value type + modifier translation

**Files:**

- Create: `Jot/Utils/QuickNoteHotKey.swift`
- Create: `JotTests/QuickNoteTests.swift`

### - [ ] Step 1.1: Write the failing tests

Create `JotTests/QuickNoteTests.swift`:

```swift
import XCTest
@testable import Jot
import AppKit
import Carbon.HIToolbox

final class QuickNoteHotKeyTests: XCTestCase {

    // MARK: Codable

    func testCodableRoundTrip() throws {
        let original = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_N),
                                       modifiers: UInt32(cmdKey | optionKey | controlKey))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuickNoteHotKey.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: Default

    func testDefaultIsControlOptionCommandN() {
        let d = QuickNoteHotKey.default
        XCTAssertEqual(d.keyCode, UInt32(kVK_ANSI_N))
        XCTAssertEqual(d.modifiers, UInt32(cmdKey | optionKey | controlKey))
    }

    // MARK: Cocoa → Carbon modifier translation

    func testCocoaToCarbonAllSixteenCombinations() {
        let cases: [(NSEvent.ModifierFlags, UInt32)] = [
            ([],                                                            0),
            ([.command],                                                    UInt32(cmdKey)),
            ([.option],                                                     UInt32(optionKey)),
            ([.shift],                                                      UInt32(shiftKey)),
            ([.control],                                                    UInt32(controlKey)),
            ([.command, .option],                                           UInt32(cmdKey | optionKey)),
            ([.command, .shift],                                            UInt32(cmdKey | shiftKey)),
            ([.command, .control],                                          UInt32(cmdKey | controlKey)),
            ([.option, .shift],                                             UInt32(optionKey | shiftKey)),
            ([.option, .control],                                           UInt32(optionKey | controlKey)),
            ([.shift, .control],                                            UInt32(shiftKey | controlKey)),
            ([.command, .option, .shift],                                   UInt32(cmdKey | optionKey | shiftKey)),
            ([.command, .option, .control],                                 UInt32(cmdKey | optionKey | controlKey)),
            ([.command, .shift, .control],                                  UInt32(cmdKey | shiftKey | controlKey)),
            ([.option, .shift, .control],                                   UInt32(optionKey | shiftKey | controlKey)),
            ([.command, .option, .shift, .control],                         UInt32(cmdKey | optionKey | shiftKey | controlKey)),
        ]
        for (cocoa, expected) in cases {
            XCTAssertEqual(QuickNoteHotKey.carbonModifiers(from: cocoa), expected,
                           "Failed for cocoa flags: \(cocoa.rawValue)")
        }
    }

    // MARK: Display string

    func testDisplayStringOrdering() {
        // ⌃⌥⇧⌘N — order must be Control, Option, Shift, Command, then key
        let hk = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_N),
                                 modifiers: UInt32(cmdKey | optionKey | shiftKey | controlKey))
        XCTAssertEqual(hk.displayString, "⌃⌥⇧⌘N")
    }

    func testDisplayStringDefault() {
        XCTAssertEqual(QuickNoteHotKey.default.displayString, "⌃⌥⌘N")
    }

    func testDisplayStringSingleModifier() {
        let hk = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey))
        XCTAssertEqual(hk.displayString, "⌘S")
    }

    func testDisplayStringFunctionKey() {
        let hk = QuickNoteHotKey(keyCode: UInt32(kVK_F5), modifiers: 0)
        XCTAssertEqual(hk.displayString, "F5")
    }

    func testDisplayStringUnknownKeyFallback() {
        // A virtual key code we don't map → "Key 0xFF"
        let hk = QuickNoteHotKey(keyCode: 0xFF, modifiers: UInt32(cmdKey))
        XCTAssertEqual(hk.displayString, "⌘Key 0xFF")
    }

    // MARK: hasAnyModifier

    func testHasAnyModifierTrue() {
        let hk = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey))
        XCTAssertTrue(hk.hasAnyModifier)
    }

    func testHasAnyModifierFalse() {
        let hk = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: 0)
        XCTAssertFalse(hk.hasAnyModifier)
    }
}
```

### - [ ] Step 1.2: Run tests to verify they fail

```bash
cd /Users/mohebanwari/development/Jot
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/QuickNoteHotKeyTests test -allowProvisioningUpdates 2>&1 | tail -30
```

Expected: Build FAIL with `cannot find 'QuickNoteHotKey' in scope`.

### - [ ] Step 1.3: Implement `QuickNoteHotKey`

Create `Jot/Utils/QuickNoteHotKey.swift`:

```swift
//
//  QuickNoteHotKey.swift
//  Jot
//
//  Value type representing a global keyboard shortcut for Quick Notes.
//  Stores a Carbon virtual key code + Carbon modifier bitmask (not Cocoa).
//  Codable so it can persist to UserDefaults as JSON.
//

import AppKit
import Carbon.HIToolbox

struct QuickNoteHotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon bitmask: cmdKey | optionKey | shiftKey | controlKey

    /// The factory default: ⌃⌥⌘N (Control + Option + Command + N).
    static let `default` = QuickNoteHotKey(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(cmdKey | optionKey | controlKey)
    )

    /// True if the hotkey has at least one modifier (required for valid global hotkeys —
    /// pure letter keys would block normal typing system-wide).
    var hasAnyModifier: Bool {
        modifiers & UInt32(cmdKey | optionKey | shiftKey | controlKey) != 0
    }

    /// Human-readable chord display, e.g. "⌃⌥⌘N". Order matches Apple conventions.
    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0  { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0   { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0     { result += "⌘" }
        result += Self.keyCodeDisplayString(for: keyCode)
        return result
    }

    // MARK: - Cocoa ↔ Carbon translation

    /// Convert a Cocoa NSEvent.ModifierFlags bitmask into a Carbon bitmask.
    static func carbonModifiers(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoa.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoa.contains(.option)  { carbon |= UInt32(optionKey) }
        if cocoa.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if cocoa.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    // MARK: - Key code → display

    private static let keyCodeGlyphs: [UInt32: String] = [
        // Letters
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        // Digits
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        // Function keys
        UInt32(kVK_F1): "F1",   UInt32(kVK_F2): "F2",   UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",   UInt32(kVK_F5): "F5",   UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",   UInt32(kVK_F8): "F8",   UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        // Specials
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
    ]

    private static func keyCodeDisplayString(for keyCode: UInt32) -> String {
        keyCodeGlyphs[keyCode] ?? String(format: "Key 0x%02X", keyCode)
    }
}
```

### - [ ] Step 1.4: Run tests to verify they pass

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/QuickNoteHotKeyTests test -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: `TEST SUCCEEDED`, all 11 tests pass.

### - [ ] Step 1.5: Commit

```bash
cd /Users/mohebanwari/development/Jot
git add Jot/Utils/QuickNoteHotKey.swift JotTests/QuickNoteTests.swift
git commit -m "feat: add QuickNoteHotKey value type with Cocoa↔Carbon translation

First piece of the Quick Notes feature. Pure data + static helpers,
fully unit-tested, zero runtime dependencies.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `ThemeManager` persistence for `quickNoteHotKey` and `quickNotesFolderID`

**Files:**

- Modify: `Jot/Utils/ThemeManager.swift`
- Modify: `JotTests/QuickNoteTests.swift`

### - [ ] Step 2.1: Write failing tests

Append to `JotTests/QuickNoteTests.swift` (after the closing brace of `QuickNoteHotKeyTests`):

```swift
final class ThemeManagerQuickNoteTests: XCTestCase {

    func testDefaultHotKeyIsDefaultWhenNothingStored() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        XCTAssertEqual(manager.quickNoteHotKey, QuickNoteHotKey.default)
    }

    func testSettingHotKeyPersistsToDefaults() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        let newHotKey = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey))
        manager.quickNoteHotKey = newHotKey

        let raw = try XCTUnwrap(defaults.data(forKey: ThemeManager.quickNoteHotKeyKey))
        let decoded = try JSONDecoder().decode(QuickNoteHotKey.self, from: raw)
        XCTAssertEqual(decoded, newHotKey)
    }

    func testClearingHotKeyRemovesFromDefaults() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        manager.quickNoteHotKey = QuickNoteHotKey(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey))
        manager.quickNoteHotKey = nil

        XCTAssertNil(defaults.data(forKey: ThemeManager.quickNoteHotKeyKey))
        XCTAssertNil(manager.quickNoteHotKey)
    }

    func testQuickNotesFolderIDPersistence() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(userDefaults: defaults)
        XCTAssertNil(manager.quickNotesFolderID)

        let id = UUID()
        manager.quickNotesFolderID = id
        XCTAssertEqual(defaults.string(forKey: ThemeManager.quickNotesFolderIDKey), id.uuidString)

        // Re-instantiate — should read back
        let manager2 = ThemeManager(userDefaults: defaults)
        XCTAssertEqual(manager2.quickNotesFolderID, id)
    }

    // MARK: - Helpers

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "QuickNoteThemeManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
```

Add the required imports at the top of the test file if missing:

```swift
import Carbon.HIToolbox
```

### - [ ] Step 2.2: Run tests to verify they fail

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/ThemeManagerQuickNoteTests test -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: Build FAIL with `value of type 'ThemeManager' has no member 'quickNoteHotKey'` and similar for `quickNotesFolderID`.

### - [ ] Step 2.3: Add the two properties to `ThemeManager`

In `Jot/Utils/ThemeManager.swift`:

**Add** the two key constants right after line 124 (`versionRetentionDaysKey`):

```swift
    // Quick Notes feature keys
    static let quickNoteHotKeyKey = "QuickNoteHotKey"
    static let quickNotesFolderIDKey = "QuickNotesFolderID"
```

**Add** the two published properties just before the `init` (insert right after the `versionRetentionDays` property, around line 247):

```swift
    @Published var quickNoteHotKey: QuickNoteHotKey? {
        didSet {
            if let hk = quickNoteHotKey,
               let data = try? JSONEncoder().encode(hk) {
                userDefaults.set(data, forKey: Self.quickNoteHotKeyKey)
            } else {
                userDefaults.removeObject(forKey: Self.quickNoteHotKeyKey)
            }
        }
    }

    @Published var quickNotesFolderID: UUID? {
        didSet {
            if let id = quickNotesFolderID {
                userDefaults.set(id.uuidString, forKey: Self.quickNotesFolderIDKey)
            } else {
                userDefaults.removeObject(forKey: Self.quickNotesFolderIDKey)
            }
        }
    }
```

**Add** initialization at the end of `init(userDefaults:)` — right before `applyAppKitAppearance(self.currentTheme)` (around line 300):

```swift
        // Quick Notes: hotkey defaults to ⌃⌥⌘N on first launch, folder is nil until first save
        if let data = userDefaults.data(forKey: Self.quickNoteHotKeyKey),
           let decoded = try? JSONDecoder().decode(QuickNoteHotKey.self, from: data) {
            self.quickNoteHotKey = decoded
        } else {
            self.quickNoteHotKey = .default
        }

        if let idString = userDefaults.string(forKey: Self.quickNotesFolderIDKey),
           let id = UUID(uuidString: idString) {
            self.quickNotesFolderID = id
        } else {
            self.quickNotesFolderID = nil
        }
```

### - [ ] Step 2.4: Run tests to verify they pass

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/ThemeManagerQuickNoteTests test -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: `TEST SUCCEEDED`, 4 tests pass.

### - [ ] Step 2.5: Full build to catch any downstream breakage

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

### - [ ] Step 2.6: Commit

```bash
git add Jot/Utils/ThemeManager.swift JotTests/QuickNoteTests.swift
git commit -m "feat: add quickNoteHotKey and quickNotesFolderID to ThemeManager

Persists the user's chosen hotkey (JSON-encoded) and the inbox folder ID
across launches. Defaults to ⌃⌥⌘N on first run.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `GlobalHotKeyManager` — Carbon wrapper

**Files:**

- Create: `Jot/Utils/GlobalHotKeyManager.swift`

No unit tests for this task — Carbon hotkey firing requires the WindowServer and can't be exercised from XCTest. Structural correctness is verified by (a) build success, (b) the manual smoke test in Task 12.

### - [ ] Step 3.1: Implement the manager

Create `Jot/Utils/GlobalHotKeyManager.swift`:

```swift
//
//  GlobalHotKeyManager.swift
//  Jot
//
//  Thin Swift wrapper around Carbon's RegisterEventHotKey. One hotkey at a time.
//  Works under the macOS sandbox without any entitlement, because Carbon hotkey
//  registration goes through the WindowServer's registered-hotkey table — not
//  accessibility APIs. This is the same approach Alfred, Raycast, Things, etc. use.
//

import AppKit
import Carbon.HIToolbox
import os

final class GlobalHotKeyManager {

    static let shared = GlobalHotKeyManager()

    /// Called on the main queue when the registered hotkey fires.
    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = OSType(0x4A4F5451) // "JOTQ" — must be a unique FourCharCode
    private let hotKeyID: UInt32 = 1
    private let logger = Logger(subsystem: "com.jot", category: "GlobalHotKeyManager")

    private init() {
        installEventHandler()
    }

    deinit {
        uninstall()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Public API

    /// Install a hotkey. If one is already installed, it is replaced.
    /// - Returns: true if registration succeeded.
    @discardableResult
    func install(_ hotKey: QuickNoteHotKey) -> Bool {
        uninstall()

        guard hotKey.hasAnyModifier else {
            logger.warning("Refusing to install hotkey with no modifiers (keyCode: \(hotKey.keyCode))")
            return false
        }

        var eventHotKeyID = EventHotKeyID(signature: signature, id: hotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            eventHotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr, let ref = ref {
            hotKeyRef = ref
            logger.info("Installed global hotkey: \(hotKey.displayString)")
            return true
        } else {
            logger.error("Failed to install global hotkey \(hotKey.displayString): OSStatus \(status)")
            return false
        }
    }

    /// Unregister the current hotkey, if any.
    func uninstall() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    /// Replace the current hotkey with a new one.
    @discardableResult
    func replace(with newHotKey: QuickNoteHotKey) -> Bool {
        install(newHotKey)
    }

    // MARK: - Carbon event handler

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef = eventRef, let userData = userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hkID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard status == noErr, hkID.signature == manager.signature, hkID.id == manager.hotKeyID else {
                return noErr
            }

            DispatchQueue.main.async {
                manager.onFire?()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )
        if status == noErr {
            eventHandlerRef = handlerRef
        } else {
            logger.error("Failed to install Carbon event handler: OSStatus \(status)")
        }
    }
}
```

### - [ ] Step 3.2: Build to verify Carbon imports resolve

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. (No tests for this file; correctness verified manually in Task 12.)

### - [ ] Step 3.3: Commit

```bash
git add Jot/Utils/GlobalHotKeyManager.swift
git commit -m "feat: add GlobalHotKeyManager (Carbon hotkey wrapper)

One-hotkey-at-a-time Carbon wrapper around RegisterEventHotKey. Fires
onFire on the main queue. Works under sandbox without any entitlement.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `QuickNoteService` — folder resolution + save

**Files:**

- Create: `Jot/Utils/QuickNoteService.swift`
- Modify: `JotTests/QuickNoteTests.swift`

### - [ ] Step 4.1: Write failing tests

Append to `JotTests/QuickNoteTests.swift`:

```swift
final class QuickNoteServiceTests: XCTestCase {

    // Helper that builds an isolated SimpleSwiftDataManager backed by an in-memory SwiftData store.
    // Reuses the same helper the existing SimpleSwiftDataManagerTests use — we mirror its setup.
    private func makeManager() throws -> SimpleSwiftDataManager {
        try SimpleSwiftDataManager(inMemory: true)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "QuickNoteServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    func testSaveWithTitleAndBodyCreatesNoteInInboxFolder() throws {
        let manager = try makeManager()
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let note = service.save(title: "Meeting prep", body: "Bring coffee")

        XCTAssertEqual(note.title, "Meeting prep")
        XCTAssertEqual(note.content, "Bring coffee")
        XCTAssertNotNil(note.folderID)
        // Folder was created and persisted
        let storedID = defaults.string(forKey: ThemeManager.quickNotesFolderIDKey)
        XCTAssertEqual(storedID, note.folderID?.uuidString)
        // Folder name is "Quick Notes"
        let folder = manager.folders.first(where: { $0.id == note.folderID })
        XCTAssertEqual(folder?.name, "Quick Notes")
    }

    func testSaveReusesExistingInboxFolder() throws {
        let manager = try makeManager()
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let first = service.save(title: "First", body: "1")
        let second = service.save(title: "Second", body: "2")

        XCTAssertEqual(first.folderID, second.folderID)
        XCTAssertEqual(manager.folders.filter { $0.name == "Quick Notes" }.count, 1)
    }

    func testSaveRecreatesFolderIfStaleIDPointsToDeletedFolder() throws {
        let manager = try makeManager()
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Plant a stale ID for a folder that doesn't exist
        let staleID = UUID()
        defaults.set(staleID.uuidString, forKey: ThemeManager.quickNotesFolderIDKey)

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let note = service.save(title: "Fresh", body: "body")

        XCTAssertNotEqual(note.folderID, staleID)
        XCTAssertNotNil(note.folderID)
    }

    func testEmptyTitleDerivesFromFirstLineOfBody() throws {
        let manager = try makeManager()
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let note = service.save(title: "   ", body: "First line\nSecond line\nThird")
        XCTAssertEqual(note.title, "First line")
    }

    func testEmptyTitleWithLongFirstLineTruncates() throws {
        let manager = try makeManager()
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let longLine = String(repeating: "a", count: 120)
        let note = service.save(title: "", body: longLine)
        XCTAssertEqual(note.title.count, 60)
        XCTAssertTrue(longLine.hasPrefix(note.title))
    }

    func testEmptyTitleAndEmptyBodyFallsBackToLiteralQuickNote() throws {
        let manager = try makeManager()
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = QuickNoteService(manager: manager, defaults: defaults)
        let note = service.save(title: "", body: "   \n  ")
        XCTAssertEqual(note.title, "Quick Note")
    }
}
```

**Before running the test, verify** that `SimpleSwiftDataManager` has an `init(inMemory:)` convenience — if it doesn't, use the same initializer pattern used by `SimpleSwiftDataManagerTests`. Check:

```bash
grep -n "init.*inMemory\|SimpleSwiftDataManager(" /Users/mohebanwari/development/Jot/JotTests/SimpleSwiftDataManagerTests.swift | head -5
```

If no `inMemory` initializer exists, replace the `makeManager()` helper body with whatever the existing test file uses. This step is critical — do not skip it. If the existing tests construct the manager differently, match their pattern exactly.

### - [ ] Step 4.2: Run tests to verify they fail

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/QuickNoteServiceTests test -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: Build FAIL with `cannot find 'QuickNoteService' in scope`.

### - [ ] Step 4.3: Implement `QuickNoteService`

Create `Jot/Utils/QuickNoteService.swift`:

```swift
//
//  QuickNoteService.swift
//  Jot
//
//  Single save path for quick-captured notes. Resolves or creates the
//  "Quick Notes" inbox folder, then delegates to SimpleSwiftDataManager.addNote.
//

import Foundation
import os

final class QuickNoteService {

    static let shared = QuickNoteService(
        manager: SimpleSwiftDataManager.shared,
        defaults: .standard
    )

    private let manager: SimpleSwiftDataManager
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.jot", category: "QuickNoteService")

    private static let inboxFolderName = "Quick Notes"
    private static let titleTruncationLimit = 60

    init(manager: SimpleSwiftDataManager, defaults: UserDefaults) {
        self.manager = manager
        self.defaults = defaults
    }

    // MARK: - Save

    @discardableResult
    func save(title: String, body: String) -> Note {
        let folderID = resolveOrCreateInboxFolder()
        let effectiveTitle = derivedTitle(rawTitle: title, body: body)
        logger.info("Saving quick note: \(effectiveTitle)")
        return manager.addNote(
            title: effectiveTitle,
            content: body,
            folderID: folderID
        )
    }

    // MARK: - Folder resolution

    private func resolveOrCreateInboxFolder() -> UUID {
        if let idString = defaults.string(forKey: ThemeManager.quickNotesFolderIDKey),
           let id = UUID(uuidString: idString),
           manager.folders.contains(where: { $0.id == id }) {
            return id
        }

        // Create a new folder and persist its ID.
        let folder = manager.addFolder(name: Self.inboxFolderName)
        defaults.set(folder.id.uuidString, forKey: ThemeManager.quickNotesFolderIDKey)
        return folder.id
    }

    // MARK: - Title derivation

    private func derivedTitle(rawTitle: String, body: String) -> String {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        // First non-empty line of body, truncated.
        let firstLine = body
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })

        if let line = firstLine, !line.isEmpty {
            if line.count <= Self.titleTruncationLimit {
                return line
            }
            return String(line.prefix(Self.titleTruncationLimit))
        }

        return "Quick Note"
    }
}
```

**Important:** This file references `manager.addFolder(name:)`. Before proceeding, verify that method exists on `SimpleSwiftDataManager`:

```bash
grep -n "func addFolder" /Users/mohebanwari/development/Jot/Jot/Models/SwiftData/SimpleSwiftDataManager.swift
```

If the signature is different (e.g., `addFolder(_:)` or `createFolder(name:)`), update the call site in `resolveOrCreateInboxFolder()` to match. Do not guess — use the actual signature from the source.

### - [ ] Step 4.4: Run tests to verify they pass

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/QuickNoteServiceTests test -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: `TEST SUCCEEDED`, 6 tests pass.

### - [ ] Step 4.5: Commit

```bash
git add Jot/Utils/QuickNoteService.swift JotTests/QuickNoteTests.swift
git commit -m "feat: add QuickNoteService with folder resolution and title fallback

Single save path for quick notes. Auto-creates a 'Quick Notes' inbox
folder on first save, reuses it thereafter, and transparently recreates
it if the stored ID points to a deleted folder. Empty titles derive
from the first line of the body, truncated to 60 chars.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `QuickNotePanel.swift` — NSPanel subclass + Window controller + SwiftUI view

**Files:**

- Create: `Jot/Views/Screens/QuickNotePanel.swift`

This file contains three related types in one file because they're tightly coupled and small: the NSPanel subclass, the window controller singleton, and the SwiftUI content view. Splitting them would fragment a feature that reads most clearly as one unit.

No unit tests — NSPanel and NSHostingView can't be exercised meaningfully from XCTest without a running event loop. Verified by build success + manual smoke in Task 12.

### - [ ] Step 5.1: Implement the file

Create `Jot/Views/Screens/QuickNotePanel.swift`:

```swift
//
//  QuickNotePanel.swift
//  Jot
//
//  Floating panel for Quick Notes capture. Three types in one file
//  because they're tightly coupled and small:
//    1. QuickNotePanelWindow  — NSPanel subclass that can become key but not main
//    2. QuickNoteWindowController — singleton that owns the panel
//    3. QuickNotePanelView    — SwiftUI content view hosted inside the panel
//

import AppKit
import SwiftUI
import os

// MARK: - NSPanel subclass

final class QuickNotePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Window controller

@MainActor
final class QuickNoteWindowController {

    static let shared = QuickNoteWindowController()

    private var panel: QuickNotePanelWindow?
    private weak var previousApp: NSRunningApplication?
    private let logger = Logger(subsystem: "com.jot", category: "QuickNoteWindowController")

    private init() {}

    // MARK: - Public API

    func showPanel() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if panel == nil {
            panel = makePanel()
        }

        guard let panel = panel else { return }

        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        resetContent()
        panel.center()
        panel.alphaValue = 1.0
        panel.makeKeyAndOrderFront(nil)
    }

    func dismissPanel(saved: Bool) {
        guard let panel = panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1.0
            self?.previousApp?.activate()
            self?.previousApp = nil
        })
    }

    // MARK: - Panel construction

    private func makePanel() -> QuickNotePanelWindow {
        let size = NSSize(width: 480, height: 320)
        let rect = NSRect(origin: .zero, size: size)

        let panel = QuickNotePanelWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("QuickNotePanel")
        panel.isReleasedWhenClosed = false

        let rootView = QuickNotePanelView(
            onSave: { [weak self] title, body in
                QuickNoteService.shared.save(title: title, body: body)
                self?.dismissPanel(saved: true)
            },
            onCancel: { [weak self] in
                self?.dismissPanel(saved: false)
            }
        )
        panel.contentView = NSHostingView(rootView: rootView)
        return panel
    }

    private func resetContent() {
        guard let panel = panel else { return }
        let rootView = QuickNotePanelView(
            onSave: { [weak self] title, body in
                QuickNoteService.shared.save(title: title, body: body)
                self?.dismissPanel(saved: true)
            },
            onCancel: { [weak self] in
                self?.dismissPanel(saved: false)
            }
        )
        panel.contentView = NSHostingView(rootView: rootView)
    }
}

// MARK: - SwiftUI content

struct QuickNotePanelView: View {

    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var body: String = ""
    @State private var showSavedCheckmark: Bool = false
    @FocusState private var focus: Field?
    @Environment(\.colorScheme) private var colorScheme

    private enum Field { case title, body }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(FontManager.heading(size: 20, weight: .semibold))
                .foregroundColor(Color("PrimaryTextColor"))
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
                .focused($focus, equals: .title)
                .onSubmit {
                    focus = .body
                }

            Divider()
                .foregroundColor(Color("BorderSubtleColor"))
                .padding(.horizontal, 20)

            TextEditor(text: $body)
                .scrollContentBackground(.hidden)
                .font(FontManager.body(size: 14))
                .foregroundColor(Color("PrimaryTextColor"))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .focused($focus, equals: .body)

            footer
        }
        .background(
            ZStack {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        )
        .onAppear {
            // Slight delay so the window is actually key before focus moves
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                focus = .title
            }
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onKeyPress(keys: [.return]) { press in
            if press.modifiers.contains(.command) {
                performSave()
                return .handled
            }
            return .ignored
        }
    }

    private var footer: some View {
        HStack {
            if showSavedCheckmark {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved")
                        .font(FontManager.metadata(size: 11, weight: .semibold))
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .transition(.opacity)
            } else {
                Text("⌘↩ to save · esc to cancel")
                    .font(FontManager.metadata(size: 11, weight: .medium))
                    .foregroundColor(Color("SecondaryTextColor"))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func performSave() {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty || !trimmedTitle.isEmpty else { return }

        withAnimation(.easeIn(duration: 0.15)) {
            showSavedCheckmark = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onSave(title, body)
        }
    }
}
```

### - [ ] Step 5.2: Build to verify

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -30
```

Expected: `BUILD SUCCEEDED`. If you get errors about `glassEffect` or `FontManager`, re-check the imports and confirm the project targets macOS 26+.

### - [ ] Step 5.3: Commit

```bash
git add Jot/Views/Screens/QuickNotePanel.swift
git commit -m "feat: add QuickNotePanel (NSPanel + WindowController + SwiftUI view)

Three tightly-coupled types in one file: nonactivating NSPanel subclass,
singleton window controller that manages show/dismiss with focus return
to the previous frontmost app, and a plain-text SwiftUI capture view.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `HotKeyRecorderView` — Settings chord recorder

**Files:**

- Create: `Jot/Views/Components/HotKeyRecorderView.swift`

### - [ ] Step 6.1: Implement the recorder

Create `Jot/Views/Components/HotKeyRecorderView.swift`:

```swift
//
//  HotKeyRecorderView.swift
//  Jot
//
//  SwiftUI control for recording a keyboard chord and storing it as a
//  QuickNoteHotKey. Uses a local NSEvent monitor only while recording.
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotKeyRecorderView: View {

    @Binding var hotKey: QuickNoteHotKey?
    let onChange: (QuickNoteHotKey?) -> Void

    @State private var isRecording: Bool = false
    @State private var errorMessage: String?
    @State private var localMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                Text(buttonLabel)
                    .font(FontManager.metadata(size: 11, weight: .semibold))
                    .foregroundColor(labelColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(buttonBackground)
                    )
            }
            .buttonStyle(.plain)
            .macPointingHandCursor()

            if hotKey != nil && !isRecording {
                Button(action: clearHotKey) {
                    Text("Clear")
                        .font(FontManager.metadata(size: 11, weight: .medium))
                        .foregroundColor(Color("SecondaryTextColor"))
                }
                .buttonStyle(.plain)
                .macPointingHandCursor()
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(FontManager.metadata(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Labels and colors

    private var buttonLabel: String {
        if isRecording { return "Press a chord…" }
        if let hk = hotKey { return hk.displayString }
        return "Click to record"
    }

    private var labelColor: Color {
        if isRecording { return Color("PrimaryTextColor") }
        return hotKey == nil ? Color("SecondaryTextColor") : Color("PrimaryTextColor")
    }

    private var buttonBackground: Color {
        if isRecording {
            return Color.accentColor.opacity(0.2)
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    // MARK: - Recording state

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        errorMessage = nil
        isRecording = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleEvent(event)
            return nil // swallow
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        // Escape cancels recording without change
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let carbonMods = QuickNoteHotKey.carbonModifiers(from: event.modifierFlags)
        let candidate = QuickNoteHotKey(keyCode: UInt32(event.keyCode), modifiers: carbonMods)

        guard candidate.hasAnyModifier else {
            errorMessage = "Shortcut requires at least one modifier"
            return
        }

        hotKey = candidate
        onChange(candidate)
        stopRecording()
    }

    private func clearHotKey() {
        hotKey = nil
        errorMessage = nil
        onChange(nil)
    }
}
```

### - [ ] Step 6.2: Build to verify

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

### - [ ] Step 6.3: Commit

```bash
git add Jot/Views/Components/HotKeyRecorderView.swift
git commit -m "feat: add HotKeyRecorderView for Settings chord capture

Local NSEvent monitor during recording. Rejects modifier-less keys.
Escape cancels. Clear button unbinds. Surfaces inline error messages
for invalid chords.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Wire Settings integration — add Quick Notes row to General tab

**Files:**

- Modify: `Jot/Views/Components/FloatingSettings.swift`

### - [ ] Step 7.1: Locate the General tab content region

```bash
grep -n "activeTab == .general\|case .general\|generalContent\|generalPage\|generalPanel" \
  /Users/mohebanwari/development/Jot/Jot/Views/Components/FloatingSettings.swift
```

Identify where the General tab content begins and find a sensible place to add a new `settingsGroupedCard { … }` block, typically just before or after the existing sort order picker row (`settingsSortPicker`).

### - [ ] Step 7.2: Add the Quick Notes row

Inside the General tab's content `VStack`, add a new card block. Insert after the existing sort order / grouping controls. The exact position is a judgment call — match the surrounding structure.

Add this block using the existing `settingsGroupedCard` helper:

```swift
settingsGroupedCard {
    VStack(alignment: .leading, spacing: 6) {
        Text("Quick Notes")
            .font(FontManager.heading(size: 13, weight: .semibold))
            .foregroundColor(Color("PrimaryTextColor"))

        Text("Open a floating note panel from any app using a global keyboard shortcut.")
            .font(FontManager.metadata(size: 11, weight: .medium))
            .foregroundColor(Color("SecondaryTextColor"))
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)

    HStack {
        Text("Shortcut")
            .font(FontManager.heading(size: 13, weight: .medium))
            .tracking(-0.5)
            .foregroundColor(Color("SettingsPlaceholderTextColor"))

        Spacer()

        HotKeyRecorderView(
            hotKey: $themeManager.quickNoteHotKey,
            onChange: { newHotKey in
                if let hk = newHotKey {
                    GlobalHotKeyManager.shared.replace(with: hk)
                } else {
                    GlobalHotKeyManager.shared.uninstall()
                }
            }
        )
    }
}
```

### - [ ] Step 7.3: Build to verify

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

### - [ ] Step 7.4: Commit

```bash
git add Jot/Views/Components/FloatingSettings.swift
git commit -m "feat: add Quick Notes shortcut row to Settings General tab

HotKeyRecorderView wired to themeManager.quickNoteHotKey. On change,
GlobalHotKeyManager.replace is called so the hotkey re-registers
immediately without requiring an app restart.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Wire `JotApp` — install hotkey at launch

**Files:**

- Modify: `Jot/App/JotApp.swift`

### - [ ] Step 8.1: Add hotkey registration to `JotApp.init`

In `Jot/App/JotApp.swift`, inside the `init()` method, append this block **after** the existing `PrintKeyHandler.shared.install()` line (around line 60):

```swift
        // Install Quick Notes global hotkey (default ⌃⌥⌘N on first launch)
        let storedHotKey = QuickNoteHotKey.loadFromStandardDefaults() ?? .default
        GlobalHotKeyManager.shared.onFire = { @MainActor in
            QuickNoteWindowController.shared.showPanel()
        }
        GlobalHotKeyManager.shared.install(storedHotKey)
```

### - [ ] Step 8.2: Add the `loadFromStandardDefaults` helper

In `Jot/Utils/QuickNoteHotKey.swift`, append this extension at the bottom of the file (outside the struct definition):

```swift
extension QuickNoteHotKey {
    /// Reads the hotkey from the shared `UserDefaults.standard` using the same key
    /// ThemeManager uses. This is a convenience for `JotApp.init` where we need the
    /// hotkey before `ThemeManager` is constructed.
    static func loadFromStandardDefaults() -> QuickNoteHotKey? {
        guard let data = UserDefaults.standard.data(forKey: ThemeManager.quickNoteHotKeyKey),
              let decoded = try? JSONDecoder().decode(QuickNoteHotKey.self, from: data) else {
            return nil
        }
        return decoded
    }
}
```

### - [ ] Step 8.3: Build to verify

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -30
```

Expected: `BUILD SUCCEEDED`.

### - [ ] Step 8.4: Run the full test suite to make sure nothing regressed

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected: `TEST SUCCEEDED`, all suites pass.

### - [ ] Step 8.5: Commit

```bash
git add Jot/App/JotApp.swift Jot/Utils/QuickNoteHotKey.swift
git commit -m "feat: wire Quick Notes hotkey installation in JotApp.init

Reads the stored hotkey from UserDefaults (or falls back to the default
⌃⌥⌘N) and installs it at app launch. Fire callback shows the
QuickNoteWindowController panel on the main actor.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Manual smoke test

**Files:** none (manual only)

The unit tests cover the pure-data and pure-Swift layers. The OS integration can only be verified manually by running the app.

### - [ ] Step 9.1: Build the app for running

```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build -allowProvisioningUpdates 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`. **Do not relaunch the app yourself** — the user will relaunch via the in-app updates panel. Ask the user to relaunch before proceeding to step 9.2.

### - [ ] Step 9.2: Walk the smoke checklist with the user

Ask the user to verify each:

- [ ] Press `⌃⌥⌘N` while Safari (or any other app) is frontmost → Quick Notes panel appears, Safari stays frontmost in the Dock
- [ ] Type a title and body, press `⌘↩` → footer shows "Saved" checkmark briefly, panel fades out
- [ ] Focus returns to Safari (or whichever app was previously active)
- [ ] Open main Jot window → new note appears under the "Quick Notes" folder in the sidebar
- [ ] Press `⌃⌥⌘N` again while the panel is visible → panel stays, focus returns to panel
- [ ] Press `⌃⌥⌘N`, type nothing, press `escape` → panel dismisses with no saved note
- [ ] Press `⌃⌥⌘N`, type body only (no title), press `⌘↩` → note is created with the first line of body as title
- [ ] Open Settings → General tab → locate the Quick Notes row → click the chord button → press `⌘⇧K` → chord updates to `⌘⇧K`
- [ ] Close Settings → press `⌘⇧K` in Safari → panel appears (new chord works)
- [ ] Press old `⌃⌥⌘N` in Safari → nothing happens (old chord unbound)
- [ ] Open Settings → click `Clear` next to the Quick Notes chord → press `⌘⇧K` → nothing happens (hotkey fully cleared)
- [ ] Rebind by clicking the recorder → press `⌃⌥⌘N` → chord restored
- [ ] Delete the "Quick Notes" folder manually from the sidebar → press `⌃⌥⌘N` → type a new note → save → folder is recreated

### - [ ] Step 9.3: Note any failures

If any smoke test fails, stop and file each failure as a bug before continuing. Do not declare the feature done.

---

## Task 10: Update memory and roadmap

**Files:**

- Modify: `roadmap.md`
- Modify: `/Users/mohebanwari/.claude/projects/-Users-mohebanwari-development-Jot/memory/project_apple_notes_roadmap_apr08.md`

### - [ ] Step 10.1: Update the roadmap

In `roadmap.md`, change Phase 2 Feature 3 from "Not implemented" to "Completed":

Find the section header `### 3. Quick Notes (Global Hotkey Capture)` and update:

- Change `**Status:** Not implemented` to `**Status:** Completed`
- Add a `**Changes:**` line describing what was built (6 new files, 3 modified, Carbon-based registration, NSPanel panel, default ⌃⌥⌘N, configurable via Settings)
- Match the format used by the completed Phase 1 entries above it

### - [ ] Step 10.2: Update the memory file

In `/Users/mohebanwari/.claude/projects/-Users-mohebanwari-development-Jot/memory/project_apple_notes_roadmap_apr08.md`:

- Move item 3 from "Remaining" to "Completed" with a brief description
- Keep items 4, 5, 6 in "Remaining"
- Update the `description` frontmatter field if needed ("3 features done, 3 remaining")

### - [ ] Step 10.3: Commit

```bash
git add roadmap.md
git commit -m "docs: mark Quick Notes (Phase 2 #3) as completed in roadmap

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

The memory file lives outside the repo and is not committed.

---

## Self-review notes

**Spec coverage check:**

- [x] Hotkey subsystem (Task 1 + 3 + 8)
- [x] QuickNoteHotKey value type with Cocoa↔Carbon translation (Task 1)
- [x] GlobalHotKeyManager Carbon wrapper (Task 3)
- [x] Panel subsystem — NSPanel + WindowController + SwiftUI view (Task 5)
- [x] QuickNoteService with folder resolution + title fallback (Task 4)
- [x] ThemeManager persistence (Task 2)
- [x] HotKeyRecorderView (Task 6)
- [x] Settings integration (Task 7)
- [x] JotApp wiring (Task 8)
- [x] Edge cases covered: #1 install failure (Task 3 logs), #2/#3 idempotent show (Task 5), #4 stale folder (Task 4 test), #6 hotkey-before-init (Task 8 placement), #8 silent escape (Task 5), #11 hot-swap (Task 7 onChange callback)
- [x] Unit tests for pure layers (Tasks 1, 2, 4)
- [x] Manual smoke test for OS integration (Task 9)
- [x] Documentation updates (Task 10)

**Placeholder scan:** No "TBD", "TODO", or "similar to" references. Every step with code shows the actual code.

**Type consistency:** `QuickNoteHotKey`, `GlobalHotKeyManager`, `QuickNoteService`, `QuickNotePanelWindow`, `QuickNoteWindowController`, `QuickNotePanelView`, `HotKeyRecorderView`, `ThemeManager.quickNoteHotKey`, `ThemeManager.quickNoteHotKeyKey`, `ThemeManager.quickNotesFolderIDKey` — all used consistently.

**Known verification points flagged inline** (not gaps, just things the executor must confirm against current code):

- Task 4.1: verify `SimpleSwiftDataManager` in-memory init pattern matches existing tests
- Task 4.3: verify `addFolder(name:)` method signature
- Task 7.1: locate exact insertion point in General tab

These are legitimate "look at the current code before editing" checks, not TBDs.
