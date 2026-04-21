//
//  MapBlockOverlayView.swift
//  Jot
//

import AppKit
import MapKit
import QuartzCore

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

        let snapshotter = MKMapSnapshotter(options: makeOptions(for: data, size: size, appearance: appearance))
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

        let snapshotter = MKMapSnapshotter(options: makeOptions(for: data, size: size, appearance: appearance))
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
        options.appearance = appearance
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.emphasisStyle = .default
        options.preferredConfiguration = configuration
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

final class MapBlockOverlayView: NSView, MKMapViewDelegate {
    var mapData: MapBlockData {
        didSet {
            if annotationChanged(from: oldValue, to: mapData) {
                updateAnnotation()
            }
            applyRegionIfNeeded(oldValue: oldValue)
        }
    }

    weak var parentTextView: NSTextView?
    var containerWidth: CGFloat = 0
    var isInteractionEnabled: Bool = true {
        didSet { updateInteractionState() }
    }
    var onDataChanged: ((MapBlockData) -> Void)?

    private let containerView = NSView()
    private let mapView = MKMapView()
    private let borderLayer = CALayer()

    private let edgeZone: CGFloat = 40
    private let edgeOutset: CGFloat = 6

    private enum ResizeEdge { case right, bottom, corner }

    private var activeResizeEdge: ResizeEdge?
    private var isDraggingResize = false
    private var dragStartPoint: CGPoint = .zero
    private var dragStartWidth: CGFloat = 0
    private var isApplyingProgrammaticRegion = false

