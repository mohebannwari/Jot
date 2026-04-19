//
//  NoteDetailView.swift
//  Jot
//
//  Created by AI on 15.08.25.
//
//  Figma-aligned note detail view.
//  Gallery logic lives in NoteDetailView+Gallery.swift
//  Voice/image/link handlers live in NoteDetailView+Actions.swift

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteDetailView: View {
  let note: Note
  let editorInstanceID: UUID
  let focusRequestID: UUID
  let contentTopInsetAdjustment: CGFloat
  let stickyHeaderTopPadding: CGFloat
  var onSave: (Note) -> Void
  var availableNotes: [NotePickerItem] = []
  var onNavigateToNote: ((UUID) -> Void)?
  var backlinks: [BacklinkItem] = []
  var isSidebarAnimating: Bool = false
  var isPanelAnimating: Bool = false

  private var isLayoutAnimating: Bool { isSidebarAnimating || isPanelAnimating }

  /// Matches ``editorScrollContent`` top padding and sticker placement math.
  private var noteDetailScrollContentTopInset: CGFloat {
    FontManager.noteDetailEditorScrollTopInset()
  }

  // MARK: - Environment
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @EnvironmentObject private var themeManager: ThemeManager
  @EnvironmentObject var notesManager: SimpleSwiftDataManager
  @EnvironmentObject var meetingRecorderManager: MeetingRecorderManager

  // MARK: - Core editing state
  @State var editedTitle: String
  @State var editedContent: String
  @State private var autosaveWorkItem: DispatchWorkItem?
  @State private var lastSavedSnapshot: DraftSnapshot
  /// The note whose content editedTitle/editedContent currently describe.
  /// Distinct from `note` (the prop), which SwiftUI updates to the NEW note BEFORE
  /// `onChange(of: note.id)` fires — so `persistIfNeeded()` must use this, not `note`.
  @State private var noteForPersist: Note

  // MARK: - UI animation state
  @State private var glassElementsVisible = false
  @Namespace private var glassNamespace

  // MARK: - Sticker state
  @State private var editedStickers: [Sticker] = []
  @State private var lastSavedStickers: [Sticker] = []
  @State private var isPlacingSticker = false
  @State private var selectedStickerID: UUID? = nil
  @StateObject private var stickerUndoController = StickerUndoController()

  // MARK: - Overlay state (accessed by +Actions extension)
  @State var showVoiceRecorderOverlay = false
  @State private var showFileLinkPicker = false
  @State var showLinkInputOverlay = false
  @State var linkInputText = ""
  @FocusState var isLinkInputFocused: Bool

  // MARK: - Search on page state (accessed by +Actions extension)
  @State var showSearchOnPageOverlay = false
  @State var searchOnPageQuery = ""
  @State var searchOnPageMatches: [NSRange] = []
  @State var searchOnPageCurrentIndex: Int = 0
  @FocusState var isSearchOnPageFocused: Bool
  @State var replaceText = ""
  @State var showReplaceField = false
  @FocusState var isReplaceFocused: Bool

  // MARK: - Apple Intelligence state
  @State var aiPanelState: AIPanelState = .none  // loading / proofread / editPreview / error
  @State var aiSummaryText: String? = nil  // independent — not cleared by other tools
  @State var aiKeyPointsItems: [String]? = nil  // independent — not cleared by other tools
  /// Tracks whether AI results were loaded from persisted content (prevents re-save on init).
  @State private var aiBlockLoadedFromContent = false
  @State var aiIsProcessing: Bool = false
  /// Tracks the current in-flight AI Task so it can be cancelled on note switch.
  @State var currentAITask: Task<Void, Never>?
  @State private var aiStateCache: [UUID: AIPanelState] = [:]
  @State var currentProofreadIndex: Int = 0

  // Selection capture for Edit Content
  @State var capturedSelectionRange: NSRange = NSRange(location: NSNotFound, length: 0)
  @State var capturedSelectionText: String = ""
  @State var capturedSelectionWindowRect: CGRect = .zero
  @State var aiCaptureIsCardOrigin: Bool = false

  // Edit Content floating panel
  @State var showEditContentPanel: Bool = false

  // Translate floating panel
  @State var showTranslatePanel: Bool = false

  // Text Generation floating panel
  @State var showTextGenPanel: Bool = false

  // Meeting Notes - now driven by shared MeetingRecorderManager (see ContentView)
  // Local state only for panel visibility and persisted sessions. Recording continues
  // in background when switching notes. Waveform levels and state come from manager.
  // The local meetingRecordingState, meetingAudioRecorder, meetingTranscriptionService
  // have been removed to avoid duplicate instances. The manager handles persistence.
  @State var showMeetingPanel: Bool = false
  /// Drives the floating meeting panel's entrance/exit motion. SwiftUI's `.transition`
  /// on this overlay often does not run when `MeetingRecorderManager` publishes many
  /// `@Published` updates in the same turn as `showMeetingPanel` flips, so we animate
  /// scale/offset/opacity explicitly instead of relying on `AnyTransition` alone.
  @State var meetingPanelEntranceRevealed: Bool = false

  // Persisted meeting data (loaded from note, updated on save)
  @State var savedIsMeetingNote: Bool = false
  @State var savedMeetingSessions: [MeetingSession] = []

  // MARK: - Scroll / toolbar state
  @FocusState private var titleFocused: Bool
  @State private var localEditorFocusID: UUID?
  @State private var scrollViewHeight: CGFloat = 0

  @State private var showStickyHeader = false
  @State private var headerRevealProgress: CGFloat = 0
  @State private var titleOffset: CGFloat = 0
  @State private var commandMenuNeedsSpace = false
  /// True when any popup menu (command menu, note picker) is visible.
  /// Used to disable the parent scroll view so scroll events stay in the popup.
  @State private var popupMenuActive = false
  @State private var showFloatingToolbar = false
  @State private var floatingToolbarOffset = CGPoint.zero
  @State private var floatingToolbarPlaceAbove = false
  @State private var toolbarIsBold = false
  @State private var toolbarIsItalic = false
  @State private var toolbarIsUnderline = false
  @State private var toolbarIsStrikethrough = false
  @State private var toolbarIsHighlight = false
  @State private var toolbarHeadingLevel: Int = 0
  @State private var showHighlightColorPicker = false
  @State private var highlightPickerOffset = CGPoint.zero
  @State private var lastSelectionBottomY: CGFloat = 0
  @State private var lastSelectionCenterX: CGFloat = 0
  @State private var toolbarFontSize: CGFloat = 16
  @State private var toolbarFontFamily: String = "default"
  @State private var toolbarTextColorHex: String? = nil
  @State private var measuredToolbarWidth: CGFloat = 0
  @State private var measuredToolbarHeight: CGFloat = 46
  @State private var activeToolbarSubmenu: ToolbarSubmenuType? = nil
  @State private var pillOffsets: [ToolbarSubmenuType: CGFloat] = [:]
  @State private var measuredSubmenuHeight: CGFloat = 0

  // MARK: - Constants

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    return f
  }()

  private var editorIdentity: String {
    note.id.uuidString
  }

  private struct DraftSnapshot: Equatable {
    let title: String
    let content: String
  }

  // MARK: - Init

  init(
    note: Note,
    editorInstanceID: UUID = UUID(),
    focusRequestID: UUID,
    contentTopInsetAdjustment: CGFloat = 0,
    stickyHeaderTopPadding: CGFloat = 12,
    onSave: @escaping (Note) -> Void,
    availableNotes: [NotePickerItem] = [],
    onNavigateToNote: ((UUID) -> Void)? = nil,
    backlinks: [BacklinkItem] = [],
    isSidebarAnimating: Bool = false,
    isPanelAnimating: Bool = false
  ) {
    self.note = note
    self.editorInstanceID = editorInstanceID
    self.focusRequestID = focusRequestID
    self.contentTopInsetAdjustment = contentTopInsetAdjustment
    self.stickyHeaderTopPadding = stickyHeaderTopPadding
    self.onSave = onSave
    self.availableNotes = availableNotes
    self.onNavigateToNote = onNavigateToNote
    self.backlinks = backlinks
    self.isSidebarAnimating = isSidebarAnimating
    self.isPanelAnimating = isPanelAnimating
    self._editedTitle = State(initialValue: note.title)
    // Strip AI block from persisted content so the editor never sees AI tags.
    // AI results are restored into their own @State vars.
    let parsed = NoteDetailView.stripAIBlock(note.content)
    self._editedContent = State(initialValue: parsed.content)
    self._lastSavedSnapshot = State(
      initialValue: DraftSnapshot(title: note.title, content: note.content)
    )
    self._noteForPersist = State(initialValue: note)
    self._aiSummaryText = State(initialValue: parsed.summary)
    self._aiKeyPointsItems = State(initialValue: parsed.keyPoints)
    self._aiBlockLoadedFromContent = State(
      initialValue: parsed.summary != nil || parsed.keyPoints != nil)
    self._editedStickers = State(initialValue: note.stickers)
    self._lastSavedStickers = State(initialValue: note.stickers)
    // Meeting data
    self._savedIsMeetingNote = State(initialValue: note.isMeetingNote)
    self._savedMeetingSessions = State(initialValue: note.meetingSessions)
    // Meeting panel layout fields removed — panel renders at fixed position and full width.
    // Note: meeting recorder is now shared via @EnvironmentObject in ContentView to persist across note switches.
  }

  // MARK: - Body

  var body: some View {
    noteContent
  }

  // MARK: - Note Content

  private var noteContent: some View {
    noteContentEvents2
      .fileImporter(
        isPresented: $showFileLinkPicker,
        allowedContentTypes: [.item],
        allowsMultipleSelection: false
      ) { result in
        handleFileLinkImport(result)
      }
  }

  private func handleFileLinkImport(_ result: Result<[URL], Error>) {
    if case .success(let urls) = result, let url = urls.first {
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }

      let path = url.path
      let displayName = url.lastPathComponent

      // Create a security-scoped bookmark so we can reopen this file later
      let bookmarkBase64: String
      if let bookmarkData = try? url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      ) {
        bookmarkBase64 = bookmarkData.base64EncodedString()
      } else {
        bookmarkBase64 = ""
      }

      NotificationCenter.default.post(
        name: .insertFileLinkInEditor,
        object: nil,
        userInfo: [
          "filePath": path,
          "displayName": displayName,
          "bookmarkBase64": bookmarkBase64,
          "editorInstanceID": editorInstanceID,
        ]
      )
    }
  }

  // Extracted to reduce type-checker pressure on noteContentLayout
  @ViewBuilder
  private var editorScrollContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text(noteDateString)
          .jotMetadataLabelTypography()
          .foregroundColor(Color("SecondaryTextColor"))
          .kerning(-0.25)

        if note.isArchived {
          Circle()
            .fill(Color("SecondaryTextColor"))
            .frame(width: 2, height: 2)

          Text("Archived")
            .jotMetadataLabelTypography()
            .foregroundColor(Color("SecondaryTextColor"))
            .kerning(-0.25)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 0)

      titleField
        .background(
          GeometryReader { geo in
            Color.clear
              .onChange(of: geo.frame(in: .named("scroll")).minY) {
                oldValue, newValue in
                guard !isLayoutAnimating else { return }
                titleOffset = newValue
                let shouldShow = newValue < 0
                if shouldShow != showStickyHeader {
                  withAnimation(.smooth(duration: 0.3)) {
                    showStickyHeader = shouldShow
                  }
                }
              }
          }
        )

      // Meeting notes panel — fixed position above AI panels
      if savedIsMeetingNote && !savedMeetingSessions.isEmpty {
        MeetingNoteDetailPanel(
          sessions: $savedMeetingSessions,
          onNotesChanged: { sessionID, newNotes in
            if let idx = savedMeetingSessions.firstIndex(where: { $0.id == sessionID }) {
              savedMeetingSessions[idx].manualNotes = newNotes
            }
            var updated = note
            updated.meetingSessions = savedMeetingSessions
            updated.isMeetingNote = true
            notesManager.updateNote(updated)
          },
          onSummaryChanged: { sessionID, newSummary in
            if let idx = savedMeetingSessions.firstIndex(where: { $0.id == sessionID }) {
              savedMeetingSessions[idx].summary = newSummary
            }
            var updated = note
            updated.meetingSessions = savedMeetingSessions
            updated.isMeetingNote = true
            notesManager.updateNote(updated)
          },
          onDismiss: {
            withAnimation(.jotSpring) {
              savedIsMeetingNote = false
              savedMeetingSessions = []
            }
            var updated = note
            updated.isMeetingNote = false
            updated.meetingSessions = []
            notesManager.updateNote(updated)
          }
        )
        .modifier(AIGlowFallbackModifier(cornerRadius: 22, mode: .oneShot))
        .transition(.opacity.combined(with: .offset(y: -8)))
      }

      if let summaryText = aiSummaryText {
        AIResultPanel(
          state: .summary(summaryText),
          onDismiss: {
            withAnimation(.jotSpring) { aiSummaryText = nil }
            scheduleAutosave()
          }
        )
        .modifier(AIGlowFallbackModifier(cornerRadius: 22, mode: .oneShot))
        .transition(.opacity.combined(with: .offset(y: -8)))
      }
      if let keyPointsItems = aiKeyPointsItems {
        AIResultPanel(
          state: .keyPoints(keyPointsItems),
          onDismiss: {
            withAnimation(.jotSpring) { aiKeyPointsItems = nil }
            scheduleAutosave()
          }
        )
        .modifier(AIGlowFallbackModifier(cornerRadius: 22, mode: .oneShot))
        .transition(.opacity.combined(with: .offset(y: -8)))
      }
      if shouldShowTopPanel {
        AIResultPanel(
          state: aiPanelState,
          onDismiss: {
            withAnimation(.jotSpring) { aiPanelState = .none }
          }
        )
        .transition(.opacity.combined(with: .offset(y: -8)))
      }

      TodoRichTextEditor(
        text: $editedContent,
        focusRequestID: localEditorFocusID ?? focusRequestID,
        editorInstanceID: editorInstanceID,
        onToolbarAction: handleEditToolAction,
        onCommandMenuSelection: { performAuxiliaryToolAction($0) },
        availableNotes: availableNotes,
        onNavigateToNote: onNavigateToNote,
        fetchNote: { uuid in notesManager.notes.first(where: { $0.id == uuid }) },
        onUndoManagerAvailable: { stickerUndoController.noteEditorUndoManager = $0 }
      )
      .id(editorIdentity)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, -28)  // Extend editor into VStack padding for table row handle gutter

      if commandMenuNeedsSpace {
        Color.clear
          .frame(
            height: CommandMenuLayout.idealHeight(for: CommandMenuLayout.maxVisibleItems)
              + CommandMenuLayout.outerPadding * 2
          )
          .id("menuSpacer")
      }
    }
    .padding(.top, noteDetailScrollContentTopInset)
    .padding(.horizontal, 60)
    .frame(maxWidth: .infinity, minHeight: scrollViewHeight, alignment: .topLeading)
    .overlay(alignment: .topLeading) {
      StickerCanvasOverlay(
        stickers: $editedStickers,
        isPlacingSticker: $isPlacingSticker,
        selectedStickerID: $selectedStickerID,
        onChanged: { scheduleAutosave() },
        recordStickerUndo: { old, new, name in
          stickerUndoController.record(oldStickers: old, newStickers: new, actionName: name)
        }
      )
    }
    .background(
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture {
          titleFocused = false
          localEditorFocusID = UUID()
          selectedStickerID = nil  // deselect stickers
        }
    )
  }

  // MARK: - Meeting Panel (Drag-to-Reorder)

  @ViewBuilder
  private var noteContentLayout: some View {
    ZStack(alignment: .topLeading) {
      Color.clear
        .ignoresSafeArea()

      ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
          editorScrollContent
        }
        // Otherwise SwiftUI paints an opaque scroll surface over the pane chrome and hides
        // Liquid Glass / desktop blur when detail translucency is enabled (see ContentView).
        .scrollContentBackground(
          themeManager.detailPaneTranslucency > 0.001 ? .hidden : .automatic
        )
        .onAppear {
          stickerUndoController.bind(stickers: $editedStickers)
          stickerUndoController.onAfterMutation = { scheduleAutosave() }
        }
        .padding(.top, contentTopInsetAdjustment)
        .transaction { t in
          if isLayoutAnimating { t.animation = nil }
        }
        .scrollDisabled(popupMenuActive)
        .scrollClipDisabled()
        .coordinateSpace(name: "scroll")
        .modifier(BottomContentMargin(bottom: 100))
        .background(
          GeometryReader { geo in
            Color.clear.onAppear { scrollViewHeight = geo.size.height }
              .onChange(of: geo.size.height) { _, h in
                guard !isLayoutAnimating else { return }
                scrollViewHeight = h
              }
          }
        )
        .onChange(of: commandMenuNeedsSpace) { _, needsSpace in
          if needsSpace {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("menuSpacer", anchor: .top)
              }
            }
          }
        }
      }

      // Bottom content fade
      VStack {
        Spacer()
        Rectangle()
          .fill(Color.clear)
          .frame(height: 180)
          .background(
            maskedStickyChromeFade(mask: Self.footerMaskGradient)
          )
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .allowsHitTesting(false)
      .zIndex(14)

      // Sticky header
      if showStickyHeader {
        ZStack(alignment: .top) {
          // Gradient fade — extends into the safe area (title bar zone)
          Rectangle()
            .fill(Color.clear)
            .frame(height: 180)
            .background(
              maskedStickyChromeFade(mask: Self.headerMaskGradient)
                .ignoresSafeArea(edges: .top)
            )
            .ignoresSafeArea(edges: .top)

          // Title — lives in normal content space (same as overlay icons)
          HStack {
            Spacer()
            Text(editedTitle.isEmpty ? "Untitled" : editedTitle)
              .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .medium))
              .foregroundColor(Color("PrimaryTextColor"))
              .opacity(0.5)
              .lineLimit(1)
              .truncationMode(.tail)
              .padding(.horizontal, 80)
            Spacer()
          }
          .frame(height: 24)
          .padding(.top, stickyHeaderTopPadding)
        }
        .frame(maxWidth: .infinity)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(15)
      }

    }
    .overlay(alignment: .bottom) {
      bottomOverlay
        .opacity(showFloatingToolbar ? 0.5 : 1.0)
        .animation(.jotSmoothFast, value: showFloatingToolbar)
    }
    .overlay {
      floatingToolbarOverlay
        .allowsHitTesting(showFloatingToolbar && !anyAIPanelVisible)
    }
    .overlay {
      editContentPanelOverlay
        .allowsHitTesting(showEditContentPanel)
    }
    .overlay {
      translatePanelOverlay
        .allowsHitTesting(showTranslatePanel)
    }
    .overlay {
      textGenFloatingOverlay
        .allowsHitTesting(showTextGenPanel)
    }
    .overlay {
      meetingNotesFloatingOverlay
        .allowsHitTesting(showMeetingPanel)
    }
    .overlay {
      highlightColorPickerOverlay
        .allowsHitTesting(showHighlightColorPicker)
    }
    .preference(
      key: BottomOverlayActivePreferenceKey.self,
      value: false  // mic capsule is compact — NoteToolsBar stays visible
    )
    .preference(
      key: BottomInputOverlayActivePreferenceKey.self,
      value: showSearchOnPageOverlay || showLinkInputOverlay
    )
  }

  // Event handling chain — split from layout to reduce type-checker pressure
  private var noteContentEvents: some View {
    noteContentLayout
      .onAppear {
        glassElementsVisible = true
        if isNewNote {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            titleFocused = true
          }
        }
      }
      .onDisappear {
        autosaveWorkItem?.cancel()
        persistIfNeeded()
        glassElementsVisible = false
      }
      .onChange(of: editedTitle) { _, newTitle in
        if newTitle.contains("\n") {
          editedTitle = newTitle.replacingOccurrences(of: "\n", with: "")
          titleFocused = false
          localEditorFocusID = UUID()
          return
        }
        scheduleAutosave()
      }
      .onChange(of: editedContent) { _, _ in
        scheduleAutosave()
      }
      .onChange(of: note.id) { oldNoteID, newNoteID in
        autosaveWorkItem?.cancel()
        // Serialization flush before reading `editedContent` for the outgoing save is posted from
        // `ContentView` *before* `selectedNote` changes so the live coordinator still exists (see
        // `postEditorSerializationFlush` and `.jotFlushEditorSerializationBeforeNoteSwitch`).
        // Capture old-note state for deferred save — don't block the switch path
        // with synchronous SwiftData I/O (fetch + save + recomputeDerivedNotes).
        let contentWithAI =
          editedContent + Self.buildAIBlock(summary: aiSummaryText, keyPoints: aiKeyPointsItems)
        let oldSnapshot = DraftSnapshot(title: editedTitle, content: contentWithAI)
        let oldNote = noteForPersist
        if oldSnapshot != lastSavedSnapshot || oldNote.stickers != editedStickers {
          var updated = oldNote
          updated.title = oldSnapshot.title
          updated.content = oldSnapshot.content
          updated.stickers = editedStickers
          updated.date = Date()
          onSave(updated)
        }
        noteForPersist = note

        // Flush any pending version snapshot for the outgoing note
        NoteVersionManager.shared.flushPendingSnapshot(
          for: oldNoteID, in: notesManager.modelContext)

        // Cache current state (don't cache editPreview — it's contextual to a selection)
        if case .editPreview = aiPanelState {
          aiStateCache[oldNoteID] = nil
        } else if case .translatePreview = aiPanelState {
          aiStateCache[oldNoteID] = nil
        } else if case .textGenPreview = aiPanelState {
          aiStateCache[oldNoteID] = nil
        } else {
          aiStateCache[oldNoteID] = aiPanelState == .none ? nil : aiPanelState
        }
        // Evict oldest entries if cache exceeds 10 to prevent unbounded growth
        if aiStateCache.count > 10 {
          let excess = aiStateCache.count - 10
          let keysToRemove = Array(aiStateCache.keys.prefix(excess))
          for key in keysToRemove {
            aiStateCache.removeValue(forKey: key)
          }
        }

        // Cancel any in-flight AI task — prevents stale results landing on the new note
        currentAITask?.cancel()
        currentAITask = nil

        // NOTE: Meeting recording no longer auto-dismisses on note switch.
        // The shared MeetingRecorderManager in ContentView keeps the AVAudioEngine
        // and transcription running in background. Sidebar waveform indicator shows
        // active session on the original note's row. Panel only shows when on that note.

        // Tear down transient overlays
        aiIsProcessing = false
        aiCaptureIsCardOrigin = false
        showEditContentPanel = false
        showTranslatePanel = false
        showTextGenPanel = false
        currentProofreadIndex = 0
        NotificationCenter.default.post(
          name: .aiProofreadClearOverlays, object: nil,
          userInfo: ["editorInstanceID": editorInstanceID])

        // Strip AI block from new note content and restore AI results
        let parsed = NoteDetailView.stripAIBlock(note.content)
        editedTitle = note.title
        editedContent = parsed.content
        aiSummaryText = parsed.summary
        aiKeyPointsItems = parsed.keyPoints
        lastSavedSnapshot = DraftSnapshot(title: note.title, content: note.content)
        if isNewNote {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            titleFocused = true
          }
        }
        editedStickers = note.stickers
        lastSavedStickers = note.stickers
        // Restore meeting data for new note
        savedIsMeetingNote = note.isMeetingNote
        savedMeetingSessions = note.meetingSessions
        // Sync floating meeting panel to whether this note owns the active session.
        applyMeetingPanelVisibilityForActiveSession()
        isPlacingSticker = false
        selectedStickerID = nil
        showVoiceRecorderOverlay = false
        showLinkInputOverlay = false
        showFileLinkPicker = false
        capturedSelectionRange = NSRange(location: NSNotFound, length: 0)
        capturedSelectionText = ""
        capturedSelectionWindowRect = .zero

        // Restore cached AI state for new note
        let newState = aiStateCache[newNoteID] ?? .none
        aiPanelState = newState

        // Re-apply proofread overlays if that was the cached state
        if case .proofread(let annotations) = newState, !annotations.isEmpty {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
              name: .aiProofreadShowAnnotations,
              object: annotations,
              userInfo: ["activeIndex": 0, "editorInstanceID": self.editorInstanceID]
            )
          }
        }

      }
      .onChange(of: meetingRecorderManager.recordingNoteID) { _, _ in
        applyMeetingPanelVisibilityForActiveSession()
      }
      .onChange(of: meetingRecorderManager.recordingState) { _, _ in
        applyMeetingPanelVisibilityForActiveSession()
      }
      .onReceive(NotificationCenter.default.publisher(for: .forceSaveNote)) { _ in
        autosaveWorkItem?.cancel()
        persistIfNeeded()
      }
      .onReceive(NotificationCenter.default.publisher(for: .noteToolsBarAction)) { notification in
        handleNoteToolsBarNotification(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .aiToolAction)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        guard let tool = notification.object as? AITool else { return }
        currentAITask?.cancel()
        currentAITask = Task { await handleAITool(tool) }
      }
      .onReceive(NotificationCenter.default.publisher(for: .aiEditSubmit)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        guard let instruction = notification.object as? String else { return }
        currentAITask?.cancel()
        currentAITask = Task { await handleAIEdit(instruction: instruction) }
      }
      .onReceive(NotificationCenter.default.publisher(for: .aiEditCaptureSelection)) {
        notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        guard let userInfo = notification.userInfo else { return }
        capturedSelectionRange =
          (userInfo["nsRange"] as? NSRange) ?? NSRange(location: NSNotFound, length: 0)
        capturedSelectionText = (userInfo["selectedText"] as? String) ?? ""
        capturedSelectionWindowRect = (userInfo["windowRect"] as? CGRect) ?? .zero
        aiCaptureIsCardOrigin = (userInfo["cardOrigin"] as? Bool) ?? false
      }
      .onReceive(NotificationCenter.default.publisher(for: .aiTranslateSubmit)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        guard let language = notification.object as? String else { return }
        currentAITask?.cancel()
        currentAITask = Task { await handleAITranslate(language: language) }
      }
      .onReceive(NotificationCenter.default.publisher(for: .aiTextGenSubmit)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        guard let description = notification.object as? String else { return }
        currentAITask?.cancel()
        currentAITask = Task { await handleAITextGenerate(description: description) }
      }
      .onReceive(NotificationCenter.default.publisher(for: .aiMeetingNotesStart)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        startMeetingRecording()
      }
      .onReceive(NotificationCenter.default.publisher(for: .aiProofreadApplySuggestion)) {
        notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        guard let userInfo = notification.userInfo,
          let original = userInfo["original"] as? String
        else { return }
        if case .proofread(var annotations) = aiPanelState {
          annotations.removeAll { $0.original == original }
          currentProofreadIndex =
            annotations.isEmpty ? 0 : min(currentProofreadIndex, annotations.count - 1)
          withAnimation(.jotSpring) { aiPanelState = .proofread(annotations) }
          if !annotations.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
              NotificationCenter.default.post(
                name: .aiProofreadShowAnnotations,
                object: annotations,
                userInfo: [
                  "activeIndex": self.currentProofreadIndex,
                  "editorInstanceID": self.editorInstanceID,
                ]
              )
            }
          }
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .showInNoteSearch)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        presentSearchOnPage()
      }
      .onReceive(NotificationCenter.default.publisher(for: .showInNoteSearchAndReplace)) {
        notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        presentSearchOnPage()
      }
      .onReceive(NotificationCenter.default.publisher(for: .highlightTextClicked)) { notification in
        guard let userInfo = notification.userInfo else { return }
        if let nid = userInfo["editorInstanceID"] as? UUID, nid != editorInstanceID { return }

        guard let selectionWindowX = userInfo["selectionWindowX"] as? CGFloat,
          let selectionWindowY = userInfo["selectionWindowY"] as? CGFloat,
          let selectionWidth = userInfo["selectionWidth"] as? CGFloat,
          let selectionHeight = userInfo["selectionHeight"] as? CGFloat
        else { return }

        // Compute picker position below the highlighted text
        let windowHeight =
          userInfo["windowHeight"] as? CGFloat
          ?? NSApp.keyWindow?.contentView?.bounds.height ?? 800
        let selTopFromTop = max(0, windowHeight - (selectionWindowY + selectionHeight))
        let selBottomFromTop = selTopFromTop + selectionHeight

        highlightPickerOffset = CGPoint(
          x: selectionWindowX + selectionWidth / 2,
          y: selBottomFromTop
        )

        // Store the range for re-coloring via notification
        if let rangeValue = userInfo["charRange"] as? NSValue {
          NotificationCenter.default.post(
            name: .setHighlightEditRange,
            object: nil,
            userInfo: ["range": rangeValue, "editorInstanceID": editorInstanceID]
          )
        }

        // Show remove button only when opened from clicking on existing highlight
        withAnimation(.jotSmoothFast) { showHighlightColorPicker = true }
      }
  }

  // Search results + menu/picker observers — split to reduce type-checker pressure
  private var noteContentEvents2: some View {
    noteContentEvents
      .onReceive(NotificationCenter.default.publisher(for: .propertiesPanelToggleTodo)) {
        notification in
        handlePropertiesPanelToggleTodo(notification)
      }
      .onReceive(NotificationCenter.default.publisher(for: .searchOnPageResults)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID,
          nid != editorInstanceID
        {
          return
        }
        guard let ranges = notification.userInfo?["ranges"] as? [NSRange] else { return }
        searchOnPageMatches = ranges
        if searchOnPageCurrentIndex >= ranges.count {
          searchOnPageCurrentIndex = max(0, ranges.count - 1)
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .showCommandMenu)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        DispatchQueue.main.async {
          if let info = notification.object as? [String: Any],
            let needsSpace = info["needsSpace"] as? Bool
          {
            withAnimation(.easeOut(duration: 0.2)) {
              self.commandMenuNeedsSpace = needsSpace
            }
          }
          self.popupMenuActive = true
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .hideCommandMenu)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        DispatchQueue.main.async {
          withAnimation(.easeOut(duration: 0.15)) {
            self.commandMenuNeedsSpace = false
          }
          self.popupMenuActive = false
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .showNotePicker)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        DispatchQueue.main.async {
          self.popupMenuActive = true
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .hideNotePicker)) { notification in
        if let nid = notification.userInfo?["editorInstanceID"] as? UUID, nid != editorInstanceID {
          return
        }
        DispatchQueue.main.async {
          self.popupMenuActive = false
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .textSelectionChanged)) { notification in
        handleTextSelectionChanged(notification)
      }
  }

  // MARK: - Extracted Overlays (reduce type-checker pressure on noteContent)

  @ViewBuilder
  private var editContentPanelOverlay: some View {
    Group {
      if showEditContentPanel {
        GeometryReader { geometry in
          let horizontalInset: CGFloat = 16
          let panelWidth = geometry.size.width - horizontalInset * 2
          let bottomPadding: CGFloat = 52

          VStack {
            Spacer()
            EditContentFloatingPanel(
              state: aiPanelState,
              onReplace: { applyEditContentReplacement() },
              onDismiss: {
                aiCaptureIsCardOrigin = false
                withAnimation(.jotSpring) {
                  showEditContentPanel = false
                  aiPanelState = .none
                }
              },
              onRedo: { redoEditContent() }
            )
            .frame(width: panelWidth)
            .padding(.bottom, bottomPadding)
          }
          .frame(maxWidth: .infinity)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(150)
        }
      }
    }
    .allowsHitTesting(showEditContentPanel)
  }

  @ViewBuilder
  private var translatePanelOverlay: some View {
    Group {
      if showTranslatePanel {
        GeometryReader { geometry in
          let horizontalInset: CGFloat = 16
          let panelWidth = geometry.size.width - horizontalInset * 2
          let bottomPadding: CGFloat = 52

          VStack {
            Spacer()
            TranslateFloatingPanel(
              state: aiPanelState,
              onReplace: { applyTranslateReplacement() },
              onCopy: { copyTranslation() },
              onDismiss: {
                aiCaptureIsCardOrigin = false
                withAnimation(.jotSpring) {
                  showTranslatePanel = false
                  aiPanelState = .none
                }
              },
              onRetranslate: { retranslate() }
            )
            .frame(width: panelWidth)
            .padding(.bottom, bottomPadding)
          }
          .frame(maxWidth: .infinity)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(150)
        }
      }
    }
    .allowsHitTesting(showTranslatePanel)
  }

  @ViewBuilder
  private var textGenFloatingOverlay: some View {
    Group {
      if showTextGenPanel {
        GeometryReader { geometry in
          let horizontalInset: CGFloat = 16
          let panelWidth = geometry.size.width - horizontalInset * 2
          let bottomPadding: CGFloat = 52

          VStack {
            Spacer()
            TextGenFloatingPanel(
              state: aiPanelState,
              onAccept: { acceptTextGeneration() },
              onDismiss: { dismissTextGeneration() }
            )
            .frame(width: panelWidth)
            .padding(.bottom, bottomPadding)
          }
          .frame(maxWidth: .infinity)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(150)
        }
      }
    }
    .allowsHitTesting(showTextGenPanel)
  }

  @ViewBuilder
  private var meetingNotesFloatingOverlay: some View {
    ZStack {
      if showMeetingPanel {
        VStack {
          Spacer()
          MeetingNotesFloatingPanel(
            transcriptionService: meetingRecorderManager.transcriptionService,
            recordingState: meetingRecorderManager.recordingState,
            duration: meetingRecorderManager.duration,
            audioLevels: meetingRecorderManager.levels,
            summaryResult: meetingRecorderManager.summaryResult,
            isSummaryLoading: meetingRecorderManager.isSummaryLoading,
            manualNotes: meetingRecorderManager.bindingManualNotes,
            selectedTab: meetingRecorderManager.bindingSelectedTab,
            onPause: { pauseMeetingRecording() },
            onResume: { resumeMeetingRecording() },
            onStop: { stopMeetingRecording() },
            onSave: { saveMeetingNote() },
            onDismiss: { dismissMeetingPanel() }
          )
          .padding(.bottom, 52)
        }
        .frame(maxWidth: .infinity)
        // Mirrors `MeetingNotesFloatingPanelTransitionModifier` phases so motion matches
        // the design (rise from below, scale from bottom) without relying on insertion
        // transitions that were being skipped in this overlay chain.
        .scaleEffect(meetingPanelEntranceRevealed ? 1 : 0.91, anchor: .bottom)
        .offset(y: meetingPanelEntranceRevealed ? 0 : 48)
        .opacity(meetingPanelEntranceRevealed ? 1 : 0)
        .zIndex(160)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(showMeetingPanel)
    .onChange(of: showMeetingPanel) { _, new in
      if new {
        // One frame at the "offscreen" pose, then animate on the next run loop so the
        // transaction is not merged with `MeetingRecorderManager` bulk updates.
        meetingPanelEntranceRevealed = false
        DispatchQueue.main.async {
          withAnimation(.jotMeetingPanelPresent) {
            meetingPanelEntranceRevealed = true
          }
        }
      } else {
        meetingPanelEntranceRevealed = false
      }
    }
  }

  @ViewBuilder
  private var floatingToolbarOverlay: some View {
    Group {
      if showFloatingToolbar && !anyAIPanelVisible {
        GeometryReader { geometry in
          let parentFrame = geometry.frame(in: .global)
          let localX = floatingToolbarOffset.x - parentFrame.minX
          let localY = floatingToolbarOffset.y - parentFrame.minY
          let toolbarWidth: CGFloat = measuredToolbarWidth
          let toolbarHeight: CGFloat = measuredToolbarHeight
          let paneWidth: CGFloat = geometry.size.width
          let edgeInset: CGFloat = 12
          // Clamp by left edge — immune to measuredToolbarWidth being stale
          // because the left edge position doesn't depend on toolbar width.
          let clampedLeft: CGFloat = {
            let maxLeft = max(edgeInset, paneWidth - toolbarWidth - edgeInset)
            return min(max(localX, edgeInset), maxLeft)
          }()
          let clampedCenterX: CGFloat = clampedLeft + toolbarWidth / 2
          let centerY: CGFloat = localY + toolbarHeight / 2

          FloatingEditToolbar(
            isBoldActive: toolbarIsBold,
            isItalicActive: toolbarIsItalic,
            isUnderlineActive: toolbarIsUnderline,
            isStrikethroughActive: toolbarIsStrikethrough,
            isHighlightActive: toolbarIsHighlight,
            currentHeadingLevel: toolbarHeadingLevel,
            currentFontSize: toolbarFontSize,
            currentFontFamily: toolbarFontFamily,
            currentTextColorHex: toolbarTextColorHex,
            isAIAvailable: AppleIntelligenceService.shared.isAvailable,
            activeSubmenu: $activeToolbarSubmenu,
            onToolAction: handleEditToolAction,
            onFontSizeSelected: { [editorInstanceID] size in
              NotificationCenter.default.post(
                name: .applyFontSize, object: nil,
                userInfo: ["size": size, "editorInstanceID": editorInstanceID]
              )
            },
            onFontFamilySelected: { [editorInstanceID] style in
              NotificationCenter.default.post(
                name: .applyFontFamily, object: nil,
                userInfo: ["style": style.rawValue, "editorInstanceID": editorInstanceID]
              )
            },
            onColorSelected: { [editorInstanceID] hex in
              NotificationCenter.default.post(
                name: .applyTextColor, object: nil,
                userInfo: ["hex": hex, "editorInstanceID": editorInstanceID]
              )
            },
            onColorRemoved: { [editorInstanceID] in
              NotificationCenter.default.post(
                name: .removeTextColor, object: nil,
                userInfo: ["editorInstanceID": editorInstanceID]
              )
            }
          )
          .onPreferenceChange(ToolbarWidthKey.self) { width in
            if abs(measuredToolbarWidth - width) > 1 {
              measuredToolbarWidth = width
            }
          }
          .onPreferenceChange(ToolbarHeightKey.self) { height in
            if abs(measuredToolbarHeight - height) > 1 {
              measuredToolbarHeight = height
            }
          }
          .onPreferenceChange(PillOffsetKey.self) { offsets in
            pillOffsets = offsets
          }
          .fixedSize()
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .offset(x: clampedLeft, y: localY)
          .opacity(measuredToolbarWidth > 0 ? 1 : 0)
          .transition(.scale(scale: 0.9).combined(with: .opacity))
          .zIndex(101)

          // Submenus — below toolbar if space, above if clipped
          if let submenu = activeToolbarSubmenu {
            let submenuGap: CGFloat = 8
            let submenuMaxWidth: CGFloat = {
              switch submenu {
              case .textOptions: return 170
              case .color: return 186
              case .fontFamily: return 140
              case .translate: return 200
              case .editContent: return 220
              default: return 120
              }
            }()
            // Use measured height if available, otherwise estimate for initial layout
            let submenuH: CGFloat =
              measuredSubmenuHeight > 0
              ? measuredSubmenuHeight
              : {
                switch submenu {
                case .textOptions: return 340.0
                case .fontSize: return 290.0
                case .fontFamily: return 95.0
                case .translate: return 100.0
                case .editContent: return 100.0
                default: return 36.0
                }
              }()
            let paneHeight = geometry.size.height
            let toolbarBottom = centerY + toolbarHeight / 2
            let toolbarTop = centerY - toolbarHeight / 2
            // Check if submenu fits below
            let fitsBelow = toolbarBottom + submenuGap + submenuH < paneHeight - 10
            let submenuTopY =
              fitsBelow
              ? toolbarBottom + submenuGap
              : max(4, toolbarTop - submenuGap - submenuH)
            let toolbarLeftEdge = clampedCenterX - toolbarWidth / 2
            let pillMidX = pillOffsets[submenu] ?? toolbarWidth / 2
            let submenuLeftX: CGFloat = min(
              max(toolbarLeftEdge + pillMidX - submenuMaxWidth / 2, edgeInset),
              paneWidth - submenuMaxWidth - edgeInset)

            Group {
              switch submenu {
              case .textOptions:
                TextOptionsSubmenu(
                  isBoldActive: toolbarIsBold,
                  isItalicActive: toolbarIsItalic,
                  isUnderlineActive: toolbarIsUnderline,
                  isStrikethroughActive: toolbarIsStrikethrough,
                  onToolAction: handleEditToolAction,
                  onDismiss: {
                    withAnimation(.spring(duration: 0.2)) { activeToolbarSubmenu = nil }
                  }
                )
              case .fontSize:
                FontSizeSubmenu(
                  currentSize: toolbarFontSize,
                  onSizeSelected: { [editorInstanceID] size in
                    NotificationCenter.default.post(
                      name: .applyFontSize, object: nil,
                      userInfo: ["size": size, "editorInstanceID": editorInstanceID]
                    )
                    toolbarFontSize = size
                  },
                  onDismiss: {
                    withAnimation(.spring(duration: 0.2)) { activeToolbarSubmenu = nil }
                  }
                )
              case .fontFamily:
                FontFamilySubmenu(
                  currentFamily: toolbarFontFamily,
                  onFamilySelected: { [editorInstanceID] style in
                    NotificationCenter.default.post(
                      name: .applyFontFamily, object: nil,
                      userInfo: ["style": style.rawValue, "editorInstanceID": editorInstanceID]
                    )
                    toolbarFontFamily = style.rawValue
                  },
                  onDismiss: {
                    withAnimation(.spring(duration: 0.2)) { activeToolbarSubmenu = nil }
                  }
                )
              case .color:
                FloatingColorPicker(
                  onColorSelected: { [editorInstanceID] hex in
                    NotificationCenter.default.post(
                      name: .applyTextColor, object: nil,
                      userInfo: ["hex": hex, "editorInstanceID": editorInstanceID]
                    )
                    toolbarTextColorHex = hex
                  },
                  onRemove: { [editorInstanceID] in
                    NotificationCenter.default.post(
                      name: .removeTextColor, object: nil,
                      userInfo: ["editorInstanceID": editorInstanceID]
                    )
                    toolbarTextColorHex = nil
                    withAnimation(.spring(duration: 0.2)) { activeToolbarSubmenu = nil }
                  }
                )
              case .translate:
                TranslateInputSubmenu(
                  onSubmit: { [editorInstanceID] language in
                    NotificationCenter.default.post(
                      name: .aiTranslateSubmit, object: language,
                      userInfo: ["editorInstanceID": editorInstanceID as Any]
                    )
                    withAnimation(.spring(duration: 0.2)) { activeToolbarSubmenu = nil }
                  },
                  onDismiss: {
                    withAnimation(.spring(duration: 0.2)) { activeToolbarSubmenu = nil }
                  }
                )
              case .editContent:
                EditContentInputSubmenu(
                  onSubmit: { [editorInstanceID] instruction in
                    NotificationCenter.default.post(
                      name: .aiEditSubmit, object: instruction,
                      userInfo: ["editorInstanceID": editorInstanceID as Any]
                    )
                    withAnimation(.spring(duration: 0.2)) { activeToolbarSubmenu = nil }
                  },
                  onDismiss: {
                    withAnimation(.spring(duration: 0.2)) { activeToolbarSubmenu = nil }
                  }
                )
              }
            }
            .fixedSize()
            .background(
              GeometryReader { submenuGeo in
                Color.clear.onAppear {
                  measuredSubmenuHeight = submenuGeo.size.height
                }
                .onChange(of: submenuGeo.size.height) { _, newH in
                  measuredSubmenuHeight = newH
                }
              }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: submenuLeftX, y: submenuTopY)
            .zIndex(10000)
            .onChange(of: activeToolbarSubmenu) { _, _ in
              measuredSubmenuHeight = 0
            }
          }
        }
      }
    }
    .onChange(of: activeToolbarSubmenu) { _, newValue in
      // Capture selection eagerly when an AI submenu opens,
      // eliminating the race between request-selection and submit.
      // Must live on an always-in-tree element (Group), not inside
      // the conditional submenu block (which doesn't exist on first transition).
      if newValue == .translate || newValue == .editContent {
        NotificationCenter.default.post(
          name: .aiEditRequestSelection, object: nil,
          userInfo: ["editorInstanceID": editorInstanceID as Any]
        )
      }
    }
  }

  @ViewBuilder
  private var highlightColorPickerOverlay: some View {
    if showHighlightColorPicker {
      GeometryReader { geometry in
        // Full-screen tap target for click-outside dismissal
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.smooth(duration: 0.15)) {
              showHighlightColorPicker = false
            }
          }

        let parentFrame = geometry.frame(in: .global)
        let localX = highlightPickerOffset.x - parentFrame.minX
        let localY = highlightPickerOffset.y - parentFrame.minY
        let pickerWidth: CGFloat = 186
        let paneWidth = geometry.size.width
        let edgeInset: CGFloat = 12
        let gap: CGFloat = 8
        let pickerHeight: CGFloat = 36
        // highlightPickerOffset.x is selection center, .y is selection bottom
        let centerX = min(
          max(localX, pickerWidth / 2 + edgeInset),
          paneWidth - pickerWidth / 2 - edgeInset
        )
        let centerY = localY + gap + pickerHeight / 2

        FloatingColorPicker(
          onColorSelected: { [editorInstanceID] hex in
            NotificationCenter.default.post(
              name: .applyHighlightColor, object: nil,
              userInfo: ["hex": hex, "editorInstanceID": editorInstanceID]
            )
          },
          onRemove: { [editorInstanceID] in
            NotificationCenter.default.post(
              name: .removeHighlightColor, object: nil,
              userInfo: ["editorInstanceID": editorInstanceID]
            )
            withAnimation(.smooth(duration: 0.15)) {
              showHighlightColorPicker = false
            }
          }
        )
        .position(x: centerX, y: centerY)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .zIndex(101)
      }
    }
  }

  // MARK: - Notification Handlers (extracted to reduce type-checker pressure)

  private func handleTextSelectionChanged(_ notification: Notification) {
    DispatchQueue.main.async {
      guard let userInfo = notification.userInfo,
        let hasSelection = userInfo["hasSelection"] as? Bool
      else { return }

      // If this notification is from a different pane, dismiss our toolbar
      if let notifID = userInfo["editorInstanceID"] as? UUID,
        notifID != self.editorInstanceID
      {
        if hasSelection {
          withAnimation(.smooth(duration: 0.15)) { self.showFloatingToolbar = false }
        }
        return
      }

      if hasSelection,
        let selectionWidth = userInfo["selectionWidth"] as? CGFloat,
        let selectionHeight = userInfo["selectionHeight"] as? CGFloat,
        let selectionWindowY = userInfo["selectionWindowY"] as? CGFloat,
        let selectionWindowX = userInfo["selectionWindowX"] as? CGFloat,
        let visibleWidth = userInfo["visibleWidth"] as? CGFloat,
        let visibleHeight = userInfo["visibleHeight"] as? CGFloat
      {

        let result = FloatingToolbarPositioner.calculatePosition(
          selectionWindowX: selectionWindowX,
          selectionWindowY: selectionWindowY,
          selectionWidth: selectionWidth,
          selectionHeight: selectionHeight,
          visibleWidth: visibleWidth,
          visibleHeight: visibleHeight,
          toolbarWidth: self.measuredToolbarWidth
        )

        // Save selection bottom position for highlight picker
        let windowHeight =
          userInfo["windowHeight"] as? CGFloat
          ?? NSApp.keyWindow?.contentView?.bounds.height ?? visibleHeight
        let selTopFromTop = max(0, windowHeight - (selectionWindowY + selectionHeight))
        self.lastSelectionBottomY = selTopFromTop + selectionHeight
        self.lastSelectionCenterX = selectionWindowX + selectionWidth / 2

        // Update formatting state for toolbar button highlights
        self.toolbarIsBold = userInfo["isBold"] as? Bool ?? false
        self.toolbarIsItalic = userInfo["isItalic"] as? Bool ?? false
        self.toolbarIsUnderline = userInfo["isUnderline"] as? Bool ?? false
        self.toolbarIsStrikethrough = userInfo["isStrikethrough"] as? Bool ?? false
        self.toolbarIsHighlight = userInfo["isHighlight"] as? Bool ?? false
        if let hl = userInfo["headingLevel"] as? TextFormattingManager.HeadingLevel {
          switch hl {
          case .none: self.toolbarHeadingLevel = 0
          case .h1: self.toolbarHeadingLevel = 1
          case .h2: self.toolbarHeadingLevel = 2
          case .h3: self.toolbarHeadingLevel = 3
          }
        } else {
          self.toolbarHeadingLevel = 0
        }
        self.toolbarFontSize = userInfo["fontSize"] as? CGFloat ?? 16
        self.toolbarFontFamily = userInfo["fontFamily"] as? String ?? "default"
        self.toolbarTextColorHex = userInfo["textColorHex"] as? String

        withAnimation(.jotSmoothFast) {
          self.floatingToolbarOffset = result.origin
          self.floatingToolbarPlaceAbove = result.placeAbove
          self.showFloatingToolbar = true
        }

        // Dismiss highlight picker when toolbar reappears
        if self.showHighlightColorPicker {
          withAnimation(.smooth(duration: 0.15)) {
            self.showHighlightColorPicker = false
          }
        }
      } else {
        withAnimation(.smooth(duration: 0.15)) {
          self.showFloatingToolbar = false
          self.activeToolbarSubmenu = nil
        }
      }
    }
  }

  private func handlePropertiesPanelToggleTodo(_ notification: Notification) {
    guard let targetID = notification.object as? UUID, targetID == editorInstanceID,
      let lineIndex = notification.userInfo?["lineIndex"] as? Int
    else { return }
    var lines = editedContent.components(separatedBy: "\n")
    guard lineIndex < lines.count else { return }
    let line = lines[lineIndex]
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("[x]") {
      lines[lineIndex] = line.replacingOccurrences(
        of: "[x]", with: "[ ]", range: line.range(of: "[x]"))
    } else if trimmed.hasPrefix("[ ]") {
      lines[lineIndex] = line.replacingOccurrences(
        of: "[ ]", with: "[x]", range: line.range(of: "[ ]"))
    }
    editedContent = lines.joined(separator: "\n")
    scheduleAutosave()
  }

  private func handleNoteToolsBarNotification(_ notification: Notification) {
    if let notifID = notification.userInfo?["editorInstanceID"] as? UUID {
      guard notifID == self.editorInstanceID else { return }
    }
    if let rawValue = notification.object as? String,
      let tool = EditTool(rawValue: rawValue)
    {
      handleEditToolAction(tool)
    }
  }

  // MARK: - Computed Properties

  private var noteDateString: String {
    Self.dateFormatter.string(from: note.date)
  }

  var shouldShowTopPanel: Bool {
    switch aiPanelState {
    case .loading(let tool):
      return tool == .summary || tool == .keyPoints
    default: return false
    }
  }

  private var anyAIPanelVisible: Bool {
    showEditContentPanel || showTranslatePanel || showTextGenPanel || showMeetingPanel
  }

  private var isNewNote: Bool {
    let hasMinimalTitle =
      editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || editedTitle == "Untitled" || editedTitle == "Note Title"
      || editedTitle == "New Note"
    let hasMinimalContent = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    return hasMinimalTitle && hasMinimalContent
  }

  // MARK: - Title

  private var titleField: some View {
    TextField("Note Title", text: $editedTitle, axis: .vertical)
      .font(FontManager.noteDetailTitleFont())
      .foregroundColor(Color("PrimaryTextColor"))
      .textFieldStyle(.plain)
      .lineLimit(nil)
      .fixedSize(horizontal: false, vertical: true)
      .focused($titleFocused)
      .onKeyPress(.return) {
        titleFocused = false
        localEditorFocusID = UUID()
        return .handled
      }
      .padding(.top, 4)
  }

  // MARK: - Tags

  // MARK: - Header Styling Helpers

  private var detailTranslucency: Double {
    min(1, max(0, themeManager.detailPaneTranslucency))
  }

  /// Sticky title strip + bottom scroll fade.
  /// - Reduce Transparency / opaque pane: solid `tintedPaneSurface` (paper) under the mask.
  /// - Translucent pane: **blur-only** chrome — no tinted paper crossfade, so the strip does not reintroduce
  ///   the cream/dark wash on top of neutral Liquid Glass (Real Detail Transparency plan).
  @ViewBuilder
  private func maskedStickyChromeFade(mask: LinearGradient) -> some View {
    let paper = themeManager.tintedPaneSurface(for: colorScheme)
    if reduceTransparency || detailTranslucency < 0.001 {
      Rectangle()
        .fill(paper)
        .mask(mask)
    } else {
      // Localized material reads as frosted chrome; avoids `.regularMaterial` milkiness on macOS 26+ glass panes.
      Rectangle()
        .fill(Color.clear)
        .background(.ultraThinMaterial)
        .mask(mask)
    }
  }

  private static let headerMaskGradient: LinearGradient = {
    // Perlin smootherstep (6t^5 - 15t^4 + 10t^3) -- zero 1st+2nd derivatives at endpoints.
    let steps = 40
    let stops: [Gradient.Stop] = (0...steps).map { i in
      let t = Double(i) / Double(steps)
      let eased = 1.0 - (t * t * t * (t * (t * 6 - 15) + 10))
      return .init(color: Color.white.opacity(eased), location: t)
    }
    return LinearGradient(gradient: Gradient(stops: stops), startPoint: .top, endPoint: .bottom)
  }()

  private static let footerMaskGradient: LinearGradient = {
    let steps = 40
    let stops: [Gradient.Stop] = (0...steps).map { i in
      let t = Double(i) / Double(steps)
      let eased = t * t * t * (t * (t * 6 - 15) + 10)
      return .init(color: Color.white.opacity(eased), location: t)
    }
    return LinearGradient(gradient: Gradient(stops: stops), startPoint: .top, endPoint: .bottom)
  }()

  // MARK: - Bottom Overlay

  @ViewBuilder
  private var bottomOverlay: some View {
    let proofreadAnnotations: [ProofreadAnnotation]? = {
      if case .proofread(let a) = aiPanelState { return a }
      return nil
    }()
    let showProofreadLoading: Bool = {
      if case .loading(.proofread) = aiPanelState { return true }
      return false
    }()
    let showProofreadSuggestions = !(proofreadAnnotations?.isEmpty ?? true)
    let showProofreadSuccess = proofreadAnnotations?.isEmpty == true
    let showAIError: Bool = {
      if case .error = aiPanelState { return true }
      return false
    }()
    let showAnyOverlay =
      showVoiceRecorderOverlay || showLinkInputOverlay
      || showSearchOnPageOverlay || showProofreadLoading
      || showProofreadSuggestions || showProofreadSuccess || showAIError

    if showAnyOverlay {
      VStack(spacing: 12) {
        if showSearchOnPageOverlay {
          HStack {
            Spacer()
            searchOnPagePrompt
              .transition(.move(edge: .bottom).combined(with: .opacity))
            Spacer()
          }
        }

        if showLinkInputOverlay {
          HStack {
            Spacer()
            linkInputPrompt
              .transition(.move(edge: .bottom).combined(with: .opacity))
            Spacer()
          }
        }

        if showVoiceRecorderOverlay {
          HStack {
            Spacer()
            voiceRecorderControl
              .transition(.move(edge: .bottom).combined(with: .opacity))
            Spacer()
          }
        }

        if showProofreadLoading {
          HStack {
            Spacer()
            proofreadLoadingPill
              .transition(.move(edge: .bottom).combined(with: .opacity))
            Spacer()
          }
        }

        if showProofreadSuggestions, let annotations = proofreadAnnotations {
          HStack {
            Spacer()
            proofreadSuggestionsBar(annotations: annotations)
              .transition(.move(edge: .bottom).combined(with: .opacity))
            Spacer()
          }
        }

        if showProofreadSuccess {
          HStack {
            Spacer()
            looksGoodPill
              .transition(.move(edge: .bottom).combined(with: .opacity))
            Spacer()
          }
        }

        if showAIError, case .error(let errorMessage) = aiPanelState {
          HStack {
            Spacer()
            aiErrorPill(message: errorMessage)
              .transition(.move(edge: .bottom).combined(with: .opacity))
            Spacer()
          }
        }
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 56)
      .animation(.jotSpring, value: showVoiceRecorderOverlay)
      .animation(.jotSpring, value: showLinkInputOverlay)
      .animation(.jotSpring, value: showSearchOnPageOverlay)
      .animation(.jotSpring, value: showProofreadLoading)
      .animation(.jotSpring, value: showProofreadSuggestions)
      .animation(.jotSpring, value: showProofreadSuccess)
      .animation(.jotSpring, value: showAIError)
    }
  }

  private var proofreadLoadingPill: some View {
    HStack(spacing: 8) {
      BrailleLoader(pattern: .snake, size: 11)
      Text("Proofreading...")
        .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .medium))
        .foregroundColor(Color("PrimaryTextColor"))
        .shimmering(active: true)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .liquidGlass(in: Capsule())
  }

  private func aiErrorPill(message: String) -> some View {
    HStack(spacing: 8) {
      Text(message)
        .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .medium))
        .foregroundColor(Color.red.opacity(0.8))
        .lineLimit(1)

      Button(action: {
        withAnimation(.jotSpring) { aiPanelState = .none }
      }) {
        Image("IconXMark")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .foregroundColor(Color("SecondaryTextColor"))
          .frame(width: 15, height: 15)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .liquidGlass(in: RoundedRectangle(cornerRadius: 100, style: .continuous))
  }

  private func proofreadSuggestionsBar(annotations: [ProofreadAnnotation]) -> some View {
    let count = annotations.count
    let clampedIndex = count > 0 ? min(currentProofreadIndex, count - 1) : 0
    let current = count > 0 ? annotations[clampedIndex] : nil

    return VStack(alignment: .leading, spacing: 8) {
      if let current {
        HStack(spacing: 8) {
          Text(current.original)
            .strikethrough()
            .font(FontManager.body(size: 16, weight: .regular))
            .foregroundColor(Color("SecondaryTextColor"))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              Color("SecondaryBackgroundColor"),
              in: RoundedRectangle(cornerRadius: 10, style: .continuous))

          Text(current.replacement)
            .font(FontManager.body(size: 16, weight: .regular))
            .foregroundColor(Color("PrimaryTextColor"))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              Color("SecondaryBackgroundColor"),
              in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 8) {
        if count > 1 {
          Text("\(clampedIndex + 1)/\(count)")
            .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .medium).monospacedDigit())
            .foregroundColor(Color("SecondaryTextColor"))
            .padding(.leading, 8)

          Button {
            navigateToPrevProofreadSuggestion()
          } label: {
            Image("IconChevronTopSmall")
              .renderingMode(.template)
              .resizable().scaledToFit()
              .frame(width: 15, height: 15)
          }
          .foregroundColor(Color("SecondaryTextColor"))
          .buttonStyle(.plain)
          .macPointingHandCursor()
          .subtleHoverScale(1.04)

          Button {
            navigateToNextProofreadSuggestion()
          } label: {
            Image("IconChevronDownSmall")
              .renderingMode(.template)
              .resizable().scaledToFit()
              .frame(width: 15, height: 15)
          }
          .foregroundColor(Color("SecondaryTextColor"))
          .buttonStyle(.plain)
          .macPointingHandCursor()
          .subtleHoverScale(1.04)
        }

        Spacer()

        Button("Done") {
          NotificationCenter.default.post(
            name: .aiProofreadClearOverlays, object: nil,
            userInfo: ["editorInstanceID": editorInstanceID])
          withAnimation(.jotSpring) { aiPanelState = .none }
        }
        .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .regular))
        .foregroundColor(Color("SecondaryTextColor"))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .liquidGlass(in: Capsule())
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .subtleHoverScale(1.04)

        Button("Replace All") {
          replaceAllSuggestions()
        }
        .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.accentColor, in: Capsule())
        .buttonStyle(.plain)
        .macPointingHandCursor()
        .subtleHoverScale(1.04)
      }
    }
    .padding(8)
    .frame(maxWidth: 360)
    .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var looksGoodPill: some View {
    HStack(spacing: 6) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
        .font(.system(size: 14))
      Text("Looks good")
        .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .medium))
        .foregroundColor(Color("PrimaryTextColor"))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .liquidGlass(in: Capsule())
    .task {
      try? await Task.sleep(for: .seconds(3))
      withAnimation(.jotSpring) { aiPanelState = .none }
    }
  }

  private var voiceRecorderControl: some View {
    MicCaptureControl(
      onSend: { result in
        processVoiceRecorderResult(result)
      },
      onCancel: {
        dismissVoiceRecorderOverlay()
      },
      autoStart: true
    )
  }

  private var linkInputPrompt: some View {
    HStack(spacing: 8) {
      Image("insert link")
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 15, height: 15)
        .foregroundColor(Color("SecondaryTextColor"))

      TextField("Enter URL", text: $linkInputText)
        .textFieldStyle(.plain)
        .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .medium))
        .foregroundColor(Color("PrimaryTextColor"))
        .focused($isLinkInputFocused)
        .submitLabel(.done)
        .onSubmit(submitLink)

      Button(action: submitLink) {
        Image(systemName: "arrow.right.circle.fill")
          .font(FontManager.heading(size: FontManager.noteDetailAuxiliaryHeadingSize, weight: .regular))
          .foregroundColor(
            linkInputText.isEmpty ? Color("SecondaryTextColor") : Color("AccentColor"))
      }
      .buttonStyle(.plain)
      .macPointingHandCursor()
      .disabled(linkInputText.isEmpty)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .liquidGlass(in: Capsule())
    .frame(maxWidth: 200)
    .onExitCommand {
      hideLinkInputOverlay()
    }
  }

  // MARK: - Search on Page Overlay

  private var searchCountLabel: String {
    guard !searchOnPageMatches.isEmpty else {
      return "0/0"
    }
    return "\(searchOnPageCurrentIndex + 1)/\(searchOnPageMatches.count)"
  }

  private var searchOnPagePrompt: some View {
    VStack(spacing: 0) {
      // Find row
      HStack(spacing: 8) {
        Text(searchCountLabel)
          .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .medium))
          .foregroundColor(Color("SecondaryTextColor"))
          .monospacedDigit()
          .frame(minWidth: 28, alignment: .trailing)

        TextField("Search", text: $searchOnPageQuery)
          .textFieldStyle(.plain)
          .font(FontManager.heading(size: FontManager.noteDetailOverlayHeadingSize, weight: .medium))
          .foregroundColor(Color("PrimaryTextColor"))
          .focused($isSearchOnPageFocused)
          .onChange(of: searchOnPageQuery) { _, newValue in
            performInNoteSearch(newValue)
          }
          .onSubmit { navigateToNextMatch() }

        HStack(spacing: 4) {
          Button(action: navigateToPreviousMatch) {
            Image("IconChevronTopSmall")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 15, height: 15)
              .foregroundColor(Color("SecondaryTextColor"))
          }
          .buttonStyle(.plain)
          .disabled(searchOnPageMatches.isEmpty)

          Button(action: navigateToNextMatch) {
            Image("IconChevronDownSmall")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 15, height: 15)
              .foregroundColor(Color("SecondaryTextColor"))
          }
          .buttonStyle(.plain)
          .disabled(searchOnPageMatches.isEmpty)

        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .liquidGlass(in: RoundedRectangle(cornerRadius: 100, style: .continuous))
    .frame(maxWidth: 240)
    .onExitCommand {
      dismissSearchOnPage()
    }
  }

  // MARK: - AI Block Persistence

  /// Sentinel tag that delimits AI-generated metadata appended to note content.
  private static let aiBlockStart = "\n[[ai-block]]"
  private static let aiBlockEnd = "[[/ai-block]]"

  /// Strips the `[[ai-block]]...[[/ai-block]]` from a content string and returns
  /// the clean content plus any extracted AI summary and key points.
  static func stripAIBlock(_ content: String) -> (
    content: String, summary: String?, keyPoints: [String]?
  ) {
    guard let startRange = content.range(of: "\n[[ai-block]]") ?? content.range(of: "[[ai-block]]")
    else {
      return (content, nil, nil)
    }
    let cleanContent = String(content[content.startIndex..<startRange.lowerBound])
    let aiSection = String(content[startRange.upperBound...])

    var summary: String?
    var keyPoints: [String]?

    // Extract summary
    if let sStart = aiSection.range(of: "[[ai-summary]]"),
      let sEnd = aiSection.range(of: "[[/ai-summary]]")
    {
      summary = String(aiSection[sStart.upperBound..<sEnd.lowerBound])
      if summary?.isEmpty == true { summary = nil }
    }

    // Extract key points (newline-separated, with \n escape handling)
    if let kStart = aiSection.range(of: "[[ai-keypoints]]"),
      let kEnd = aiSection.range(of: "[[/ai-keypoints]]")
    {
      let raw = String(aiSection[kStart.upperBound..<kEnd.lowerBound])
      let items = raw.components(separatedBy: "\n")
        .map { $0.replacingOccurrences(of: "\\n", with: "\n") }
        .filter { !$0.isEmpty }
      if !items.isEmpty { keyPoints = items }
    }

    return (cleanContent, summary, keyPoints)
  }

  /// Builds the AI block string to append to note content for persistence.
  static func buildAIBlock(summary: String?, keyPoints: [String]?) -> String {
    guard summary != nil || keyPoints != nil else { return "" }
    var block = Self.aiBlockStart + "\n"
    if let summary = summary {
      block += "[[ai-summary]]\(summary)[[/ai-summary]]\n"
    }
    if let keyPoints = keyPoints, !keyPoints.isEmpty {
      let escaped = keyPoints.map { $0.replacingOccurrences(of: "\n", with: "\\n") }
      block += "[[ai-keypoints]]\(escaped.joined(separator: "\n"))[[/ai-keypoints]]\n"
    }
    block += Self.aiBlockEnd
    return block
  }

  // MARK: - Helpers

  private func persistIfNeeded() {
    // Merge AI block into content for persistence
    let contentWithAI =
      editedContent
      + Self.buildAIBlock(
        summary: aiSummaryText, keyPoints: aiKeyPointsItems)

    let snapshot = DraftSnapshot(
      title: editedTitle,
      content: contentWithAI
    )
    let stickersDirty = editedStickers != lastSavedStickers
    guard snapshot != lastSavedSnapshot || stickersDirty else { return }

    var updatedNote = noteForPersist
    updatedNote.title = editedTitle
    updatedNote.content = contentWithAI
    updatedNote.stickers = editedStickers
    updatedNote.date = Date()

    onSave(updatedNote)
    lastSavedSnapshot = snapshot
    lastSavedStickers = editedStickers
  }

  func scheduleAutosave() {
    autosaveWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      persistIfNeeded()
    }
    autosaveWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
  }

  private func insertStickerAtCenter() {
    // Position relative to current scroll viewport, not scroll content top
    let visibleTop = max(
      0, -titleOffset + noteDetailScrollContentTopInset + contentTopInsetAdjustment)
    let x: CGFloat = 80
    let y: CGFloat = visibleTop + 80
    let newSticker = Sticker(
      color: .green,
      text: "",
      positionX: x,
      positionY: y,
      size: 200,
      fontSize: 12,
      textColorDark: true,
      zIndex: (editedStickers.map(\.zIndex).max() ?? 0) + 1
    )
    let previous = editedStickers
    let next = previous + [newSticker]
    stickerUndoController.record(
      oldStickers: previous, newStickers: next, actionName: "Add Sticker")
  }

  private func handleEditToolAction(_ tool: EditTool) {
    if performAuxiliaryToolAction(tool) {
      return
    }
    let eidInfo: [String: Any] = ["editorInstanceID": editorInstanceID]
    switch tool {
    case .todo:
      NotificationCenter.default.post(
        name: .todoToolbarAction, object: nil, userInfo: eidInfo)
    default:
      var info = eidInfo
      info["tool"] = tool.rawValue
      NotificationCenter.default.post(
        name: .applyEditTool, object: nil, userInfo: info)
    }
  }

  @discardableResult
  private func performAuxiliaryToolAction(_ tool: EditTool) -> Bool {
    switch tool {
    case .imageUpload:
      hideLinkInputOverlay()
      openImageFilePanel()
      return true
    case .voiceRecord:
      hideLinkInputOverlay()
      showVoiceRecorderOverlay = true
      return true
    case .link:
      presentLinkInputOverlay()
      return true
    case .convertToWebClip:
      NotificationCenter.default.post(
        name: .convertSelectedTextToWebClip, object: nil,
        userInfo: ["editorInstanceID": editorInstanceID]
      )
      return true
    case .searchOnPage:
      presentSearchOnPage()
      return true
    case .quickLook:
      NotificationCenter.default.post(
        name: .triggerQuickLook, object: nil,
        userInfo: ["editorInstanceID": editorInstanceID]
      )
      return true
    case .fileLink:
      hideLinkInputOverlay()
      showFileLinkPicker = true
      return true
    case .sticker:
      insertStickerAtCenter()
      return true
    case .highlight:
      if toolbarIsHighlight {
        // Toggle off: remove existing highlight from selected text
        NotificationCenter.default.post(
          name: .removeHighlightColor, object: nil,
          userInfo: ["editorInstanceID": editorInstanceID]
        )
        toolbarIsHighlight = false
        return true
      }
      // Reset highlight edit range so initial apply uses lastKnownSelectionRange
      NotificationCenter.default.post(
        name: .setHighlightEditRange, object: nil,
        userInfo: [
          "range": NSValue(range: NSRange(location: NSNotFound, length: 0)),
          "editorInstanceID": editorInstanceID,
        ]
      )
      // Apply default yellow highlight — handler computes layout rect
      // and posts highlightTextClicked with correct position
      NotificationCenter.default.post(
        name: .applyHighlightColor, object: nil,
        userInfo: ["hex": "FFFF00", "editorInstanceID": editorInstanceID]
      )
      // Dismiss floating toolbar — picker show + position handled by highlightTextClicked
      withAnimation(.smooth(duration: 0.15)) {
        showFloatingToolbar = false
        activeToolbarSubmenu = nil
      }
      return true
    default:
      return false
    }
  }
}

// MARK: - Preference Keys

struct TitleOffsetPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

struct BottomOverlayActivePreferenceKey: PreferenceKey {
  static var defaultValue: Bool = false
  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value || nextValue()
  }
}

struct BottomInputOverlayActivePreferenceKey: PreferenceKey {
  static var defaultValue: Bool = false
  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value || nextValue()
  }
}
