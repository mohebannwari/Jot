//
//  GlobalHotKeyManager.swift
//  Jot
//
//  Thin Swift wrapper around Carbon's RegisterEventHotKey. One hotkey at a time.
//  Works under the macOS sandbox without any entitlement, because Carbon hotkey
//  registration goes through the WindowServer's registered-hotkey table — not
//  the accessibility APIs that NSEvent.addGlobalMonitorForEvents would require.
//  This is the same approach Alfred, Raycast, Things, and essentially every
//  serious Mac utility uses.
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
    /// FourCharCode "JOTQ" — must be unique across all hotkey registrations in the process.
    private let signature: OSType = 0x4A4F5451
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
    /// Returns true if registration succeeded.
    @discardableResult
    func install(_ hotKey: QuickNoteHotKey) -> Bool {
        uninstall()

        guard hotKey.hasAnyModifier else {
            logger.warning("Refusing to install hotkey with no modifiers (keyCode: \(hotKey.keyCode))")
            return false
        }

        let eventHotKeyID = EventHotKeyID(signature: signature, id: hotKeyID)
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

    /// Replace the current hotkey with a new one. Shorthand for uninstall + install.
    @discardableResult
    func replace(with newHotKey: QuickNoteHotKey) -> Bool {
        install(newHotKey)
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
                  hkID.id == manager.hotKeyID else {
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
