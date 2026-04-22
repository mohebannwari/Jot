//
//  MapBlockOverlayView.swift
//  Jot
//

import AppKit
import Combine
import CoreLocation
import MapKit
import QuartzCore
import SwiftUI

enum MapBlockLayoutMetrics {
    static let controlInset: CGFloat = 12
    static let resizeThickness: CGFloat = 12
    static let cornerResizeSize: CGFloat = 12
    static let openInMapsSize = CGSize(width: 112, height: 38)

    static func minimumInteractiveWidth(for containerWidth: CGFloat) -> CGFloat {
        min(
            max(containerWidth, 1),
            openInMapsSize.width
        )
    }

    static func minimumDisplayWidth(for containerWidth: CGFloat) -> CGFloat {
        let clampedContainerWidth = max(containerWidth, 1)
        return min(
            clampedContainerWidth,
            max(
                MapBlockData.minimumDisplayWidth(for: clampedContainerWidth),
                minimumInteractiveWidth(for: clampedContainerWidth)
            )
        )
    }

    static func openInMapsFrame(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.midX - (openInMapsSize.width / 2),
            y: bounds.maxY - controlInset - openInMapsSize.height,
            width: openInMapsSize.width,
            height: openInMapsSize.height
        )
    }
}

enum MapBlockCameraGeometry {
    static func cameraPosition(for data: MapBlockData, size: CGSize) -> MapCameraPosition {
        .camera(swiftUICamera(for: data, size: size))
    }

    static func swiftUICamera(for data: MapBlockData, size: CGSize) -> MapCamera {
        let region = MKCoordinateRegion(center: data.viewportCenter, span: data.viewportSpan)
        let distance = cameraDistance(for: region, size: size)
        return MapCamera(
            centerCoordinate: data.viewportCenter,
            distance: distance,
            heading: MapBlockData.normalizedHeading(data.headingDegrees),
            pitch: 0
        )
    }

    static func mapKitCamera(for data: MapBlockData, size: CGSize) -> MKMapCamera {
        let region = MKCoordinateRegion(center: data.viewportCenter, span: data.viewportSpan)
        let distance = cameraDistance(for: region, size: size)
        return MKMapCamera(
            lookingAtCenter: data.viewportCenter,
            fromDistance: distance,
            pitch: 0,
            heading: MapBlockData.normalizedHeading(data.headingDegrees)
        )
    }

    static func cameraDistance(for region: MKCoordinateRegion, size: CGSize) -> CLLocationDistance {
        let normalizedSize = CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )

        let measureDistance = {
            let mapView = MKMapView(
                frame: CGRect(origin: .zero, size: normalizedSize)
            )
            mapView.setRegion(region, animated: false)
            mapView.layoutSubtreeIfNeeded()
            let distance = mapView.camera.centerCoordinateDistance
            return distance > 1 ? distance : fallbackDistance(for: region, size: normalizedSize)
        }

        if Thread.isMainThread {
            return measureDistance()
        }

        var measured: CLLocationDistance = fallbackDistance(for: region, size: normalizedSize)
        DispatchQueue.main.sync {
            measured = measureDistance()
        }
        return measured
    }

    private static func fallbackDistance(
        for region: MKCoordinateRegion,
        size: CGSize
    ) -> CLLocationDistance {
        let latRadians = region.center.latitude * .pi / 180
        let metersPerDegreeLatitude = 111_000.0
        let latMeters = region.span.latitudeDelta * metersPerDegreeLatitude
        let lonMeters = region.span.longitudeDelta
            * metersPerDegreeLatitude
            * max(cos(latRadians), 0.01)
        let aspectAdjustedMeters = max(
            latMeters,
            lonMeters * size.height / max(size.width, 1)
        )
        return max(aspectAdjustedMeters * 1.2, 250)
    }
}

