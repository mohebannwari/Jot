//
//  QuickNotePanel.swift
//  Jot
//
//  Floating panel for Quick Notes capture. Three tightly-coupled types live
//  together in this file because they're small and reading them together is
//  clearer than splitting them across three files:
//    1. QuickNotePanelWindow      — borderless NSPanel subclass
//    2. QuickNoteWindowController — singleton owning the panel lifecycle
//    3. QuickNotePanelView        — SwiftUI plain-text editor inside the panel
//

import AppKit
import SwiftUI

// MARK: - NSPanel subclass

/// Borderless NSPanel that can become key (so its text fields accept input)
/// but never becomes main (so it never steals the main-window role from
/// ContentView). The borderless style is required to drop Apple's window
/// chrome (rounded rect, traffic lights, titlebar) — without it, our custom
/// liquid-glass surface would render *inside* a second outer rectangle.
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

  private init() {}

  // MARK: - Public

  /// Show the panel. Captures the currently frontmost app so focus can be
  /// restored on dismiss. If the panel is already visible, brings it forward
  /// without resetting content.
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

    // Reset to empty content by rebuilding the hosting view. Cheap and
    // guarantees @State goes back to defaults without any indirection.
    installContent(into: panel)

    // Do NOT call center() here — the frame autosave restores the user's
    // last position. Centering on every show would defeat that.
    panel.alphaValue = 1.0
    panel.makeKeyAndOrderFront(nil)
  }

  /// Dismiss the panel. Two distinct animations depending on why:
  ///   - `saved: true`  → SpriteKit genie warp toward the main Jot window,
  ///                      signalling "your note is now in the app"
  ///   - `saved: false` → SwiftUI atom dissolve driven off a window-server
  ///                      snapshot of the panel, signalling "the ink
  ///                      decomposes into nothing"
  /// Both paths restore focus to whichever app was frontmost when the
  /// panel was summoned.
  func dismissPanel(saved: Bool) {
    guard let panel = panel, panel.isVisible else { return }

    if saved {
      let target = genieTargetPoint(excluding: panel)
      GenieDismiss.run(panel: panel, toward: target) { [weak self] in
        self?.previousApp?.activate()
        self?.previousApp = nil
      }
      return
    }

    AtomDismiss.run(panel: panel) { [weak self] in
      self?.previousApp?.activate()
      self?.previousApp = nil
    }
  }

  /// Chooses the collapse point for the genie animation.
  /// Preference order:
  ///   1. `NSApp.mainWindow` — Apple's designated main content window.
  ///      This is the correct answer when Jot has a main window and the
  ///      Quick Note panel was summoned from within the app.
  ///   2. The largest visible window in `NSApp.windows` that is NOT an
  ///      NSPanel subclass — handles the case where the global hotkey
  ///      fires while a non-Jot app is frontmost and mainWindow is nil.
  ///      Excluding NSPanel ensures we don't target the Quick Note panel
  ///      itself or any other floating palette.
  ///   3. Bottom-center of the screen as a last-resort fallback.
  private func genieTargetPoint(excluding: NSPanel) -> CGPoint {
    if let main = NSApp.mainWindow,
      main !== excluding,
      main.isVisible,
      main.contentView != nil
    {
      return CGPoint(x: main.frame.midX, y: main.frame.midY)
    }

    let candidates = NSApp.windows.filter { win in
      win !== excluding
        && !(win is NSPanel)
        && win.isVisible
        && win.contentView != nil
        && win.frame.width > 100
        && win.frame.height > 100
    }
    if let biggest = candidates.max(by: {
      ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
    }) {
      return CGPoint(x: biggest.frame.midX, y: biggest.frame.midY)
    }

    let screen = excluding.screen ?? NSScreen.main ?? NSScreen.screens.first
    if let frame = screen?.frame {
      return CGPoint(x: frame.midX, y: frame.minY + 60)
    }
    return .zero
  }

  // MARK: - Panel construction

  private func makePanel() -> QuickNotePanelWindow {
    let initialSize = NSSize(width: 600, height: 400)
    let rect = NSRect(origin: .zero, size: initialSize)

    // Borderless + nonactivating + resizable. No .titled, no .closable —
    // the SwiftUI surface is the entire chrome.
    let panel = QuickNotePanelWindow(
      contentRect: rect,
      styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false

    // Make the window itself transparent so only the SwiftUI rounded glass
    // is visible. hasShadow still works because the glass content is opaque.
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true

    // Reasonable lower bound so the user can't shrink past usability.
    // NSWindow.minSize is ignored when the content view uses AutoLayout
    // (which NSHostingView does), so contentMinSize is the authoritative
    // setting. Setting both for belt-and-suspenders.
    let minPanelSize = NSSize(width: 360, height: 240)
    panel.minSize = minPanelSize
    panel.contentMinSize = minPanelSize

    // Try to restore the user's last position; only center if there is none.
    let autosaveKey = "NSWindow Frame QuickNotePanel"
    let hasSavedFrame = UserDefaults.standard.string(forKey: autosaveKey) != nil
    panel.setFrameAutosaveName("QuickNotePanel")
    if !hasSavedFrame {
      panel.center()
    }

    installContent(into: panel)
    return panel
  }

  private func installContent(into panel: QuickNotePanelWindow) {
    // Read the latest persisted appearance settings each time the panel is
    // rebuilt so Quick Notes stays visually in sync with the main app after
    // users change the tint controls in Settings.
    let themeManager = ThemeManager()
    let rootView = QuickNotePanelView(
      themeManager: themeManager,
      onSave: { [weak self] title, body in
        QuickNoteService.shared.save(title: title, body: body)
        self?.dismissPanel(saved: true)
      },
      onCancel: { [weak self] in
        self?.dismissPanel(saved: false)
      }
    )
    let hosting = NSHostingView(rootView: rootView)
    hosting.autoresizingMask = [.width, .height]
    panel.contentView = hosting
  }
}

