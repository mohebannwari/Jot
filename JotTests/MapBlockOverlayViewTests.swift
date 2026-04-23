import AppKit
import CoreLocation
import XCTest

@testable import Jot

@MainActor
final class MapBlockOverlayViewTests: XCTestCase {

    private func makeOverlay(in hostView: NSView) -> MapBlockOverlayView {
        let overlay = MapBlockOverlayView(
            mapData: MapBlockData.initial(
                title: "Museum",
                subtitle: "Downtown",
                coordinate: CLLocationCoordinate2D(latitude: 52.520008, longitude: 13.404954)
            )
        )
        overlay.frame = NSRect(x: 140, y: 120, width: 264, height: 198)
        hostView.addSubview(overlay)
        overlay.layoutSubtreeIfNeeded()
        return overlay
    }

    func testHitTestCapturesResizeEdgeFromSuperviewCoordinates() {
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let overlay = makeOverlay(in: hostView)

        let rightEdgePointInSuperview = NSPoint(
            x: overlay.frame.maxX - 2,
            y: overlay.frame.midY
        )

        XCTAssertTrue(
            overlay.hitTest(rightEdgePointInSuperview) === overlay,
            "NSView.hitTest(_:) receives points in the superview's coordinate space. Resize hit-testing must convert before checking the edge zones, or MKMapView will consume the drag."
        )
    }

    func testHitTestCapturesBottomEdgeFromSuperviewCoordinates() {
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let overlay = makeOverlay(in: hostView)

        let bottomEdgePointInSuperview = NSPoint(
            x: overlay.frame.minX + 20,
            y: overlay.frame.minY + 2
        )

        XCTAssertTrue(
            overlay.hitTest(bottomEdgePointInSuperview) === overlay,
            "The bottom resize zone must still capture away from the centered Open in Maps button."
        )
    }

    func testOpenInMapsFrameAnchorsTwelvePointsFromBottomAndCentersHorizontally() {
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let overlay = makeOverlay(in: hostView)

        let openInMapsFrame = overlay.expectedOpenInMapsFrame()

        XCTAssertEqual(overlay.bounds.maxY - openInMapsFrame.maxY, 12, accuracy: 0.001)
        XCTAssertEqual(openInMapsFrame.midX, overlay.bounds.midX, accuracy: 0.001)
    }

    func testOpenInMapsButtonDoesNotGetCapturedByResizeHitTesting() {
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let overlay = makeOverlay(in: hostView)
        let openInMapsFrame = overlay.expectedOpenInMapsFrame()
        let pointInSuperview = NSPoint(
            x: overlay.frame.minX + openInMapsFrame.midX,
            y: overlay.frame.minY + openInMapsFrame.midY
        )

        XCTAssertFalse(
            overlay.hitTest(pointInSuperview) === overlay,
            "The Open in Maps control should remain clickable instead of being mistaken for a bottom-right resize gesture."
        )
    }

    func testSnapshotDrawingIsSuppressedForLiveWindowedEditors() {
        let liveView = NSView(frame: .init(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = liveView

        XCTAssertFalse(
            MapSizeAttachmentCell.shouldDrawSnapshot(for: liveView),
            "Live editor windows should render only the overlay view. Drawing a snapshot cell underneath causes the resize ghosting."
        )
        XCTAssertTrue(
            MapSizeAttachmentCell.shouldDrawSnapshot(for: nil),
            "Windowless and offscreen render paths still need the snapshot fallback."
        )
    }
}