enum MapBlockSnapshotRenderer {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 50 * 1024 * 1024
        return cache
    }()
    private static let stateQueue = DispatchQueue(label: "Jot.MapSnapshot.State")
    private static let renderQueue = DispatchQueue(label: "Jot.MapSnapshot.Render", qos: .userInitiated)
    private static var inFlightKeys: Set<String> = []

    static func cachedImage(
        for data: MapBlockData,
        size: CGSize,
        appearance: NSAppearance
    ) -> NSImage? {
        cache.object(forKey: cacheKey(for: data, size: size, appearance: appearance))
    }

    static func cacheIdentifier(
        for data: MapBlockData,
        size: CGSize,
        appearance: NSAppearance
    ) -> NSString {
        cacheKey(for: data, size: size, appearance: appearance)
    }

    static func requestSnapshot(
        for data: MapBlockData,
        size: CGSize,
        appearance: NSAppearance,
        controlView: NSView?
    ) {
        let key = cacheKey(for: data, size: size, appearance: appearance)
        if cache.object(forKey: key) != nil {
            controlView?.needsDisplay = true
            return
        }

        var shouldStart = false
        stateQueue.sync {
            let rawKey = key as String
            if !inFlightKeys.contains(rawKey) {
                inFlightKeys.insert(rawKey)
                shouldStart = true
            }
        }
        guard shouldStart else { return }

        let snapshotter = MKMapSnapshotter(
            options: makeOptions(for: data, size: size, appearance: appearance)
        )
        snapshotter.start(with: renderQueue) { snapshot, _ in
            if let snapshot,
               let image = renderSnapshot(snapshot, for: data, size: size) {
                cache.setObject(image, forKey: key, cost: Int(size.width * size.height * 4))
            }

            stateQueue.sync {
                inFlightKeys.remove(key as String)
            }

            DispatchQueue.main.async {
                controlView?.needsDisplay = true
            }
        }
    }

    static func blockingSnapshot(
        for data: MapBlockData,
        size: CGSize,
        appearance: NSAppearance
    ) -> NSImage? {
        if let cached = cachedImage(for: data, size: size, appearance: appearance) {
            return cached
        }

        let key = cacheKey(for: data, size: size, appearance: appearance)
        let semaphore = DispatchSemaphore(value: 0)
        var renderedImage: NSImage?

        let snapshotter = MKMapSnapshotter(
            options: makeOptions(for: data, size: size, appearance: appearance)
        )
        snapshotter.start(with: renderQueue) { snapshot, _ in
            if let snapshot {
                renderedImage = renderSnapshot(snapshot, for: data, size: size)
                if let renderedImage {
                    cache.setObject(renderedImage, forKey: key, cost: Int(size.width * size.height * 4))
                }
            }
            semaphore.signal()
        }

        semaphore.wait()
        return renderedImage
    }

    private static func cacheKey(
        for data: MapBlockData,
        size: CGSize,
        appearance: NSAppearance
    ) -> NSString {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return "\(data.serialize())|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))|\(isDark ? "dark" : "light")" as NSString
    }

    private static func makeOptions(
        for data: MapBlockData,
        size: CGSize,
        appearance: NSAppearance
    ) -> MKMapSnapshotter.Options {
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.region = MKCoordinateRegion(center: data.viewportCenter, span: data.viewportSpan)
        options.camera = MapBlockCameraGeometry.mapKitCamera(for: data, size: size)
        options.appearance = appearance
        options.preferredConfiguration = data.displayMode.makeMapConfiguration()
        return options
    }

    private static func renderSnapshot(
        _ snapshot: MKMapSnapshotter.Snapshot,
        for data: MapBlockData,
        size: CGSize
    ) -> NSImage? {
        let composed = NSImage(size: size)
        composed.lockFocus()
        snapshot.image.draw(in: CGRect(origin: .zero, size: size))

        let markerConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        let markerImage = NSImage(
            systemSymbolName: "mappin.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(markerConfiguration)
        let point = snapshot.point(for: data.pinCoordinate)
        let markerSize = CGSize(width: 22, height: 22)
        let markerRect = CGRect(
            x: point.x - markerSize.width / 2,
            y: point.y - markerSize.height,
            width: markerSize.width,
            height: markerSize.height
        )

        if let markerImage {
            let tintedMarker = NSImage(size: markerImage.size)
            tintedMarker.lockFocus()
            markerImage.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.systemRed.set()
            NSRect(origin: .zero, size: markerImage.size).fill(using: .sourceAtop)
            tintedMarker.unlockFocus()
            tintedMarker.draw(in: markerRect)
        }

        composed.unlockFocus()
        return composed
    }
}

