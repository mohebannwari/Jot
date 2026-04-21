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

struct MapBlockData: Equatable {
    static let markupPrefix = "[[map|"
    static let defaultWidthRatio: CGFloat = 0.33
    static let minWidth: CGFloat = 100
    static let cornerRadius: CGFloat = 22
    static let aspectHeightRatio: CGFloat = 3.0 / 4.0
    static let initialRegionDistanceMeters: CLLocationDistance = 1_000

    var title: String
    var subtitle: String
    var pinCoordinate: CLLocationCoordinate2D
    var viewportCenter: CLLocationCoordinate2D
    var viewportSpan: MKCoordinateSpan
    var widthRatio: CGFloat

    private static let markupLocale = Locale(identifier: "en_US_POSIX")

    init(
        title: String,
        subtitle: String,
        pinCoordinate: CLLocationCoordinate2D,
        viewportCenter: CLLocationCoordinate2D,
        viewportSpan: MKCoordinateSpan,
        widthRatio: CGFloat
    ) {
        self.title = Self.sanitizedTextComponent(title)
        self.subtitle = Self.sanitizedTextComponent(subtitle)
        self.pinCoordinate = pinCoordinate
        self.viewportCenter = viewportCenter
        self.viewportSpan = viewportSpan
        self.widthRatio = widthRatio
    }

    static func initial(
        title: String,
        subtitle: String,
        coordinate: CLLocationCoordinate2D,
        widthRatio: CGFloat = defaultWidthRatio
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
            widthRatio: widthRatio
        )
    }

    var displayTitle: String {
        title.isEmpty ? "Pinned Location" : title
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
        ]
        return "\(Self.markupPrefix)\(components.joined(separator: "|"))]]"
    }

    static func deserialize(from token: String) -> MapBlockData? {
        guard token.hasPrefix(markupPrefix), token.hasSuffix("]]") else { return nil }
        let payload = String(token.dropFirst(markupPrefix.count).dropLast(2))
        let parts = payload.components(separatedBy: "|")
        guard parts.count == 9 else { return nil }

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
            widthRatio: CGFloat(widthRatio)
        )
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

    private static func formatDecimal<T: BinaryFloatingPoint>(_ value: T, digits: Int) -> String {
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
    }
}
