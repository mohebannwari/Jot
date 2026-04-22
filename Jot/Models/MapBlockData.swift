//
//  MapBlockData.swift
//  Jot
//
//  Data model for inline MapKit blocks embedded in the rich text editor.
//

import CoreGraphics
import CoreLocation
import Foundation
import MapKit

enum MapDisplayMode: String, CaseIterable, Equatable, Hashable {
    case explore
    case driving
    case transit
    case satellite

    var title: String {
        switch self {
        case .explore:
            "Explore"
        case .driving:
            "Driving"
        case .transit:
            "Transit"
        case .satellite:
            "Satellite"
        }
    }

    var mapsFrameValue: String { rawValue }

    func makeMapConfiguration() -> MKMapConfiguration {
        switch self {
        case .explore:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .default
            configuration.showsTraffic = false
            configuration.pointOfInterestFilter = .includingAll
            return configuration
        case .driving:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .default
            configuration.showsTraffic = true
            configuration.pointOfInterestFilter = .includingAll
            return configuration
        case .transit:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .default
            configuration.showsTraffic = false
            configuration.pointOfInterestFilter = MKPointOfInterestFilter(
                including: [MKPointOfInterestCategory.publicTransport]
            )
            return configuration
        case .satellite:
            return MKImageryMapConfiguration(elevationStyle: .flat)
        }
    }
}

struct MapBlockData: Equatable {
    static let markupPrefix = "[[map|"
    static let defaultWidthRatio: CGFloat = 0.33
    static let minimumWidthRatio: CGFloat = defaultWidthRatio
    static let cornerRadius: CGFloat = 22
    static let aspectHeightRatio: CGFloat = 3.0 / 4.0
    static let initialRegionDistanceMeters: CLLocationDistance = 1_000

    var title: String
    var subtitle: String
    var pinCoordinate: CLLocationCoordinate2D
    var viewportCenter: CLLocationCoordinate2D
    var viewportSpan: MKCoordinateSpan
    var widthRatio: CGFloat
    var displayMode: MapDisplayMode
    var headingDegrees: CLLocationDirection

    private static let markupLocale = Locale(identifier: "en_US_POSIX")

    init(
        title: String,
        subtitle: String,
        pinCoordinate: CLLocationCoordinate2D,
        viewportCenter: CLLocationCoordinate2D,
        viewportSpan: MKCoordinateSpan,
        widthRatio: CGFloat,
        displayMode: MapDisplayMode = .explore,
        headingDegrees: CLLocationDirection = 0
    ) {
        self.title = Self.sanitizedTextComponent(title)
        self.subtitle = Self.sanitizedTextComponent(subtitle)
        self.pinCoordinate = pinCoordinate
        self.viewportCenter = viewportCenter
        self.viewportSpan = viewportSpan
        self.widthRatio = widthRatio
        self.displayMode = displayMode
        self.headingDegrees = Self.normalizedHeading(headingDegrees)
    }