@MainActor
private final class MapBlockHostedState: ObservableObject {
    @Published var mapData: MapBlockData
    @Published var cameraPosition: MapCameraPosition
    @Published var isInteractionEnabled: Bool

    var onMapDataChanged: ((MapBlockData) -> Void)?
    var onOpenInMaps: ((URL) -> Void)?

    private(set) var viewSize: CGSize
    private var isApplyingProgrammaticCamera = false

    init(
        mapData: MapBlockData,
        viewSize: CGSize,
        isInteractionEnabled: Bool
    ) {
        self.mapData = mapData
        self.viewSize = CGSize(width: max(viewSize.width, 1), height: max(viewSize.height, 1))
        self.cameraPosition = MapBlockCameraGeometry.cameraPosition(for: mapData, size: viewSize)
        self.isInteractionEnabled = isInteractionEnabled
    }

    var interactionModes: MapInteractionModes {
        isInteractionEnabled ? [.pan, .zoom] : []
    }

    func applyExternalMapData(_ newData: MapBlockData, viewSize: CGSize? = nil) {
        if let viewSize {
            updateViewSize(viewSize)
        }

        let oldData = mapData
        mapData = newData

        if needsProgrammaticCameraRefresh(from: oldData, to: newData) {
            applyProgrammaticCamera(for: newData)
        }
    }

    func updateViewSize(_ newSize: CGSize) {
        viewSize = CGSize(width: max(newSize.width, 1), height: max(newSize.height, 1))
    }

    func handleCameraChange(context: MapCameraUpdateContext, position: MapCameraPosition) {
        guard !isApplyingProgrammaticCamera else { return }
        guard position.positionedByUser else { return }

        var updatedData = mapData
        updatedData.viewportCenter = context.region.center
        updatedData.viewportSpan = context.region.span
        updatedData.headingDegrees = MapBlockData.normalizedHeading(context.camera.heading)
        mapData = updatedData
        onMapDataChanged?(updatedData)
    }

    func openInMaps() {
        guard let url = MapBlockOpenInMapsURLBuilder.url(for: mapData) else { return }
        onOpenInMaps?(url)
    }

    private func applyProgrammaticCamera(for data: MapBlockData) {
        isApplyingProgrammaticCamera = true
        cameraPosition = MapBlockCameraGeometry.cameraPosition(for: data, size: viewSize)
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingProgrammaticCamera = false
        }
    }

    private func needsProgrammaticCameraRefresh(from oldData: MapBlockData, to newData: MapBlockData) -> Bool {
        oldData.viewportCenter.latitude != newData.viewportCenter.latitude
            || oldData.viewportCenter.longitude != newData.viewportCenter.longitude
            || oldData.viewportSpan.latitudeDelta != newData.viewportSpan.latitudeDelta
            || oldData.viewportSpan.longitudeDelta != newData.viewportSpan.longitudeDelta
            || oldData.headingDegrees != newData.headingDegrees
    }
}

private struct MapBlockHostedView: View {
    @ObservedObject var state: MapBlockHostedState

