import AppKit
import CoreLocation
import MapKit
import XCTest

@testable import Jot

final class MapBlockDataTests: XCTestCase {

    func testRoundTripSerializationPreservesCoordinatesAndLabels() {
        let data = MapBlockData(
            title: "Cafe",
            subtitle: "Berlin Mitte",
            pinCoordinate: CLLocationCoordinate2D(latitude: 52.520008, longitude: 13.404954),
            viewportCenter: CLLocationCoordinate2D(latitude: 52.520100, longitude: 13.405100),
            viewportSpan: MKCoordinateSpan(latitudeDelta: 0.012345, longitudeDelta: 0.023456),
            widthRatio: 0.3333,
            displayMode: .driving,
            headingDegrees: 91.25
        )

        let serialized = data.serialize()
        guard let roundTripped = MapBlockData.deserialize(from: serialized) else {
            return XCTFail("deserialize failed")
        }

        XCTAssertEqual(roundTripped, data)
    }

    func testWidthRatioPersistsWithFixedPrecision() {
        let data = MapBlockData.initial(
            title: "Library",
            subtitle: "",
            coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            widthRatio: 0.375,
            displayMode: .satellite
        )

        let serialized = data.serialize()

        XCTAssertTrue(serialized.hasSuffix("|0.3750|satellite|0.0000]]"), serialized)
        guard let decoded = MapBlockData.deserialize(from: serialized) else {
            return XCTFail("deserialize failed")
        }
        XCTAssertEqual(decoded.widthRatio, 0.375, accuracy: 0.0001)
    }

    func testViewportPrecisionSurvivesRoundTrip() {
        let data = MapBlockData(
            title: "Pin",
            subtitle: "",
            pinCoordinate: CLLocationCoordinate2D(latitude: 37.33182, longitude: -122.03118),
            viewportCenter: CLLocationCoordinate2D(latitude: 37.33191, longitude: -122.03127),
            viewportSpan: MKCoordinateSpan(latitudeDelta: 0.004321, longitudeDelta: 0.005432),
            widthRatio: 0.2199,
            displayMode: .transit,
            headingDegrees: 270
        )

        guard let decoded = MapBlockData.deserialize(from: data.serialize()) else {
            return XCTFail("deserialize failed")
        }

        XCTAssertEqual(decoded.viewportCenter.latitude, data.viewportCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(decoded.viewportCenter.longitude, data.viewportCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(decoded.viewportSpan.latitudeDelta, data.viewportSpan.latitudeDelta, accuracy: 0.000001)
        XCTAssertEqual(decoded.viewportSpan.longitudeDelta, data.viewportSpan.longitudeDelta, accuracy: 0.000001)
    }

    func testLegacyMapTokenDefaultsToExploreModeAndNorthHeading() {
        let legacyToken = "[[map|Park|North Gate|52.520008|13.404954|52.520108|13.405054|0.010000|0.020000|0.3333]]"

        guard let decoded = MapBlockData.deserialize(from: legacyToken) else {
            return XCTFail("deserialize failed")
        }

        XCTAssertEqual(decoded.displayMode, .explore)
        XCTAssertEqual(decoded.headingDegrees, 0, accuracy: 0.0001)
    }

    func testHeadingNormalizesIntoPositiveCompassRange() {
        let data = MapBlockData(
            title: "Pin",
            subtitle: "",
            pinCoordinate: CLLocationCoordinate2D(latitude: 37.33182, longitude: -122.03118),
            viewportCenter: CLLocationCoordinate2D(latitude: 37.33191, longitude: -122.03127),
            viewportSpan: MKCoordinateSpan(latitudeDelta: 0.004321, longitudeDelta: 0.005432),
            widthRatio: 0.3333,
            displayMode: .explore,
            headingDegrees: -90
        )

        XCTAssertEqual(data.headingDegrees, 270, accuracy: 0.0001)
    }

    func testOpenInMapsURLPreservesModeHeadingAndViewport() {
        let data = MapBlockData(
            title: "Museum",
            subtitle: "Downtown",
            pinCoordinate: CLLocationCoordinate2D(latitude: 52.520008, longitude: 13.404954),
            viewportCenter: CLLocationCoordinate2D(latitude: 52.520108, longitude: 13.405054),
            viewportSpan: MKCoordinateSpan(latitudeDelta: 0.010000, longitudeDelta: 0.020000),
            widthRatio: 0.3333,
            displayMode: .transit,
            headingDegrees: 123.4567
        )

        guard let url = MapBlockOpenInMapsURLBuilder.url(for: data),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return XCTFail("failed to build url")
        }

        XCTAssertEqual(url.host, "maps.apple.com")
        XCTAssertEqual(url.path, "/frame")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["map"], "transit")
        XCTAssertEqual(query["center"], "52.520108,13.405054")
        XCTAssertEqual(query["span"], "0.020000,0.010000")
        XCTAssertEqual(query["heading"], "123.4567")
    }

