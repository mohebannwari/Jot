//
//  GlobalHotKeyManager.swift
//  Jot
//
//  Thin Swift wrapper around Carbon's RegisterEventHotKey. Supports multiple
//  simultaneous global shortcuts (Quick Note panel, Start meeting session, …).
//  Works under the macOS sandbox without any entitlement, because Carbon hotkey
//  registration goes through the WindowServer's registered-hotkey table — not
//  the accessibility APIs that NSEvent.addGlobalMonitorForEvents would require.
//  This is the same approach Alfred, Raycast, Things, and essentially every
//  serious Mac utility uses.
//

import AppKit
import Carbon.HIToolbox
import os

/// Identifies which feature owns a Carbon `EventHotKeyID.id` within this process.
enum GlobalHotKeySlot: UInt32, CaseIterable {
    case quickNote = 1
    case startMeetingSession = 2
}

final class GlobalHotKeyManager {

    static let shared = GlobalHotKeyManager()

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?
    /// FourCharCode "JOTQ" — must be unique across all hotkey registrations in the process.
    private let signature: OSType = 0x4A4F5451
    private let logger = Logger(subsystem: "com.jot", category: "GlobalHotKeyManager")

    private init() {
        installEventHandler()
    }

    deinit {
        for slot in GlobalHotKeySlot.allCases {
            unregister(slot: slot)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Public API

    /// Main-queue callback when the chord for `slot` fires. Pass `nil` to detach.
    func setHandler(_ handler: (() -> Void)?, for slot: GlobalHotKeySlot) {
        handlers[slot.rawValue] = handler
    }

    /// Install or replace the hotkey for `slot`. Other slots are untouched.
    /// Returns true if registration succeeded.
    @discardableResult
    func register(_ hotKey: QuickNoteHotKey, slot: GlobalHotKeySlot) -> Bool {
        unregister(slot: slot)

        guard hotKey.hasAnyModifier else {
            logger.warning("Refusing to install hotkey with no modifiers (keyCode: \(hotKey.keyCode))")
            return false
        }

        let eventHotKeyID = EventHotKeyID(signature: signature, id: slot.rawValue)
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
            hotKeyRefs[slot.rawValue] = ref
            logger.info("Installed global hotkey [\(slot.rawValue)]: \(hotKey.displayString)")
            return true
        } else {
            logger.error("Failed to install global hotkey \(hotKey.displayString) slot \(slot.rawValue): OSStatus \(status)")
            return false
        }
    }

    /// Unregister one slot only.
    func unregister(slot: GlobalHotKeySlot) {
        let id = slot.rawValue
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
    }

    // MARK: - Carbon event handler

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

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
            guard status == noErr,
                  hkID.signature == manager.signature,
                  manager.hotKeyRefs[hkID.id] != nil else {
                return noErr
            }

            DispatchQueue.main.async {
                manager.handlers[hkID.id]?()
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