    var body: some View {
        ZStack {
            Map(
                position: Binding(
                    get: { state.cameraPosition },
                    set: { state.cameraPosition = $0 }
                ),
                interactionModes: state.interactionModes
            ) {
                UserAnnotation()
                Marker(
                    state.mapData.displayTitle,
                    coordinate: state.mapData.pinCoordinate
                )
                .tint(.red)
            }
            .mapStyle(state.mapData.displayMode.makeSwiftUIMapStyle())
            .onMapCameraChange(frequency: .onEnd) { context in
                state.handleCameraChange(
                    context: context,
                    position: state.cameraPosition
                )
            }
            .accessibilityIdentifier("map.block.surface")

            Button {
                state.openInMaps()
            } label: {
                Text("Open in Maps")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(
                    width: MapBlockLayoutMetrics.openInMapsSize.width,
                    height: MapBlockLayoutMetrics.openInMapsSize.height
                )
            }
            .buttonStyle(.plain)
            .liquidGlass(in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
            .padding(.bottom, MapBlockLayoutMetrics.controlInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .accessibilityIdentifier("map.block.openInMaps")
        }
    }
}

private extension MapDisplayMode {
    func makeSwiftUIMapStyle() -> MapStyle {
        switch self {
        case .explore:
            return .standard(
                elevation: .flat,
                emphasis: .automatic,
                pointsOfInterest: .all,
                showsTraffic: false
            )
        case .driving:
            return .standard(
                elevation: .flat,
                emphasis: .automatic,
                pointsOfInterest: .all,
                showsTraffic: true
            )
        case .transit:
            return .standard(
                elevation: .flat,
                emphasis: .automatic,
                pointsOfInterest: .including(.publicTransport),
                showsTraffic: false
            )
        case .satellite:
            return .imagery(elevation: .flat)
        }
    }
}

final class MapBlockOverlayView: NSView {
    var mapData: MapBlockData {
        didSet {
            guard oldValue != mapData else { return }
            if !isApplyingHostedStateUpdate {
                hostedState.applyExternalMapData(
                    mapData,
                    viewSize: containerView.bounds.size
                )
            }
            requestSnapshotRefresh()
        }
    }

    weak var parentTextView: NSTextView?
    var containerWidth: CGFloat = 0
    var isInteractionEnabled: Bool = true {
        didSet { updateInteractionState() }
    }
    var onDataChanged: ((MapBlockData) -> Void)?

    private let containerView = NSView()
    private let hostingView: NSHostingView<MapBlockHostedView>
    private let hostedState: MapBlockHostedState
    private let borderLayer = CALayer()
    private let rightResizeHandle = MapResizeHandleView()
    private let bottomResizeHandle = MapResizeHandleView()
    private let cornerResizeHandle = MapResizeHandleView()

    private enum ResizeEdge { case right, bottom, corner }

    private var activeResizeEdge: ResizeEdge?
    private var isDraggingResize = false
    private var dragStartPoint: CGPoint = .zero
    private var dragStartWidth: CGFloat = 0
    private var isApplyingHostedStateUpdate = false

    private var translucencyObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }

    init(mapData: MapBlockData) {
        self.mapData = mapData
        self.hostedState = MapBlockHostedState(
            mapData: mapData,
            viewSize: CGSize(width: 320, height: 240),
            isInteractionEnabled: true
        )
        self.hostingView = NSHostingView(
            rootView: MapBlockHostedView(state: hostedState)
        )
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.cornerRadius = MapBlockData.cornerRadius
        addSubview(containerView)

        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)

        borderLayer.cornerCurve = .continuous
        borderLayer.cornerRadius = MapBlockData.cornerRadius
        borderLayer.borderWidth = 1
        borderLayer.masksToBounds = true
        containerView.layer?.addSublayer(borderLayer)

        hostedState.onMapDataChanged = { [weak self] updatedData in
            self?.handleHostedDataChange(updatedData)
        }
        hostedState.onOpenInMaps = { url in
            NSWorkspace.shared.open(url)
        }

        configureResizeHandles()
        updateInteractionState()
        requestSnapshotRefresh()
        updateBorderAndShadow()

        translucencyObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.detailPaneTranslucencyDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBorderAndShadow()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MapBlockOverlayView does not support init(coder:)")
    }

    deinit {
        if let translucencyObserver {
            NotificationCenter.default.removeObserver(translucencyObserver)
        }
    }

