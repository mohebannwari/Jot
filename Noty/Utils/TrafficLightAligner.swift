//
//  TrafficLightAligner.swift
//  Noty
//
//  Reads the macOS window traffic light button positions at runtime
//  and provides alignment metrics for positioning sidebar icons.
//

#if os(macOS)
import SwiftUI
import AppKit

/// Alignment metrics derived from the actual traffic light button positions.
struct TrafficLightMetrics: Equatable {
    /// Leading X for an icon placed `gap` points after the zoom (green) button.
    var iconLeading: CGFloat
    /// Top Y that vertically centers an icon of `iconHeight` with the traffic light buttons.
    var iconTop: CGFloat

    static let fallback = TrafficLightMetrics(iconLeading: 78, iconTop: 4)
}

/// Invisible NSViewRepresentable that reads the zoom button frame from the hosting
/// NSWindow and reports computed alignment metrics via a binding.
struct TrafficLightAligner: NSViewRepresentable {
    @Binding var metrics: TrafficLightMetrics
    /// Horizontal gap between the zoom button trailing edge and the icon leading edge.
    var gap: CGFloat = 12
    /// Icon height used for vertical center-alignment with the traffic light dots.
    var iconHeight: CGFloat = 16

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackerView {
        TrackerView(coordinator: context.coordinator, aligner: self)
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.aligner = self
    }

    final class Coordinator {}

    final class TrackerView: NSView {
        let coordinator: Coordinator
        var aligner: TrafficLightAligner
        private var windowObservers: [NSObjectProtocol] = []

        init(coordinator: Coordinator, aligner: TrafficLightAligner) {
            self.coordinator = coordinator
            self.aligner = aligner
            super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        }

        required init?(coder: NSCoder) { fatalError() }

        deinit {
            unregisterWindowObservers()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                unregisterWindowObservers()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            registerWindowObservers()
            readMetrics()
        }

        override func layout() {
            super.layout()
            readMetrics()
        }

        private func registerWindowObservers() {
            unregisterWindowObservers()
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didMoveNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification
            ]
            windowObservers = names.map { name in
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.readMetrics()
                }
            }
        }

        private func unregisterWindowObservers() {
            for observer in windowObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            windowObservers.removeAll()
        }

        private func readMetrics() {
            guard let window = window,
                  let zoom = window.standardWindowButton(.zoomButton),
                  let content = window.contentView else { return }

            let frame = zoom.convert(zoom.bounds, to: content)
            guard frame.width > 0, frame.height > 0 else { return }
            let leading = frame.maxX + aligner.gap
            // NSHostingView (SwiftUI's content view) is flipped: Y=0 is at the top.
            // For non-flipped views, convert from bottom-up to top-down.
            let contentHeight = content.bounds.height
            guard content.isFlipped || contentHeight > 0 else { return }
            let centerYFromTop = content.isFlipped
                ? frame.midY
                : contentHeight - frame.midY
            let top = centerYFromTop - aligner.iconHeight / 2

            let result = TrafficLightMetrics(
                iconLeading: max(0, leading),
                iconTop: max(0, top)
            )
            guard result != aligner.metrics else { return }
            if Thread.isMainThread {
                aligner.metrics = result
            } else {
                DispatchQueue.main.async {
                    self.aligner.metrics = result
                }
            }
        }
    }
}
#endif