    func testMapDisplayModeConfigurationMappingMatchesExpectedPublicModes() throws {
        let explore = MapDisplayMode.explore.makeMapConfiguration()
        let driving = MapDisplayMode.driving.makeMapConfiguration()
        let transit = MapDisplayMode.transit.makeMapConfiguration()
        let satellite = MapDisplayMode.satellite.makeMapConfiguration()

        XCTAssertTrue(explore is MKStandardMapConfiguration)
        XCTAssertTrue(driving is MKStandardMapConfiguration)
        XCTAssertTrue(transit is MKStandardMapConfiguration)
        XCTAssertTrue(satellite is MKImageryMapConfiguration)

        let drivingConfig = try XCTUnwrap(driving as? MKStandardMapConfiguration)
        let transitConfig = try XCTUnwrap(transit as? MKStandardMapConfiguration)
        XCTAssertTrue(drivingConfig.showsTraffic)
        XCTAssertNotNil(transitConfig.pointOfInterestFilter)
    }

    func testSnapshotCacheIdentifierChangesWhenModeOrHeadingChanges() {
        // ``NSAppearance.current`` is optional on newer SDKs; fall back to the app appearance for a stable value.
        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.current ?? NSApp.effectiveAppearance
        let baseData = MapBlockData(
            title: "Museum",
            subtitle: "Downtown",
            pinCoordinate: CLLocationCoordinate2D(latitude: 52.520008, longitude: 13.404954),
            viewportCenter: CLLocationCoordinate2D(latitude: 52.520108, longitude: 13.405054),
            viewportSpan: MKCoordinateSpan(latitudeDelta: 0.010000, longitudeDelta: 0.020000),
            widthRatio: 0.3333,
            displayMode: .explore,
            headingDegrees: 0
        )
        let headingChangedData = MapBlockData(
            title: baseData.title,
            subtitle: baseData.subtitle,
            pinCoordinate: baseData.pinCoordinate,
            viewportCenter: baseData.viewportCenter,
            viewportSpan: baseData.viewportSpan,
            widthRatio: baseData.widthRatio,
            displayMode: .explore,
            headingDegrees: 45
        )
        let modeChangedData = MapBlockData(
            title: baseData.title,
            subtitle: baseData.subtitle,
            pinCoordinate: baseData.pinCoordinate,
            viewportCenter: baseData.viewportCenter,
            viewportSpan: baseData.viewportSpan,
            widthRatio: baseData.widthRatio,
            displayMode: .satellite,
            headingDegrees: 0
        )

        let baseIdentifier = MapBlockSnapshotRenderer.cacheIdentifier(
            for: baseData,
            size: CGSize(width: 264, height: 198),
            appearance: appearance
        )
        let headingIdentifier = MapBlockSnapshotRenderer.cacheIdentifier(
            for: headingChangedData,
            size: CGSize(width: 264, height: 198),
            appearance: appearance
        )
        let modeIdentifier = MapBlockSnapshotRenderer.cacheIdentifier(
            for: modeChangedData,
            size: CGSize(width: 264, height: 198),
            appearance: appearance
        )

        XCTAssertNotEqual(baseIdentifier, headingIdentifier)
        XCTAssertNotEqual(baseIdentifier, modeIdentifier)
    }

    func testMinimumDisplayWidthMatchesDefaultInsertionWidth() {
        let containerWidth: CGFloat = 720

        XCTAssertEqual(
            MapBlockData.minimumWidthRatio,
            MapBlockData.defaultWidthRatio,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            MapBlockData.minimumDisplayWidth(for: containerWidth),
            containerWidth * MapBlockData.defaultWidthRatio,
            accuracy: 0.0001
        )
    }
}