    static func initial(
        title: String,
        subtitle: String,
        coordinate: CLLocationCoordinate2D,
        widthRatio: CGFloat = defaultWidthRatio,
        displayMode: MapDisplayMode = .explore
    ) -> MapBlockData {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: initialRegionDistanceMeters,
            longitudinalMeters: initialRegionDistanceMeters
        )
        return MapBlockData(
            title: title,
            subtitle: subtitle,
            pinCoordinate: coordinate,
            viewportCenter: region.center,
            viewportSpan: region.span,
            widthRatio: widthRatio,
            displayMode: displayMode,
            headingDegrees: 0
        )
    }

    var displayTitle: String {
        title.isEmpty ? "Pinned Location" : title
    }

    static func minimumDisplayWidth(for containerWidth: CGFloat) -> CGFloat {
        let clampedContainerWidth = max(containerWidth, 1)
        return min(
            clampedContainerWidth,
            clampedContainerWidth * minimumWidthRatio
        )
    }

    func serialize() -> String {
        let components = [
            Self.sanitizedTextComponent(title),
            Self.sanitizedTextComponent(subtitle),
            Self.formatDecimal(pinCoordinate.latitude, digits: 6),
            Self.formatDecimal(pinCoordinate.longitude, digits: 6),
            Self.formatDecimal(viewportCenter.latitude, digits: 6),
            Self.formatDecimal(viewportCenter.longitude, digits: 6),
            Self.formatDecimal(viewportSpan.latitudeDelta, digits: 6),
            Self.formatDecimal(viewportSpan.longitudeDelta, digits: 6),
            Self.formatDecimal(widthRatio, digits: 4),
            displayMode.rawValue,
            Self.formatDecimal(headingDegrees, digits: 4),
        ]
        return "\(Self.markupPrefix)\(components.joined(separator: "|"))]]"
    }

    static func deserialize(from token: String) -> MapBlockData? {
        guard token.hasPrefix(markupPrefix), token.hasSuffix("]]") else { return nil }
        let payload = String(token.dropFirst(markupPrefix.count).dropLast(2))
        let parts = payload.components(separatedBy: "|")
        guard parts.count == 9 || parts.count == 11 else { return nil }

        guard
            let pinLat = Double(parts[2]),
            let pinLon = Double(parts[3]),
            let centerLat = Double(parts[4]),
            let centerLon = Double(parts[5]),
            let latDelta = Double(parts[6]),
            let lonDelta = Double(parts[7]),
            let widthRatio = Double(parts[8])
        else {
            return nil
        }

        let displayMode: MapDisplayMode
        let headingDegrees: CLLocationDirection
        if parts.count == 11 {
            guard let decodedMode = MapDisplayMode(rawValue: parts[9]),
                  let decodedHeading = Double(parts[10]) else {
                return nil
            }
            displayMode = decodedMode
            headingDegrees = decodedHeading
        } else {
            displayMode = .explore
            headingDegrees = 0
        }

        let pinCoordinate = CLLocationCoordinate2D(latitude: pinLat, longitude: pinLon)
        let viewportCenter = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        guard CLLocationCoordinate2DIsValid(pinCoordinate),
              CLLocationCoordinate2DIsValid(viewportCenter) else {
            return nil
        }

        return MapBlockData(
            title: parts[0],
            subtitle: parts[1],
            pinCoordinate: pinCoordinate,
            viewportCenter: viewportCenter,
            viewportSpan: MKCoordinateSpan(
                latitudeDelta: max(latDelta, 0.000_001),
                longitudeDelta: max(lonDelta, 0.000_001)
            ),
            widthRatio: CGFloat(widthRatio),
            displayMode: displayMode,
            headingDegrees: headingDegrees
        )
    }

    static func normalizedHeading(_ headingDegrees: CLLocationDirection) -> CLLocationDirection {
        let bounded = headingDegrees.truncatingRemainder(dividingBy: 360)
        return bounded >= 0 ? bounded : bounded + 360
    }

    static func sanitizedTextComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "]]", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    fileprivate static func formatDecimal<T: BinaryFloatingPoint>(_ value: T, digits: Int) -> String {
        String(
            format: "%.\(digits)f",
            locale: markupLocale,
            Double(value)
        )
    }

    static func == (lhs: MapBlockData, rhs: MapBlockData) -> Bool {
        lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.pinCoordinate.latitude == rhs.pinCoordinate.latitude
            && lhs.pinCoordinate.longitude == rhs.pinCoordinate.longitude
            && lhs.viewportCenter.latitude == rhs.viewportCenter.latitude
            && lhs.viewportCenter.longitude == rhs.viewportCenter.longitude
            && lhs.viewportSpan.latitudeDelta == rhs.viewportSpan.latitudeDelta
            && lhs.viewportSpan.longitudeDelta == rhs.viewportSpan.longitudeDelta
            && lhs.widthRatio == rhs.widthRatio
            && lhs.displayMode == rhs.displayMode
            && lhs.headingDegrees == rhs.headingDegrees
    }
}

enum MapBlockOpenInMapsURLBuilder {
    static func url(for data: MapBlockData) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/frame"
        components.queryItems = [
            URLQueryItem(
                name: "map",
                value: data.displayMode.mapsFrameValue
            ),
            URLQueryItem(
                name: "center",
                value: "\(MapBlockData.formatDecimal(data.viewportCenter.latitude, digits: 6)),\(MapBlockData.formatDecimal(data.viewportCenter.longitude, digits: 6))"
            ),
            URLQueryItem(
                name: "span",
                value: "\(MapBlockData.formatDecimal(data.viewportSpan.longitudeDelta, digits: 6)),\(MapBlockData.formatDecimal(data.viewportSpan.latitudeDelta, digits: 6))"
            ),
            URLQueryItem(
                name: "heading",
                value: MapBlockData.formatDecimal(
                    MapBlockData.normalizedHeading(data.headingDegrees),
                    digits: 4
                )
            ),
        ]
        return components.url
    }
}