// MARK: - SwiftUI content

/// Small, testable style model for the floating Quick Notes shell.
/// Keeping these values in one place makes regressions easy to spot in tests
/// and keeps the view body focused on layout instead of style bookkeeping.
struct QuickNotePanelChrome {
  let cornerRadius: CGFloat = 22
  let showsTitleDivider: Bool = false
  let scrollIndicatorVisibility: ScrollIndicatorVisibility = .never
  let darkModeBorderOpacity: Double = 0.10
  let glassTintOpacity: Double = 0.80
  let fallbackSurfaceOpacity: Double = 0.95
  let surfaceTint: Color

  init(themeManager: ThemeManager, colorScheme: ColorScheme) {
    // Match the detail pane's single tint source so Quick Notes inherits
    // the same hue wash instead of falling back to the raw asset color.
    self.surfaceTint = themeManager.tintedPaneSurface(for: colorScheme)
  }
}

struct QuickNotePanelView: View {
  @ObservedObject private var themeManager: ThemeManager

  let onSave: (String, String) -> Void
  let onCancel: () -> Void

  @State private var title: String = ""
  @State private var bodyText: String = ""
  /// Sentinel set on the first performSave invocation to block double
  /// Cmd+Return presses from firing two saves while the genie animation
  /// is in flight. The genie IS the visual feedback — there's no checkmark
  /// or delay to race.
  @State private var saveInFlight: Bool = false
  @FocusState private var focus: Field?
  @Environment(\.colorScheme) private var colorScheme

  private enum Field { case title, body }

