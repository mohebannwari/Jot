//
//  TodoEditorRepresentable+OverlayManagement.swift
//  Jot
//
//  Extracted from TodoEditorRepresentable.swift — 1,404 lines of overlay-view lifecycle
//  management for inline attachments (images, tables, callouts, code blocks, tabs, card
//  sections, link cards, file previews, dividers). Each overlay type follows the same
//  pattern: enumerate `.attachment` ranges, sync a dictionary of `attachment → NSView`,
//  update overlay frames on layout, remove stale entries for deleted attachments.
//
//  Lives here as a Coordinator extension — the same pragmatic choice made for the
//  deserializer in Batch 4. A pure `NoteOverlayManager` class per the original plan would
//  require migrating 9 dictionary properties + weak textView + construction/teardown
//  plumbing, with no testability win (overlay behavior requires a real NSTextView
//  hierarchy regardless). The extension approach achieves the primary extraction goal
//  (main-file line reduction) without class-boundary risk.
//
//  Invariants preserved:
//    - `updateDividerAttachments`: width-cache short-circuit (P2) via `lastKnownDividerContainerWidth`.
//    - NSHostingView `containerWidth` set BEFORE `rebuildHostingView()` (memory rule).
//    - File preview overlays: synchronous `updateFilePreviewOverlays` (not async scheduleOverlayUpdate).
//    - Block-level cards use Y=0, not `imageTagVerticalOffset`.
//

import AppKit
import SwiftUI

extension TodoEditorRepresentable.Coordinator {

        func removeAllOverlays() {
            imageOverlays.values.forEach { $0.removeFromSuperview() }
            imageOverlays.removeAll()
            mapOverlays.values.forEach { $0.removeFromSuperview() }
            mapOverlays.removeAll()
            tableOverlays.values.forEach { $0.removeFromSuperview() }
            tableOverlays.removeAll()
            calloutOverlays.values.forEach { $0.removeFromSuperview() }
            calloutOverlays.removeAll()
            codeBlockOverlays.values.forEach { $0.removeFromSuperview() }
            codeBlockOverlays.removeAll()
            tabsOverlays.values.forEach { $0.removeFromSuperview() }
            tabsOverlays.removeAll()
            cardSectionOverlays.values.forEach { $0.removeFromSuperview() }
            cardSectionOverlays.removeAll()
            linkCardOverlays.values.forEach { $0.removeFromSuperview() }
            linkCardOverlays.removeAll()
            linkCardThumbnailLoadAttempted.removeAll()
            filePreviewOverlays.values.forEach { $0.removeFromSuperview() }
            filePreviewOverlays.removeAll()
        }

        func updateImageOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            // Always host overlays on the text view so they use text-view-local
            // coordinates and scroll naturally with content — no conversion needed.
            let hostView: NSView = textView