    private var translucencyObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }

    init(mapData: MapBlockData) {
        self.mapData = mapData
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.cornerRadius = MapBlockData.cornerRadius
        addSubview(containerView)

        mapView.delegate = self
        mapView.autoresizingMask = [.width, .height]
        mapView.frame = bounds
        containerView.addSubview(mapView)

        borderLayer.cornerCurve = .continuous
        borderLayer.cornerRadius = MapBlockData.cornerRadius
        borderLayer.borderWidth = 1
        borderLayer.masksToBounds = true
        containerView.layer?.addSublayer(borderLayer)

        refreshConfiguration()
        updateAnnotation()
        applyRegion(force: true)
        updateBorderAndShadow()
        updateInteractionState()

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
        mapView.frame = containerView.bounds
        borderLayer.frame = containerView.bounds
        updateBorderAndShadow()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyRegion(force: true)
        updateBorderAndShadow()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshConfiguration()
        updateBorderAndShadow()
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
            x: bounds.maxX - edgeZone + edgeOutset,
            y: bounds.maxY - edgeZone + edgeOutset,
            width: edgeZone,
            height: edgeZone
        )
        addCursorRect(cornerRect, cursor: NSCursor.compatFrameResize(position: "bottomRight"))

        let rightRect = CGRect(
            x: bounds.maxX - edgeZone + edgeOutset,
            y: bounds.minY,
            width: edgeZone,
            height: bounds.height - edgeZone + edgeOutset
        )
        addCursorRect(rightRect, cursor: NSCursor.compatFrameResize(position: "right"))

        let bottomRect = CGRect(
            x: bounds.minX,
            y: bounds.maxY - edgeZone + edgeOutset,
            width: bounds.width - edgeZone + edgeOutset,
            height: edgeZone
        )
        addCursorRect(bottomRect, cursor: NSCursor.compatFrameResize(position: "bottom"))
    }

    func cursorForPoint(_ windowPoint: CGPoint) -> NSCursor? {
        let localPoint = convert(windowPoint, from: nil)
        guard let edge = resizeEdge(at: localPoint) else { return nil }
        return switch edge {
        case .right:
            NSCursor.compatFrameResize(position: "right")
        case .bottom:
            NSCursor.compatFrameResize(position: "bottom")
        case .corner:
            NSCursor.compatFrameResize(position: "bottomRight")
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let expandedBounds = bounds.insetBy(dx: -edgeOutset, dy: -edgeOutset)
        guard expandedBounds.contains(point) else { return nil }
        if isDraggingResize || resizeEdge(at: point) != nil {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let edge = resizeEdge(at: localPoint) else {
            super.mouseDown(with: event)
            return
        }

        isDraggingResize = true
        activeResizeEdge = edge
        dragStartPoint = event.locationInWindow
        dragStartWidth = bounds.width

        switch edge {
        case .right:
            NSCursor.compatFrameResize(position: "right").push()
        case .bottom:
            NSCursor.compatFrameResize(position: "bottom").push()
        case .corner:
            NSCursor.compatFrameResize(position: "bottomRight").push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingResize, let activeResizeEdge else {
            super.mouseDragged(with: event)
            return
        }

        let aspectRatio = MapBlockData.aspectHeightRatio
        let minimumWidth = min(MapBlockData.minWidth, max(containerWidth, 1))

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

    override func mouseUp(with event: NSEvent) {
        guard isDraggingResize else {
            super.mouseUp(with: event)
            return
        }

        NSCursor.pop()
        isDraggingResize = false
        activeResizeEdge = nil

        guard containerWidth > 0 else { return }
        var updatedData = mapData
        updatedData.widthRatio = frame.width / containerWidth
        mapData = updatedData
        onDataChanged?(updatedData)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard !isApplyingProgrammaticRegion else { return }

        var updatedData = mapData
        updatedData.viewportCenter = mapView.region.center
        updatedData.viewportSpan = mapView.region.span
        mapData = updatedData
        onDataChanged?(updatedData)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { return nil }

        let reuseIdentifier = "MapBlockPin"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier)
            as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
        view.annotation = annotation
        view.canShowCallout = false
        view.markerTintColor = .systemRed
        return view
    }

    private func updateInteractionState() {
        mapView.isScrollEnabled = isInteractionEnabled
        mapView.isZoomEnabled = isInteractionEnabled
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
    }

    private func refreshConfiguration() {
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.emphasisStyle = .default
        mapView.preferredConfiguration = configuration
    }

    private func updateAnnotation() {
        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = mapData.pinCoordinate
        annotation.title = mapData.title.isEmpty ? nil : mapData.title
        annotation.subtitle = mapData.subtitle.isEmpty ? nil : mapData.subtitle
        mapView.addAnnotation(annotation)
    }

    private func applyRegionIfNeeded(oldValue: MapBlockData) {
        let regionChanged = oldValue.viewportCenter.latitude != mapData.viewportCenter.latitude
            || oldValue.viewportCenter.longitude != mapData.viewportCenter.longitude
            || oldValue.viewportSpan.latitudeDelta != mapData.viewportSpan.latitudeDelta
            || oldValue.viewportSpan.longitudeDelta != mapData.viewportSpan.longitudeDelta
        if regionChanged {
            applyRegion(force: false)
        }
    }

    private func applyRegion(force: Bool) {
        guard force || window != nil else { return }
        isApplyingProgrammaticRegion = true
        mapView.setRegion(
            MKCoordinateRegion(center: mapData.viewportCenter, span: mapData.viewportSpan),
            animated: false
        )
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingProgrammaticRegion = false
        }
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

    private func annotationChanged(from oldValue: MapBlockData, to newValue: MapBlockData) -> Bool {
        oldValue.title != newValue.title
            || oldValue.subtitle != newValue.subtitle
            || oldValue.pinCoordinate.latitude != newValue.pinCoordinate.latitude
            || oldValue.pinCoordinate.longitude != newValue.pinCoordinate.longitude
    }

    private func resizeEdge(at point: NSPoint) -> ResizeEdge? {
        let expandedBounds = bounds.insetBy(dx: -edgeOutset, dy: -edgeOutset)
        guard expandedBounds.contains(point) else { return nil }

        let onRight = point.x >= bounds.maxX - edgeZone + edgeOutset
        let onBottom = point.y >= bounds.maxY - edgeZone + edgeOutset
        if onRight && onBottom { return .corner }
        if onRight { return .right }
        if onBottom { return .bottom }
        return nil
    }
}