    override func layout() {
        super.layout()
        containerView.frame = bounds
        hostingView.frame = containerView.bounds
        borderLayer.frame = containerView.bounds
        layoutResizeHandles()
        hostedState.updateViewSize(containerView.bounds.size)
        updateBorderAndShadow()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hostedState.updateViewSize(containerView.bounds.size)
        updateBorderAndShadow()
        requestSnapshotRefresh()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderAndShadow()
        requestSnapshotRefresh()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()

        let cornerRect = CGRect(
            x: bounds.maxX - MapBlockLayoutMetrics.cornerResizeSize,
            y: bounds.maxY - MapBlockLayoutMetrics.cornerResizeSize,
            width: MapBlockLayoutMetrics.cornerResizeSize,
            height: MapBlockLayoutMetrics.cornerResizeSize
        )
        addCursorRect(cornerRect, cursor: NSCursor.compatFrameResize(position: "bottomRight"))

        let rightRect = CGRect(
            x: bounds.maxX - MapBlockLayoutMetrics.resizeThickness,
            y: bounds.minY,
            width: MapBlockLayoutMetrics.resizeThickness,
            height: max(0, bounds.height - MapBlockLayoutMetrics.cornerResizeSize)
        )
        addCursorRect(rightRect, cursor: NSCursor.compatFrameResize(position: "right"))

        let bottomRect = CGRect(
            x: bounds.minX,
            y: bounds.maxY - MapBlockLayoutMetrics.resizeThickness,
            width: max(0, bounds.width - MapBlockLayoutMetrics.cornerResizeSize),
            height: MapBlockLayoutMetrics.resizeThickness
        )
        addCursorRect(bottomRect, cursor: NSCursor.compatFrameResize(position: "bottom"))
    }

    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        guard isInteractionEnabled else { return nil }
        let localPoint = convert(windowPoint, from: nil)
        guard let edge = resizeEdge(at: localPoint) else { return nil }
        return cursor(for: edge)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        if isDraggingResize || (isInteractionEnabled && resizeEdge(at: localPoint) != nil) {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled else {
            super.mouseDown(with: event)
            return
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let edge = resizeEdge(at: localPoint) else {
            super.mouseDown(with: event)
            return
        }
        beginResize(on: edge, with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingResize else {
            super.mouseDragged(with: event)
            return
        }
        continueResize(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDraggingResize else {
            super.mouseUp(with: event)
            return
        }
        finishResize()
    }

    func expectedOpenInMapsFrame() -> CGRect {
        MapBlockLayoutMetrics.openInMapsFrame(in: bounds)
    }

    private func updateInteractionState() {
        hostedState.isInteractionEnabled = isInteractionEnabled
        rightResizeHandle.isHidden = !isInteractionEnabled
        bottomResizeHandle.isHidden = !isInteractionEnabled
        cornerResizeHandle.isHidden = !isInteractionEnabled
    }

    private func updateBorderAndShadow() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let borderColor = isDark
            ? NSColor.white.withAlphaComponent(0.06).cgColor
            : NSColor.black.withAlphaComponent(0.08).cgColor
        borderLayer.borderColor = borderColor
        borderLayer.cornerRadius = MapBlockData.cornerRadius
        containerView.layer?.borderColor = borderColor
        containerView.layer?.borderWidth = 1
        containerView.layer?.cornerRadius = MapBlockData.cornerRadius

        let path = CGPath(
            roundedRect: bounds,
            cornerWidth: MapBlockData.cornerRadius,
            cornerHeight: MapBlockData.cornerRadius,
            transform: nil
        )
        let showShadow = LiquidPaperShadowChrome.shouldShowPaperShadow(
            effectiveAppearance: effectiveAppearance
        )
        LiquidPaperShadowChrome.applyPaperShadow(to: layer, path: path, enabled: showShadow)
        CATransaction.commit()
    }

    private func configureResizeHandles() {
        let handleConfigurations: [(MapResizeHandleView, ResizeEdge)] = [
            (rightResizeHandle, .right),
            (bottomResizeHandle, .bottom),
            (cornerResizeHandle, .corner),
        ]

        for (handle, edge) in handleConfigurations {
            handle.onMouseDown = { [weak self] event in
                self?.beginResize(on: edge, with: event)
            }
            handle.onMouseDragged = { [weak self] event in
                self?.continueResize(with: event)
            }
            handle.onMouseUp = { [weak self] _ in
                self?.finishResize()
            }
            addSubview(handle)
        }
    }

    private func layoutResizeHandles() {
        let thickness = MapBlockLayoutMetrics.resizeThickness
        let cornerSize = MapBlockLayoutMetrics.cornerResizeSize

        cornerResizeHandle.frame = CGRect(
            x: bounds.maxX - cornerSize,
            y: bounds.maxY - cornerSize,
            width: cornerSize,
            height: cornerSize
        )
        rightResizeHandle.frame = CGRect(
            x: bounds.maxX - thickness,
            y: bounds.minY,
            width: thickness,
            height: max(0, bounds.height - cornerSize)
        )
        bottomResizeHandle.frame = CGRect(
            x: bounds.minX,
            y: bounds.maxY - thickness,
            width: max(0, bounds.width - cornerSize),
            height: thickness
        )
    }

    private func beginResize(on edge: ResizeEdge, with event: NSEvent) {
        guard isInteractionEnabled else { return }
        isDraggingResize = true
        activeResizeEdge = edge
        dragStartPoint = event.locationInWindow
        dragStartWidth = bounds.width
        cursor(for: edge).push()
    }

    private func continueResize(with event: NSEvent) {
        guard isDraggingResize, let activeResizeEdge else { return }

        let aspectRatio = MapBlockData.aspectHeightRatio
        let minimumWidth = MapBlockLayoutMetrics.minimumDisplayWidth(
            for: max(containerWidth, 1)
        )

        let proposedWidth: CGFloat
        switch activeResizeEdge {
        case .right, .corner:
            let deltaX = event.locationInWindow.x - dragStartPoint.x
            proposedWidth = dragStartWidth + deltaX
        case .bottom:
            let deltaY = dragStartPoint.y - event.locationInWindow.y
            proposedWidth = dragStartWidth + (deltaY / aspectRatio)
        }

        let clampedWidth = max(minimumWidth, min(containerWidth, proposedWidth))
        let clampedHeight = clampedWidth * aspectRatio
        frame = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: clampedWidth,
            height: clampedHeight
        )
    }

    private func finishResize() {
        guard isDraggingResize else { return }

        NSCursor.pop()
        isDraggingResize = false
        activeResizeEdge = nil

        guard containerWidth > 0 else { return }
        var updatedData = mapData
        updatedData.widthRatio = max(
            MapBlockData.minimumWidthRatio,
            frame.width / containerWidth
        )
        handleHostedDataChange(updatedData)
    }

    private func handleHostedDataChange(_ updatedData: MapBlockData) {
        hostedState.mapData = updatedData
        isApplyingHostedStateUpdate = true
        mapData = updatedData
        isApplyingHostedStateUpdate = false
        onDataChanged?(updatedData)
    }

    private func requestSnapshotRefresh() {
        let snapshotSize = CGSize(
            width: max(bounds.width, 1),
            height: max(bounds.height, 1)
        )
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        MapBlockSnapshotRenderer.requestSnapshot(
            for: mapData,
            size: snapshotSize,
            appearance: appearance,
            controlView: parentTextView
        )
    }

    private func cursor(for edge: ResizeEdge) -> NSCursor {
        switch edge {
        case .right:
            NSCursor.compatFrameResize(position: "right")
        case .bottom:
            NSCursor.compatFrameResize(position: "bottom")
        case .corner:
            NSCursor.compatFrameResize(position: "bottomRight")
        }
    }

    private func resizeEdge(at point: NSPoint) -> ResizeEdge? {
        guard bounds.contains(point) else { return nil }
        let exclusionFrames = [
            MapBlockLayoutMetrics.openInMapsFrame(in: bounds),
        ].map { $0.insetBy(dx: -2, dy: -2) }
        guard exclusionFrames.allSatisfy({ !$0.contains(point) }) else { return nil }

        let onRight = point.x >= bounds.maxX - MapBlockLayoutMetrics.resizeThickness
        let onBottom = point.y >= bounds.maxY - MapBlockLayoutMetrics.resizeThickness
        if onRight && onBottom { return .corner }
        if onRight { return .right }
        if onBottom { return .bottom }
        return nil
    }
}

private final class MapResizeHandleView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MapResizeHandleView does not support init(coder:)")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }
}
