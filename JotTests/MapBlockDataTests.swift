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
            widthRatio: 0.3333
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
            widthRatio: 0.375
        )

        let serialized = data.serialize()

        XCTAssertTrue(serialized.hasSuffix("|0.3750]]"), serialized)
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
            widthRatio: 0.2199
        )

        guard let decoded = MapBlockData.deserialize(from: data.serialize()) else {
            return XCTFail("deserialize failed")
        }

        XCTAssertEqual(decoded.viewportCenter.latitude, data.viewportCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(decoded.viewportCenter.longitude, data.viewportCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(decoded.viewportSpan.latitudeDelta, data.viewportSpan.latitudeDelta, accuracy: 0.000001)
        XCTAssertEqual(decoded.viewportSpan.longitudeDelta, data.viewportSpan.longitudeDelta, accuracy: 0.000001)
    }
}