            if overlayHostView !== hostView {
                imageOverlays.values.forEach { $0.removeFromSuperview() }
                imageOverlays.removeAll()
                overlayHostView = hostView
            }

            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                imageOverlays.values.forEach { $0.removeFromSuperview() }
                imageOverlays.removeAll()
                return
            }

            let containerWidth = textContainer.containerSize.width

            var attachmentCount = 0
            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteImageAttachment else { return }
                attachmentCount += 1
                let filename = attachment.storedFilename
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // ── Recalculate stale attachment bounds ──
                // Bounds may be wrong because:
                //   (a) containerWidth was 0 during makeNSView (replaceLayoutManager resets it)
                //   (b) image wasn't cached at insert time, so a 4:3 fallback AR was used
                // Recalculate whenever width OR aspect ratio diverges from expected values.
                if containerWidth > 1 {
                    let expectedWidth = containerWidth * attachment.widthRatio
                    let aspectRatio: CGFloat
                    let cacheKey = filename as NSString
                    if let cachedImg = Self.inlineImageCache.object(forKey: cacheKey) {
                        aspectRatio = cachedImg.size.height / cachedImg.size.width
                    } else if let overlay = imageOverlays[id], let img = overlay.image {
                        aspectRatio = img.size.height / img.size.width
                    } else {
                        aspectRatio = 3.0 / 4.0
                    }
                    let expectedHeight = expectedWidth * aspectRatio
                    let widthDrift = abs(attachment.bounds.width - expectedWidth)
                    let heightDrift = abs(attachment.bounds.height - expectedHeight)
                    if widthDrift > 1 || heightDrift > 1 {
                        let newSize = CGSize(width: expectedWidth, height: expectedHeight)
                        attachment.attachmentCell = ImageSizeAttachmentCell(size: newSize)
                        attachment.bounds = CGRect(origin: .zero, size: newSize)
                        layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                    }
                }

                // Ensure layout is settled before querying glyph positions.
                // Without this, boundingRect can return stale Y values when
                // called right after styleTodoParagraphs invalidated layout.
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 {
                    layoutManager.ensureLayout(forGlyphRange: glyphRange)
                }

                // Get glyph rect
                guard glyphRange.length > 0 else {
                    return
                }
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: glyphRange, in: textContainer)

                // Position in text-view-local coordinates (host is always the text view)
                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                let ratio = attachment.widthRatio

                // Create or reuse overlay
                let overlay: InlineImageOverlayView
                if let existing = imageOverlays[id] {
                    overlay = existing
                } else {
                    overlay = InlineImageOverlayView(frame: .zero)
                    overlay.storedFilename = filename
                    overlay.containerWidth = containerWidth
                    overlay.currentRatio = ratio
                    overlay.parentTextView = textView

                    overlay.onResizeEnded = { [weak self, weak textStorage, weak textView] newRatio in
                        guard let self = self, let ts = textStorage, let tv = textView else { return }
                        self.updateImageRatio(newRatio, attachment: attachment, in: ts, textView: tv)
                    }

                    // Load image from cache or async
                    let cacheKey = filename as NSString
                    if let cached = Self.inlineImageCache.object(forKey: cacheKey) {
                        overlay.image = cached
                    } else {
                        // Get URL on main actor first
                        guard let url = ImageStorageManager.shared.getImageURL(for: filename) else { return }

                        // Cancel any in-flight load for the same filename before starting a new one.
                        imageLoadTasks[filename]?.cancel()
                        let loadTask = Task.detached(priority: .userInitiated) { [weak self] in
                            guard !Task.isCancelled else { return }
                            guard let img = NSImage(contentsOf: url) else { return }
                            await MainActor.run { [weak self, weak overlay] in
                                guard let self = self, !Task.isCancelled else { return }
                                Self.inlineImageCache.setObject(img, forKey: cacheKey, cost: Int(img.size.width * img.size.height * 4))
                                overlay?.image = img
                                self.imageLoadTasks.removeValue(forKey: filename)
                                self.scheduleOverlayUpdate()
                            }
                        }
                        imageLoadTasks[filename] = loadTask
                    }

                    hostView.addSubview(overlay)
                    imageOverlays[id] = overlay
                }

                overlay.frame = overlayRect.integral
                overlay.containerWidth = containerWidth
            }

            // Remove overlays for deleted attachments
            let toRemove = imageOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemove {
                imageOverlays[key]?.removeFromSuperview()
                imageOverlays.removeValue(forKey: key)
            }
        }

        func updateMapOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            let hostView: NSView = textView
            if overlayHostView !== hostView {
                mapOverlays.values.forEach { $0.removeFromSuperview() }
                mapOverlays.removeAll()
                overlayHostView = hostView
            }

            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                mapOverlays.values.forEach { $0.removeFromSuperview() }
                mapOverlays.removeAll()
                return
            }

            let containerWidth = textContainer.containerSize.width

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
                guard let attachment = value as? NoteMapAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                let expectedWidth = resolvedMapBlockWidth(
                    for: attachment.mapData.widthRatio,
                    containerWidth: max(containerWidth, 1)
                )
                let expectedHeight = expectedWidth * MapBlockData.aspectHeightRatio
                if abs(attachment.bounds.width - expectedWidth) > 1
                    || abs(attachment.bounds.height - expectedHeight) > 1 {
                    let newSize = CGSize(width: expectedWidth, height: expectedHeight)
                    attachment.attachmentCell = MapSizeAttachmentCell(
                        size: newSize,
                        mapData: attachment.mapData
                    )
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    layoutManager.invalidateLayout(
                        forCharacterRange: range,
                        actualCharacterRange: nil
                    )
                }

                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: range,
                    actualCharacterRange: nil
                )
                if glyphRange.length > 0 {
                    layoutManager.ensureLayout(forGlyphRange: glyphRange)
                }
                guard glyphRange.length > 0 else { return }

                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: glyphRange,
                    in: textContainer
                )
                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                let overlay: MapBlockOverlayView
                if let existing = mapOverlays[id] {
                    overlay = existing
                    overlay.mapData = attachment.mapData
                } else {
                    overlay = MapBlockOverlayView(mapData: attachment.mapData)
                    overlay.parentTextView = textView
                    hostView.addSubview(overlay)
                    mapOverlays[id] = overlay
                }

                overlay.frame = overlayRect.integral
                overlay.containerWidth = containerWidth

                if readOnly {
                    overlay.isInteractionEnabled = false
                    overlay.onDataChanged = nil
                } else {
                    overlay.isInteractionEnabled = true
                    overlay.onDataChanged = { [weak self, weak textStorage, weak textView, weak attachment] updatedData in
                        guard let self,
                              let textStorage,
                              let textView,
                              let attachment else { return }
                        self.updateMapData(
                            updatedData,
                            attachment: attachment,
                            in: textStorage,
                            textView: textView
                        )
                    }
                }
            }

            let toRemove = mapOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemove {
                mapOverlays[key]?.removeFromSuperview()
                mapOverlays.removeValue(forKey: key)
            }
        }

        // MARK: - Inline Table Overlay Management

        func updateTableOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            let hostView: NSView = textView

            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                tableOverlays.values.forEach { $0.removeFromSuperview() }
                tableOverlays.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteTableAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // Correct size drift (row/column count may have changed).
                let containerWidth = textContainer.containerSize.width > 0 ? textContainer.containerSize.width : 400
                let expectedWidth = min(attachment.tableData.contentWidth, containerWidth)
                let expectedHeight = NoteTableOverlayView.computeTableHeight(for: attachment.tableData) + 1 + 36  // +36 for add-row button space
                let sizeDrift = abs(attachment.bounds.height - expectedHeight) + abs(attachment.bounds.width - expectedWidth)
                if sizeDrift > 1 {
                    let newSize = CGSize(width: expectedWidth, height: expectedHeight)
                    attachment.attachmentCell = TableSizeAttachmentCell(size: newSize)
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 {
                    layoutManager.ensureLayout(forGlyphRange: glyphRange)
                }

                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                // Create or reuse overlay
                let overlay: NoteTableOverlayView
                if let existing = tableOverlays[id] {
                    overlay = existing
                    overlay.tableData = attachment.tableData
                } else {
                    overlay = NoteTableOverlayView(tableData: attachment.tableData)
                    overlay.parentTextView = textView

                    overlay.onDataChanged = { [weak self, weak textStorage, weak textView, weak attachment] previous, newData, commit in
                        guard let self = self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        let apply: (NoteTableData) -> Void = { data in
                            att.tableData = data
                            let newHeight = NoteTableOverlayView.computeTableHeight(for: data) + 1 + 36  // +36 for add-row button space
                            let containerWidth = tv.textContainer?.containerSize.width ?? 400
                            let newWidth = min(data.contentWidth, containerWidth)
                            let newSize = CGSize(width: newWidth, height: newHeight)
                            att.attachmentCell = TableSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    tv.layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                        }
                        if commit, previous != newData {
                            self.applyMutationWithUndo(
                                textView: tv,
                                actionName: "Edit Table",
                                oldValue: previous,
                                newValue: newData,
                                apply: apply
                            )
                        } else {
                            apply(newData)
                        }
                    }

                    overlay.onColumnDividerDragBegan = { [weak self, weak attachment] in
                        guard let self, let att = attachment, let tv = self.textView else { return }
                        self.pendingTableColumnResizeSnapshot[ObjectIdentifier(att)] = att.tableData
                    }

                    overlay.onDeleteTable = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self = self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                // Delete attachment char and surrounding newlines
                                var deleteStart = charRange.location
                                var deleteEnd = charRange.location + charRange.length
                                let nsString = ts.string as NSString
                                if deleteStart > 0 {
                                    let prev = nsString.character(at: deleteStart - 1)
                                    if let scalar = Unicode.Scalar(prev), CharacterSet.newlines.contains(scalar) {
                                        deleteStart -= 1
                                    }
                                }
                                if deleteEnd < nsString.length {
                                    let next = nsString.character(at: deleteEnd)
                                    if let scalar = Unicode.Scalar(next), CharacterSet.newlines.contains(scalar) {
                                        deleteEnd += 1
                                    }
                                }
                                let deleteRange = NSRange(location: deleteStart, length: deleteEnd - deleteStart)
                                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                                    ts.replaceCharacters(in: deleteRange, with: "")
                                    tv.didChangeText()
                                }
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    hostView.addSubview(overlay)
                    tableOverlays[id] = overlay
                }

                if readOnly {
                    overlay.onDataChanged = nil
                    overlay.onColumnDividerDragBegan = nil
                    overlay.onResizeGestureEnded = nil
                    overlay.onDeleteTable = nil
                } else {
                    overlay.onResizeGestureEnded = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        self.finalizeTableColumnResizeUndoIfNeeded(textView: tv, attachment: att) { data in
                            att.tableData = data
                            let newHeight = NoteTableOverlayView.computeTableHeight(for: data) + 1 + 36
                            let containerWidth = tv.textContainer?.containerSize.width ?? 400
                            let newWidth = min(data.contentWidth, containerWidth)
                            let newSize = CGSize(width: newWidth, height: newHeight)
                            att.attachmentCell = TableSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    tv.layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                        }
                        self.syncText()
                    }
                }

                // Expand frame to cover interactive handle areas outside the table rect.
                // Without this, NSView.hitTest is never called for out-of-frame handle clicks.
                let insets = NoteTableOverlayView.overlayInsets
                let expandedRect = CGRect(
                    x: overlayRect.origin.x - insets.left,
                    y: overlayRect.origin.y - insets.top,
                    width: overlayRect.width + insets.left + insets.right,
                    height: overlayRect.height + insets.top + insets.bottom
                )
                overlay.frame = expandedRect.integral
                overlay.bounds.origin = CGPoint(x: -insets.left, y: -insets.top)
                // Viewport matches the reserved text-layout width, like card sections. The table
                // renderer can still draw overflow outside this viewport because the parent clip
                // view is relaxed in `completeDeferredSetup`.
                overlay.tableWidth = attachment.bounds.width
            }

            // Remove overlays for deleted attachments
            let toRemove = tableOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemove {
                tableOverlays[key]?.removeFromSuperview()
                tableOverlays.removeValue(forKey: key)
            }
        }

        // MARK: - Divider attachment width sync

        /// Keeps `NoteDividerAttachment` cell width in sync with the text container (resize,
        /// first layout). Mirrors the table overlay "size drift" pattern; dividers draw in-cell
        /// so no separate overlay view is needed.
        func updateDividerAttachments(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let width = max(textContainer.containerSize.width, 1)
            // Width-cache short-circuit: `frameDidChange` fires on every layout pass, even when
            // only the height changed. Skip the full `.attachment` enumeration when width hasn't
            // moved since the previous run.
            if let lastWidth = lastKnownDividerContainerWidth, abs(lastWidth - width) < 0.5 {
                return
            }
            lastKnownDividerContainerWidth = width

            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else { return }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
                guard let attachment = value as? NoteDividerAttachment,
                      let cell = attachment.attachmentCell as? DividerSizeAttachmentCell else { return }

                if abs(cell.displaySize.width - width) > 0.5 || abs(attachment.bounds.width - width) > 0.5 {
                    cell.updateWidth(width)
                    attachment.bounds = CGRect(origin: .zero, size: cell.displaySize)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }
            }
        }

        // MARK: - Callout Overlay Management

        func updateCalloutOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let hostView: NSView = textView
            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                calloutOverlays.values.forEach { $0.removeFromSuperview() }
                calloutOverlays.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteCalloutAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // Restore the width from the model once the text container has its real size.
                // `makeCalloutAttachment` may deserialize while the container is still at the
                // temporary 400pt bootstrap width; if we only clamp invalid widths, custom widths
                // never expand back to their persisted size after layout settles.
                let containerW = max(textContainer.containerSize.width, 100)
                let effectiveMinCallout = min(CalloutOverlayView.minWidth, containerW)
                let currentWidth = attachment.bounds.width
                let desiredWidth: CGFloat
                if let preferredWidth = attachment.calloutData.preferredContentWidth {
                    desiredWidth = max(effectiveMinCallout, min(containerW, preferredWidth))
                } else {
                    desiredWidth = containerW
                }
                let widthDrift = abs(currentWidth - desiredWidth) > 1
                let expectedHeight = CalloutOverlayView.heightForData(
                    attachment.calloutData, width: desiredWidth)
                let heightDrift = abs(attachment.bounds.height - expectedHeight) > 1
                if widthDrift || heightDrift {
                    let newSize = CGSize(width: desiredWidth, height: expectedHeight)
                    attachment.attachmentCell = CalloutSizeAttachmentCell(size: newSize)
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 { layoutManager.ensureLayout(forGlyphRange: glyphRange) }
                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                let overlay: CalloutOverlayView
                if let existing = calloutOverlays[id] {
                    overlay = existing
                    overlay.calloutData = attachment.calloutData
                } else {
                    overlay = CalloutOverlayView(calloutData: attachment.calloutData)
                    overlay.parentTextView = textView

                    overlay.onDataChanged = { [weak self, weak textStorage, weak textView, weak attachment] newData in
                        guard let self = self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        let previous = att.calloutData
                        let apply: (CalloutData) -> Void = { data in
                            att.calloutData = data
                            let newHeight = CalloutOverlayView.heightForData(data, width: att.bounds.width)
                            let newSize = CGSize(width: att.bounds.width, height: newHeight)
                            att.attachmentCell = CalloutSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    tv.layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                            self.syncText()
                        }
                        self.applyMutationWithUndo(
                            textView: tv,
                            actionName: "Edit Callout",
                            oldValue: previous,
                            newValue: newData,
                            apply: apply
                        )
                    }

                    overlay.onResizeWidthDragBegan = { [weak self, weak attachment] in
                        guard let self, let att = attachment, let tv = self.textView else { return }
                        self.pendingCalloutWidthResizeSnapshot[ObjectIdentifier(att)] = att.calloutData
                    }

                    overlay.onDeleteCallout = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self = self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                var deleteStart = charRange.location
                                var deleteEnd = charRange.location + charRange.length
                                let nsString = ts.string as NSString
                                if deleteStart > 0 {
                                    let prev = nsString.character(at: deleteStart - 1)
                                    if let scalar = Unicode.Scalar(prev), CharacterSet.newlines.contains(scalar) {
                                        deleteStart -= 1
                                    }
                                }
                                if deleteEnd < nsString.length {
                                    let next = nsString.character(at: deleteEnd)
                                    if let scalar = Unicode.Scalar(next), CharacterSet.newlines.contains(scalar) {
                                        deleteEnd += 1
                                    }
                                }
                                let deleteRange = NSRange(location: deleteStart, length: deleteEnd - deleteStart)
                                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                                    ts.replaceCharacters(in: deleteRange, with: "")
                                    tv.didChangeText()
                                }
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    overlay.onWidthChanged = { [weak self, weak textStorage, weak layoutManager, weak attachment, weak textView] newWidth in
                        guard let self = self, let ts = textStorage, let lm = layoutManager, let att = attachment,
                              let tc = textView?.textContainer else { return }
                        // Double-click right edge snaps to full container per user request (setup-doubleclick-handles).
                        // Respects minWidth clamp. hasBeenUserResized-like flag not needed for callout (unlike code blocks).
                        // Ensures styleTodoParagraphs isImageParagraph branch (~7989) and shouldChangeText guard (~4929) handle it.
                        let effMin = min(CalloutOverlayView.minWidth, tc.containerSize.width)
                        let clamped = max(effMin, min(newWidth, tc.containerSize.width))
                        let newHeight = CalloutOverlayView.heightForData(att.calloutData, width: clamped)
                        let newSize = CGSize(width: clamped, height: newHeight)
                        att.attachmentCell = CalloutSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)
                        // Persist width in `CalloutData` so serialize() round-trips; nil when flush with container (short markup).
                        let cw = tc.containerSize.width
                        var nextData = att.calloutData
                        nextData.preferredContentWidth = abs(clamped - cw) < 1 ? nil : clamped
                        att.calloutData = nextData
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                        // Do not call `syncText()` here: it runs `styleTodoParagraphs` and schedules
                        // overlay/binding work on every drag tick, which flashes the whole note body.
                        // Width lives in textStorage + `CalloutData`; `onResizeGestureEnded` runs one
                        // debounced `syncText()` after drag or double-click snap; note-switch flush still
                        // serializes live storage synchronously.
                    }

                    hostView.addSubview(overlay)
                    calloutOverlays[id] = overlay
                }

                // Disable interaction in read-only mode (version preview)
                if readOnly {
                    overlay.onDataChanged = nil
                    overlay.onDeleteCallout = nil
                    overlay.onWidthChanged = nil
                    overlay.onResizeGestureEnded = nil
                    overlay.onResizeWidthDragBegan = nil
                } else {
                    // (Re)wire every pass so overlays created before this callback existed still persist width on gesture end.
                    overlay.onResizeGestureEnded = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        self.finalizeCalloutWidthResizeUndoIfNeeded(textView: tv, attachment: att) { data in
                            guard let tc = tv.textContainer else { return }
                            let cw = tc.containerSize.width
                            let effMin = min(CalloutOverlayView.minWidth, cw)
                            let clamped: CGFloat
                            if let pref = data.preferredContentWidth {
                                clamped = max(effMin, min(pref, cw))
                            } else {
                                clamped = cw
                            }
                            att.calloutData = data
                            let newHeight = CalloutOverlayView.heightForData(data, width: clamped)
                            let newSize = CGSize(width: clamped, height: newHeight)
                            att.attachmentCell = CalloutSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    tv.layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                        }
                        self.syncText()
                    }
                }

                overlay.currentContainerWidth = containerW
                // Widen frame past the glyph rect so the resize handle's outer half is inside
                // the overlay bounds for hit testing (see CalloutOverlayView.resizeHitOutset).
                overlay.contentLayoutWidth = attachment.bounds.width
                let calloutExpanded = CGRect(
                    x: overlayRect.origin.x,
                    y: overlayRect.origin.y,
                    width: overlayRect.width + CalloutOverlayView.resizeHitOutset,
                    height: overlayRect.height
                )
                overlay.frame = calloutExpanded.integral
            }

            let toRemoveCallout = calloutOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemoveCallout {
                calloutOverlays[key]?.removeFromSuperview()
                calloutOverlays.removeValue(forKey: key)
            }
        }

        // MARK: - Code Block Overlay Management

        func updateCodeBlockOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let hostView: NSView = textView
            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                codeBlockOverlays.values.forEach { $0.removeFromSuperview() }
                codeBlockOverlays.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteCodeBlockAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // Restore width from `preferredContentWidth` once the container is valid (same pattern as callouts).
                let containerW = max(textContainer.containerSize.width, 100)
                let effectiveMinCode = min(CodeBlockOverlayView.minWidth, containerW)
                let desiredWidth: CGFloat
                if let pref = attachment.codeBlockData.preferredContentWidth {
                    desiredWidth = max(effectiveMinCode, min(containerW, pref))
                } else {
                    desiredWidth = containerW
                }
                let currentWidth = attachment.bounds.width
                let expectedHeight = CodeBlockOverlayView.heightForData(attachment.codeBlockData, width: desiredWidth)
                let widthDrift = abs(currentWidth - desiredWidth) > 1
                let heightDrift = abs(attachment.bounds.height - expectedHeight) > 1
                if widthDrift || heightDrift {
                    let newSize = CGSize(width: desiredWidth, height: expectedHeight)
                    attachment.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 { layoutManager.ensureLayout(forGlyphRange: glyphRange) }
                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                let overlay: CodeBlockOverlayView
                if let existing = codeBlockOverlays[id] {
                    overlay = existing
                    overlay.codeBlockData = attachment.codeBlockData
                } else {
                    overlay = CodeBlockOverlayView(codeBlockData: attachment.codeBlockData)
                    overlay.parentTextView = textView

                    overlay.onDataChanged = { [weak self, weak textStorage, weak layoutManager, weak textView, weak attachment] newData in
                        guard let self = self, let ts = textStorage, let lm = layoutManager, let tv = textView, let att = attachment else { return }
                        let previous = att.codeBlockData
                        let apply: (CodeBlockData) -> Void = { data in
                            att.codeBlockData = data
                            let newHeight = CodeBlockOverlayView.heightForData(data, width: att.bounds.width)
                            if abs(att.bounds.height - newHeight) > 1 {
                                let newSize = CGSize(width: att.bounds.width, height: newHeight)
                                att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                                att.bounds = CGRect(origin: .zero, size: newSize)
                            }
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                            self.syncText()
                        }
                        self.applyMutationWithUndo(
                            textView: tv,
                            actionName: "Edit Code Block",
                            oldValue: previous,
                            newValue: newData,
                            apply: apply
                        )
                    }

                    overlay.onResizeWidthDragBegan = { [weak self, weak attachment] in
                        guard let self, let att = attachment, let tv = self.textView else { return }
                        self.pendingCodeBlockWidthResizeSnapshot[ObjectIdentifier(att)] = att.codeBlockData
                    }

                    overlay.onDeleteCodeBlock = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self = self, let ts = textStorage,
                              let tv = textView, let att = attachment else { return }
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                var deleteStart = charRange.location
                                var deleteEnd = charRange.location + charRange.length
                                let nsString = ts.string as NSString
                                if deleteStart > 0 {
                                    let prev = nsString.character(at: deleteStart - 1)
                                    if let scalar = Unicode.Scalar(prev),
                                       CharacterSet.newlines.contains(scalar) { deleteStart -= 1 }
                                }
                                if deleteEnd < nsString.length {
                                    let next = nsString.character(at: deleteEnd)
                                    if let scalar = Unicode.Scalar(next),
                                       CharacterSet.newlines.contains(scalar) { deleteEnd += 1 }
                                }
                                let deleteRange = NSRange(location: deleteStart,
                                                         length: deleteEnd - deleteStart)
                                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                                    ts.replaceCharacters(in: deleteRange, with: "")
                                    tv.didChangeText()
                                }
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    overlay.onWidthChanged = { [weak textStorage, weak layoutManager, weak attachment, weak textView] newWidth in
                        guard let ts = textStorage, let lm = layoutManager, let att = attachment,
                              let tc = textView?.textContainer else { return }
                        att.hasBeenUserResized = true
                        let effMin = min(CodeBlockOverlayView.minWidth, tc.containerSize.width)
                        let clamped = max(effMin, min(newWidth, tc.containerSize.width))
                        let cw = tc.containerSize.width
                        var next = att.codeBlockData
                        next.preferredContentWidth = abs(clamped - cw) < 1 ? nil : clamped
                        att.codeBlockData = next
                        let newHeight = CodeBlockOverlayView.heightForData(att.codeBlockData, width: clamped)
                        let newSize = CGSize(width: clamped, height: newHeight)
                        att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                    }

                    hostView.addSubview(overlay)
                    codeBlockOverlays[id] = overlay
                }

                // Disable interaction in read-only mode (version preview)
                if readOnly {
                    overlay.onDataChanged = nil
                    overlay.onDeleteCodeBlock = nil
                    overlay.onWidthChanged = nil
                    overlay.onResizeGestureEnded = nil
                    overlay.onResizeWidthDragBegan = nil
                } else {
                    overlay.onResizeGestureEnded = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        self.finalizeCodeBlockWidthResizeUndoIfNeeded(textView: tv, attachment: att) { data in
                            guard let tc = tv.textContainer else { return }
                            att.codeBlockData = data
                            let containerW = max(tc.containerSize.width, 100)
                            let effectiveMinCode = min(CodeBlockOverlayView.minWidth, containerW)
                            let desiredWidth: CGFloat
                            if let pref = data.preferredContentWidth {
                                desiredWidth = max(effectiveMinCode, min(containerW, pref))
                            } else {
                                desiredWidth = containerW
                            }
                            let newHeight = CodeBlockOverlayView.heightForData(data, width: desiredWidth)
                            let newSize = CGSize(width: desiredWidth, height: newHeight)
                            att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    tv.layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                        }
                        self.syncText()
                    }
                }

                overlay.currentContainerWidth = containerW
                overlay.frame = overlayRect.integral
            }

            let toRemove = codeBlockOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemove {
                codeBlockOverlays[key]?.removeFromSuperview()
                codeBlockOverlays.removeValue(forKey: key)
            }
        }

        // MARK: - Tabs Container Overlay Management

        func updateTabsOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let hostView: NSView = textView
            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                tabsOverlays.values.forEach { $0.removeFromSuperview() }
                tabsOverlays.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteTabsAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // ── WIDTH / HEIGHT CORRECTION ──
                let containerW = max(textContainer.containerSize.width, 100)
                let effectiveMin = min(TabsContainerOverlayView.minWidth, containerW)
                let currentWidth = attachment.bounds.width
                let expectedHeight = TabsContainerOverlayView.totalHeight(for: attachment.tabsData)
                // Without `preferredContentWidth`, min-width during deserialize is ambiguous; do not
                // expand to full container if the user explicitly chose the minimum width.
                let atMinFromDeserialization =
                    currentWidth <= effectiveMin && containerW > effectiveMin
                    && attachment.tabsData.preferredContentWidth == nil
                let needsCorrection = currentWidth < effectiveMin
                    || currentWidth > containerW
                    || abs(attachment.bounds.height - expectedHeight) > 1
                    || atMinFromDeserialization
                if needsCorrection {
                    let correctedWidth: CGFloat
                    if atMinFromDeserialization {
                        correctedWidth = containerW
                    } else {
                        correctedWidth = max(effectiveMin, min(containerW, currentWidth))
                    }
                    let newSize = CGSize(width: correctedWidth, height: expectedHeight)
                    attachment.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }

                // ── LAYOUT & POSITIONING ──
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 { layoutManager.ensureLayout(forGlyphRange: glyphRange) }
                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                // ── OVERLAY CREATION OR UPDATE ──
                let overlay: TabsContainerOverlayView
                if let existing = tabsOverlays[id] {
                    overlay = existing
                    overlay.tabsData = attachment.tabsData
                } else {
                    overlay = TabsContainerOverlayView(tabsData: attachment.tabsData)
                    overlay.parentTextView = textView
                    overlay.editorInstanceID = editorInstanceID

                    // ── onDataChanged ──
                    overlay.onDataChanged = { [weak self, weak textStorage, weak textView, weak attachment] newData in
                        guard let self = self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        let previous = att.tabsData
                        let apply: (TabsContainerData) -> Void = { data in
                            att.tabsData = data
                            let newHeight = TabsContainerOverlayView.totalHeight(for: data)
                            let newSize = CGSize(width: att.bounds.width, height: newHeight)
                            att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    tv.layoutManager?.invalidateLayout(
                                        forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                            self.syncText()
                        }
                        self.applyMutationWithUndo(
                            textView: tv,
                            actionName: "Edit Tabs",
                            oldValue: previous,
                            newValue: newData,
                            apply: apply
                        )
                    }

                    overlay.onResizeWidthDragBegan = { [weak self, weak attachment] in
                        guard let self, let att = attachment, let tv = self.textView else { return }
                        self.pendingTabsWidthResizeSnapshot[ObjectIdentifier(att)] = att.tabsData
                    }

                    overlay.onResizeHeightDragBegan = { [weak self, weak attachment] in
                        guard let self, let att = attachment, let tv = self.textView else { return }
                        self.pendingTabsHeightResizeSnapshot[ObjectIdentifier(att)] = att.tabsData
                    }

                    // ── onDeleteTabs ──
                    overlay.onDeleteTabs = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self = self, let ts = textStorage,
                              let tv = textView, let att = attachment else { return }
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                var deleteStart = charRange.location
                                var deleteEnd = charRange.location + charRange.length
                                let nsString = ts.string as NSString
                                if deleteStart > 0 {
                                    let prev = nsString.character(at: deleteStart - 1)
                                    if let scalar = Unicode.Scalar(prev),
                                       CharacterSet.newlines.contains(scalar) { deleteStart -= 1 }
                                }
                                if deleteEnd < nsString.length {
                                    let next = nsString.character(at: deleteEnd)
                                    if let scalar = Unicode.Scalar(next),
                                       CharacterSet.newlines.contains(scalar) { deleteEnd += 1 }
                                }
                                let deleteRange = NSRange(location: deleteStart,
                                                         length: deleteEnd - deleteStart)
                                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                                    ts.replaceCharacters(in: deleteRange, with: "")
                                    tv.didChangeText()
                                }
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    // ── onWidthChanged ──
                    overlay.onWidthChanged = { [weak self, weak textStorage, weak layoutManager, weak attachment, weak textView] newWidth in
                        guard let self = self, let ts = textStorage, let lm = layoutManager, let att = attachment,
                              let tc = textView?.textContainer else { return }
                        let effMin = min(TabsContainerOverlayView.minWidth, tc.containerSize.width)
                        let clamped = max(effMin, min(newWidth, tc.containerSize.width))
                        let newSize = CGSize(width: clamped, height: att.bounds.height)
                        let cw = tc.containerSize.width
                        var nextTabs = att.tabsData
                        nextTabs.preferredContentWidth = abs(clamped - cw) < 1 ? nil : clamped
                        att.tabsData = nextTabs
                        att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                        // Match callout: avoid syncText on every drag tick (reduces block glitches).
                    }

                    // ── onHeightChanged ──
                    overlay.onHeightChanged = { [weak self, weak textStorage, weak layoutManager, weak attachment] newHeight in
                        guard let self = self, let ts = textStorage, let lm = layoutManager, let att = attachment else { return }
                        att.tabsData.containerHeight = newHeight
                        let totalH = TabsContainerOverlayView.totalHeight(for: att.tabsData)
                        let newSize = CGSize(width: att.bounds.width, height: totalH)
                        att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                        // Defer `syncText` to `onResizeHeightGestureEnded` so height drags match width (one flush + undo).
                    }

                    hostView.addSubview(overlay)
                    tabsOverlays[id] = overlay
                }

                if readOnly {
                    overlay.onDataChanged = nil
                    overlay.onDeleteTabs = nil
                    overlay.onWidthChanged = nil
                    overlay.onHeightChanged = nil
                    overlay.onResizeWidthGestureEnded = nil
                    overlay.onResizeWidthDragBegan = nil
                    overlay.onResizeHeightGestureEnded = nil
                    overlay.onResizeHeightDragBegan = nil
                } else {
                    overlay.onResizeWidthGestureEnded = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        self.finalizeTabsWidthResizeUndoIfNeeded(textView: tv, attachment: att) { data in
                            guard let tc = tv.textContainer else { return }
                            att.tabsData = data
                            let containerW = max(tc.containerSize.width, 100)
                            let effectiveMin = min(TabsContainerOverlayView.minWidth, containerW)
                            let desiredWidth: CGFloat
                            if let pref = data.preferredContentWidth {
                                desiredWidth = max(effectiveMin, min(containerW, pref))
                            } else {
                                desiredWidth = containerW
                            }
                            let totalH = TabsContainerOverlayView.totalHeight(for: data)
                            let newSize = CGSize(width: desiredWidth, height: totalH)
                            att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    tv.layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                        }
                        self.syncText()
                    }
                    overlay.onResizeHeightGestureEnded = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        self.finalizeTabsHeightResizeUndoIfNeeded(textView: tv, attachment: att) { data in
                            att.tabsData = data
                            let totalH = TabsContainerOverlayView.totalHeight(for: data)
                            let newSize = CGSize(width: att.bounds.width, height: totalH)
                            att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    tv.layoutManager?.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                        }
                        self.syncText()
                    }
                }

                overlay.currentContainerWidth = containerW
                overlay.frame = overlayRect.integral
            }

            // ── CLEANUP ──
            let toRemove = tabsOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemove {
                tabsOverlays[key]?.removeFromSuperview()
                tabsOverlays.removeValue(forKey: key)
            }
        }

        // MARK: - Card Section Overlay Management

        func updateCardSectionOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let hostView: NSView = textView
            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                cardSectionOverlays.values.forEach { $0.removeFromSuperview() }
                cardSectionOverlays.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteCardSectionAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // ── WIDTH / HEIGHT CORRECTION ──
                let containerW = max(textContainer.containerSize.width, 100)
                let effectiveMin = min(CardSectionOverlayView.minWidth, containerW)
                let currentWidth = attachment.bounds.width
                let expectedHeight = CardSectionOverlayView.totalHeight(for: attachment.cardSectionData)
                let atMinFromDeserialization = currentWidth <= effectiveMin && containerW > effectiveMin
                let needsCorrection = currentWidth < effectiveMin
                    || currentWidth > containerW
                    || abs(attachment.bounds.height - expectedHeight) > 1
                    || atMinFromDeserialization
                if needsCorrection {
                    let correctedWidth: CGFloat
                    if atMinFromDeserialization {
                        correctedWidth = containerW
                    } else {
                        correctedWidth = max(effectiveMin, min(containerW, currentWidth))
                    }
                    let newSize = CGSize(width: correctedWidth, height: expectedHeight)
                    attachment.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }

                // ── LAYOUT & POSITIONING ──
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 { layoutManager.ensureLayout(forGlyphRange: glyphRange) }
                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                // ── OVERLAY CREATION OR UPDATE ──
                let overlay: CardSectionOverlayView
                if let existing = cardSectionOverlays[id] {
                    overlay = existing
                    overlay.cardSectionData = attachment.cardSectionData
                } else {
                    overlay = CardSectionOverlayView(cardSectionData: attachment.cardSectionData)
                    overlay.parentTextView = textView
                    overlay.editorInstanceID = editorInstanceID

                    // ── onDataChanged ──
                    overlay.onDataChanged = { [weak self, weak textStorage, weak textView, weak attachment] newData in
                        guard let self = self, let ts = textStorage, let tv = textView, let att = attachment else { return }
                        let previous = att.cardSectionData
                        let apply: (CardSectionData) -> Void = { data in
                            att.cardSectionData = data
                            let newHeight = CardSectionOverlayView.totalHeight(for: data)
                            let newSize = CGSize(width: att.bounds.width, height: newHeight)
                            att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    tv.layoutManager?.invalidateLayout(
                                        forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                            self.syncText()
                        }
                        self.applyMutationWithUndo(
                            textView: tv,
                            actionName: "Edit Cards",
                            oldValue: previous,
                            newValue: newData,
                            apply: apply
                        )
                    }

                    // ── onDeleteCardSection ──
                    overlay.onDeleteCardSection = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self = self, let ts = textStorage,
                              let tv = textView, let att = attachment else { return }
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                var deleteStart = charRange.location
                                var deleteEnd = charRange.location + charRange.length
                                let nsString = ts.string as NSString
                                if deleteStart > 0 {
                                    let prev = nsString.character(at: deleteStart - 1)
                                    if let scalar = Unicode.Scalar(prev),
                                       CharacterSet.newlines.contains(scalar) { deleteStart -= 1 }
                                }
                                if deleteEnd < nsString.length {
                                    let next = nsString.character(at: deleteEnd)
                                    if let scalar = Unicode.Scalar(next),
                                       CharacterSet.newlines.contains(scalar) { deleteEnd += 1 }
                                }
                                let deleteRange = NSRange(location: deleteStart,
                                                         length: deleteEnd - deleteStart)
                                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                                    ts.replaceCharacters(in: deleteRange, with: "")
                                    tv.didChangeText()
                                }
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    // ── onWidthChanged ──
                    overlay.onWidthChanged = { [weak self, weak textStorage, weak layoutManager, weak attachment, weak textView] newWidth in
                        guard let self = self, let ts = textStorage, let lm = layoutManager, let att = attachment,
                              let tc = textView?.textContainer else { return }
                        let effMin = min(CardSectionOverlayView.minWidth, tc.containerSize.width)
                        let clamped = max(effMin, min(newWidth, tc.containerSize.width))
                        let newSize = CGSize(width: clamped, height: att.bounds.height)
                        att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    // ── onHeightChanged ──
                    overlay.onHeightChanged = { [weak self, weak textStorage, weak layoutManager, weak attachment] _ in
                        guard let self = self, let ts = textStorage, let lm = layoutManager, let att = attachment else { return }
                        let totalH = CardSectionOverlayView.totalHeight(for: att.cardSectionData)
                        let newSize = CGSize(width: att.bounds.width, height: totalH)
                        att.attachmentCell = CodeBlockSizeAttachmentCell(size: newSize)
                        att.bounds = CGRect(origin: .zero, size: newSize)
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    hostView.addSubview(overlay)
                    cardSectionOverlays[id] = overlay
                }

                overlay.currentContainerWidth = containerW
                overlay.frame = overlayRect.integral
            }

            // ── CLEANUP ──
            let cardSectionToRemove = cardSectionOverlays.keys.filter { !seenIDs.contains($0) }
            for key in cardSectionToRemove {
                cardSectionOverlays[key]?.removeFromSuperview()
                cardSectionOverlays.removeValue(forKey: key)
            }
        }

        // MARK: - Link Card Overlay Management

        func updateLinkCardOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let hostView: NSView = textView
            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                linkCardOverlays.values.forEach { $0.removeFromSuperview() }
                linkCardOverlays.removeAll()
                linkCardThumbnailLoadAttempted.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteLinkCardAttachment else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // Restore thumbnail from disk cache if missing (one attempt per attachment)
                if attachment.thumbnailImage == nil && !linkCardThumbnailLoadAttempted.contains(id) {
                    linkCardThumbnailLoadAttempted.insert(id)
                    Task { @MainActor [weak self] in
                        if let cached = await ThumbnailCache.shared.loadCachedThumbnail(for: attachment.url) {
                            attachment.thumbnailImage = cached
                            attachment.thumbnailTintColor = LinkCardView.averageColor(of: cached)
                            if let tv = self?.textView { self?.updateLinkCardOverlays(in: tv) }
                        }
                    }
                }

                // Size correction — dynamic height based on thumbnail presence
                let cardWidth: CGFloat = 224
                let hasThumbnail = attachment.thumbnailImage != nil
                let cardHeight = LinkCardView.heightForCard(hasThumbnail: hasThumbnail)
                let correctSize = CGSize(width: cardWidth, height: cardHeight)
                let currentCell = attachment.attachmentCell as? CodeBlockSizeAttachmentCell
                let needsCorrection = currentCell == nil
                    || abs(currentCell!.displaySize.height - correctSize.height) > 1
                    || abs(currentCell!.displaySize.width - correctSize.width) > 1

                if needsCorrection {
                    attachment.attachmentCell = CodeBlockSizeAttachmentCell(size: correctSize)
                    attachment.bounds = CGRect(origin: .zero, size: correctSize)
                    layoutManager.invalidateLayout(
                        forCharacterRange: range,
                        actualCharacterRange: nil
                    )
                }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 { layoutManager.ensureLayout(forGlyphRange: glyphRange) }
                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                let cardView = LinkCardView(
                    title: attachment.title,
                    description: attachment.descriptionText,
                    domain: attachment.domain,
                    url: attachment.url,
                    thumbnailImage: attachment.thumbnailImage,
                    tintColor: attachment.thumbnailTintColor,
                    cardWidth: cardWidth
                )

                let hostingView: NSView
                if let existing = linkCardOverlays[id] {
                    hostingView = existing
                    if let hv = hostingView as? NSHostingView<AnyView> {
                        hv.rootView = AnyView(
                            cardView.onTapGesture {
                                if let url = URL(string: attachment.url) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        )
                    }
                } else {
                    let cardContent = AnyView(
                        cardView.onTapGesture {
                            if let url = URL(string: attachment.url) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )
                    let hv = NSHostingView(rootView: cardContent)
                    hv.wantsLayer = true
                    hv.layer?.backgroundColor = .clear
                    hostView.addSubview(hv)
                    hostingView = hv
                    linkCardOverlays[id] = hv
                }

                hostingView.frame = overlayRect.integral
            }

            let toRemove = linkCardOverlays.keys.filter { !seenIDs.contains($0) }
            for key in toRemove {
                linkCardOverlays[key]?.removeFromSuperview()
                linkCardOverlays.removeValue(forKey: key)
                linkCardThumbnailLoadAttempted.remove(key)
            }
        }

        // MARK: - File Preview Overlays

        func updateFilePreviewOverlays(in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let hostView: NSView = textView
            var seenIDs = Set<ObjectIdentifier>()
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                filePreviewOverlays.values.forEach { $0.removeFromSuperview() }
                filePreviewOverlays.removeAll()
                return
            }

            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { val, range, _ in
                guard let attachment = val as? NoteFileAttachment,
                      attachment.viewMode != .tag else { return }
                let id = ObjectIdentifier(attachment)
                seenIDs.insert(id)

                // Lazily compute aspect ratio if not cached yet
                let attCategory = FileCategory.classify(attachment.typeIdentifier)
                if attCategory == .image, attachment.cachedImageAspectRatio == nil {
                    attachment.cachedImageAspectRatio = FileAttachmentStorageManager.imageAspectRatio(
                        for: attachment.storedFilename)
                } else if attCategory == .pdf, attachment.cachedPdfPageAspectRatio == nil {
                    attachment.cachedPdfPageAspectRatio = FileAttachmentStorageManager.pdfPageAspectRatio(
                        for: attachment.storedFilename)
                }

                let containerW = max(textContainer.containerSize.width, 100)
                let targetWidth: CGFloat = attachment.viewMode == .full
                    ? containerW
                    : min(400, containerW)
                let targetHeight = FilePreviewOverlayView.heightForData(
                    FilePreviewOverlayView.FileAttachmentInfo(
                        storedFilename: attachment.storedFilename,
                        originalFilename: attachment.originalFilename,
                        typeIdentifier: attachment.typeIdentifier,
                        displayLabel: attachment.displayLabel,
                        imageAspectRatio: attachment.cachedImageAspectRatio,
                        pdfPageAspectRatio: attachment.cachedPdfPageAspectRatio
                    ),
                    viewMode: attachment.viewMode,
                    width: targetWidth
                )

                let needsSizeUpdate = abs(attachment.bounds.width - targetWidth) > 1
                    || abs(attachment.bounds.height - targetHeight) > 1
                if needsSizeUpdate {
                    let newSize = CGSize(width: targetWidth, height: targetHeight)
                    attachment.image = nil // Ensure no stale tag pill image
                    attachment.attachmentCell = CalloutSizeAttachmentCell(size: newSize)
                    attachment.bounds = CGRect(origin: .zero, size: newSize)
                    textStorage.beginEditing()
                    textStorage.addAttribute(.fileViewMode, value: attachment.viewMode.rawValue, range: range)
                    textStorage.endEditing()
                    layoutManager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                if glyphRange.length > 0 { layoutManager.ensureLayout(forGlyphRange: glyphRange) }
                guard glyphRange.length > 0 else { return }
                let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                let overlayRect = CGRect(
                    x: glyphRect.origin.x + textView.textContainerOrigin.x,
                    y: glyphRect.origin.y + textView.textContainerOrigin.y,
                    width: attachment.bounds.width,
                    height: attachment.bounds.height
                )

                let overlay: FilePreviewOverlayView
                if let existing = filePreviewOverlays[id] {
                    overlay = existing
                    let modeChanged = overlay.viewMode != attachment.viewMode
                    let widthChanged = abs(overlay.currentContainerWidth - attachment.bounds.width) > 1
                    overlay.storedFilename = attachment.storedFilename
                    overlay.originalFilename = attachment.originalFilename
                    overlay.viewMode = attachment.viewMode
                    overlay.currentContainerWidth = attachment.bounds.width
                    if modeChanged || widthChanged {
                        overlay.rebuildHostingView()
                    }
                } else {
                    overlay = FilePreviewOverlayView(
                        storedFilename: attachment.storedFilename,
                        originalFilename: attachment.originalFilename,
                        typeIdentifier: attachment.typeIdentifier,
                        displayLabel: attachment.displayLabel,
                        viewMode: attachment.viewMode,
                        containerWidth: attachment.bounds.width
                    )
                    overlay.parentTextView = textView

                    overlay.onViewModeChanged = { [weak self, weak textStorage, weak layoutManager, weak attachment] newMode in
                        guard let self = self, let ts = textStorage, let lm = layoutManager, let att = attachment else { return }
                        att.viewMode = newMode

                        if newMode == .tag {
                            // Revert to tag: restore the original pill style
                            let tagAttStr: NSMutableAttributedString
                            if let linkPath = att.originalFileLinkPath,
                               let linkName = att.originalFileLinkDisplayName {
                                // Was originally a FileLinkAttachment -- restore as file link pill
                                tagAttStr = self.makeFileLinkAttachment(
                                    filePath: linkPath,
                                    displayName: linkName,
                                    bookmarkBase64: att.originalFileLinkBookmark ?? ""
                                )
                            } else {
                                // Was originally a stored file -- restore as file tag
                                let tagMeta = FileAttachmentMetadata(
                                    storedFilename: att.storedFilename,
                                    originalFilename: att.originalFilename,
                                    typeIdentifier: att.typeIdentifier,
                                    displayLabel: att.originalFilename,
                                    viewMode: .tag
                                )
                                tagAttStr = self.makeFileAttachment(metadata: tagMeta)
                            }
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    if let tv = self.textView, tv.shouldChangeText(in: charRange, replacementString: nil) {
                                        ts.replaceCharacters(in: charRange, with: tagAttStr)
                                        // Reset paragraph style to inline (remove block-level spacing)
                                        let baseStyle = NSMutableParagraphStyle()
                                        baseStyle.alignment = .natural
                                        let newRange = NSRange(location: charRange.location, length: tagAttStr.length)
                                        if newRange.location + newRange.length <= ts.length {
                                            ts.addAttribute(.paragraphStyle, value: baseStyle, range: newRange)
                                        }
                                        tv.didChangeText()
                                    }
                                    stop.pointee = true
                                }
                            }
                        } else {
                            // Switch between medium/full: resize
                            let cw = max(self.textView?.textContainer?.containerSize.width ?? 400, 100)
                            let newWidth: CGFloat = newMode == .full ? cw : min(400, cw)
                            let newHeight = FilePreviewOverlayView.heightForData(
                                FilePreviewOverlayView.FileAttachmentInfo(
                                    storedFilename: att.storedFilename,
                                    originalFilename: att.originalFilename,
                                    typeIdentifier: att.typeIdentifier,
                                    displayLabel: att.displayLabel,
                                    imageAspectRatio: att.cachedImageAspectRatio,
                                    pdfPageAspectRatio: att.cachedPdfPageAspectRatio
                                ),
                                viewMode: newMode,
                                width: newWidth
                            )
                            let newSize = CGSize(width: newWidth, height: newHeight)
                            att.image = nil // Ensure no stale tag pill image
                            att.attachmentCell = CalloutSizeAttachmentCell(size: newSize)
                            att.bounds = CGRect(origin: .zero, size: newSize)
                            let fr = NSRange(location: 0, length: ts.length)
                            ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                                if val as AnyObject === att {
                                    ts.beginEditing()
                                    ts.addAttribute(.fileViewMode, value: newMode.rawValue, range: charRange)
                                    ts.endEditing()
                                    lm.invalidateGlyphs(forCharacterRange: charRange, changeInLength: 0, actualCharacterRange: nil)
                                    lm.invalidateLayout(forCharacterRange: charRange, actualCharacterRange: nil)
                                    stop.pointee = true
                                }
                            }
                        }
                        self.syncText()
                        self.scheduleOverlayUpdate()
                    }

                    overlay.onDelete = { [weak self, weak textStorage, weak textView, weak attachment] in
                        guard let self = self, let ts = textStorage,
                              let tv = textView, let att = attachment else { return }
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                var deleteStart = charRange.location
                                var deleteEnd = charRange.location + charRange.length
                                let nsString = ts.string as NSString
                                if deleteStart > 0 {
                                    let prev = nsString.character(at: deleteStart - 1)
                                    if let scalar = Unicode.Scalar(prev),
                                       CharacterSet.newlines.contains(scalar) { deleteStart -= 1 }
                                }
                                if deleteEnd < nsString.length {
                                    let next = nsString.character(at: deleteEnd)
                                    if let scalar = Unicode.Scalar(next),
                                       CharacterSet.newlines.contains(scalar) { deleteEnd += 1 }
                                }
                                let deleteRange = NSRange(location: deleteStart,
                                                         length: deleteEnd - deleteStart)
                                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                                    ts.replaceCharacters(in: deleteRange, with: "")
                                    tv.didChangeText()
                                }
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    overlay.onRename = { [weak self, weak textStorage, weak attachment] newName in
                        guard let self = self, let ts = textStorage, let att = attachment else { return }
                        att.originalFilename = newName
                        let fr = NSRange(location: 0, length: ts.length)
                        ts.enumerateAttribute(.attachment, in: fr, options: []) { val, charRange, stop in
                            if val as AnyObject === att {
                                ts.addAttribute(.fileOriginalFilename, value: newName, range: charRange)
                                stop.pointee = true
                            }
                        }
                        self.syncText()
                    }

                    hostView.addSubview(overlay)
                    filePreviewOverlays[id] = overlay
                }

                overlay.frame = overlayRect.integral
            }

            let filePreviewToRemove = filePreviewOverlays.keys.filter { !seenIDs.contains($0) }
            for key in filePreviewToRemove {
                filePreviewOverlays[key]?.removeFromSuperview()
                filePreviewOverlays.removeValue(forKey: key)
            }
        }
}