  init(
    themeManager: ThemeManager,
    onSave: @escaping (String, String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self._themeManager = ObservedObject(wrappedValue: themeManager)
    self.onSave = onSave
    self.onCancel = onCancel
  }

  private var hasContent: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var chrome: QuickNotePanelChrome {
    QuickNotePanelChrome(themeManager: themeManager, colorScheme: colorScheme)
  }

  var body: some View {
    VStack(spacing: 0) {
      TextField("Title", text: $title)
        .textFieldStyle(.plain)
        .jotUI(FontManager.uiPro(size: 22, weight: .semibold))
        .foregroundColor(Color("PrimaryTextColor"))
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .focused($focus, equals: .title)
        .onSubmit {
          focus = .body
        }

      TextEditor(text: $bodyText)
        .scrollContentBackground(.hidden)
        .scrollIndicators(chrome.scrollIndicatorVisibility)
        .font(FontManager.body(size: 15))
        .foregroundColor(Color("PrimaryTextColor"))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .focused($focus, equals: .body)

      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Backdrop matches the main Jot content pane's treatment so the
    // Quick Note panel reads as a floating "mini detail pane": warm
    // stone palette, same material family. On macOS 26+ it's tinted
    // Liquid Glass with DetailPaneSurfaceColor; on pre-26 it falls back
    // to an NSVisualEffectView (.hudWindow / .behindWindow) with a
    // 95%-opaque DetailPaneSurfaceColor over the top, mirroring what
    // ContentView does for the main window.
    .background {
      if #available(macOS 26.0, iOS 26.0, *) {
        Color.clear
          .tintedLiquidGlass(
            in: RoundedRectangle(cornerRadius: chrome.cornerRadius, style: .continuous),
            tint: chrome.surfaceTint,
            tintOpacity: chrome.glassTintOpacity
          )
      } else {
        ZStack {
          BackdropBlurView(material: .hudWindow, blendingMode: .behindWindow)
          chrome.surfaceTint.opacity(chrome.fallbackSurfaceOpacity)
        }
        .clipShape(RoundedRectangle(cornerRadius: chrome.cornerRadius, style: .continuous))
      }
    }
    // CLAUDE.md normally bans clipShape on parent containers, but this
    // is a deliberate exception: the panel is borderless and transparent,
    // so this rounded clip is the only thing producing the panel's
    // visible corners. Without it the SwiftUI surface would render as a
    // square against the empty NSWindow.
    .clipShape(RoundedRectangle(cornerRadius: chrome.cornerRadius, style: .continuous))
    .overlay {
      if colorScheme == .dark {
        RoundedRectangle(cornerRadius: chrome.cornerRadius, style: .continuous)
          .stroke(Color.white.opacity(chrome.darkModeBorderOpacity), lineWidth: 1)
      }
    }
    .onAppear {
      // Tiny delay so the window is actually key before focus tries to land.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
        focus = .title
      }
    }
    .onKeyPress(.escape) {
      onCancel()
      return .handled
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 12) {
      saveButton
      Spacer()
      Text("esc cancel")
        .jotMetadataLabelTypography()
        .foregroundColor(Color("SecondaryTextColor"))
    }
    // Horizontal inset matches the body editor (20). Bottom inset matches
    // that same gutter so the Save capsule aligns visually with the panel
    // corners; top stays slightly tighter against the editor scroll view.
    .padding(.horizontal, 20)
    .padding(.top, 14)
    .padding(.bottom, 20)
  }

  /// The Save button is also the Cmd+Return accelerator — one button serves
  /// both the visible and keyboard paths. The ⌘↩ glyphs live inside the
  /// capsule next to the label so there's a single "Save" in the UI.
  private var saveButton: some View {
    Button(action: performSave) {
      HStack(spacing: 6) {
        Text("Save")
          .jotUI(FontManager.uiLabel3(weight: .regular))
        Text("\u{2318}\u{21A9}")
          .jotMetadataLabelTypography()
          .opacity(0.6)
      }
      .foregroundColor(Color("ButtonPrimaryTextColor"))
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(
        Capsule().fill(
          hasContent
            ? Color("ButtonPrimaryBgColor")
            : Color("ButtonPrimaryBgColor").opacity(0.35)
        )
      )
    }
    .buttonStyle(.plain)
    .keyboardShortcut(.return, modifiers: .command)
    .disabled(!hasContent || saveInFlight)
    .macPointingHandCursor()
  }

  // MARK: - Save action

  /// Fires the save immediately and lets the controller drive the genie
  /// animation. `saveInFlight` blocks the second of two Cmd+Return presses
  /// that arrive during the animation window, which would otherwise call
  /// `onSave` twice before the panel has been ordered out.
  private func performSave() {
    guard hasContent, !saveInFlight else { return }
    saveInFlight = true
    onSave(title, bodyText)
  }
}
