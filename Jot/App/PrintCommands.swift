import AppKit

/// Intercepts Cmd+P at the NSEvent level before macOS's printing
/// infrastructure can reject it. Routes to the editor's Coordinator
/// via NotificationCenter. This bypasses SwiftUI's CommandGroup system
/// entirely because the responder chain from SwiftUI menus does not
/// traverse into NSViewRepresentable-embedded AppKit views.
final class PrintKeyHandler {
    static let shared = PrintKeyHandler()
    private var monitor: Any?

    private init() {}

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "p" {
                NotificationCenter.default.post(name: .printCurrentNote, object: nil)
                return nil
            }
            return event
        }
    }

}
