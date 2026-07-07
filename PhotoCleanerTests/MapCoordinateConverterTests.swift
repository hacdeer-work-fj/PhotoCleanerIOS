import CoreLocation
import XCTest
@testable import PhotoCleaner

final class MapCoordinateConverterTests: XCTestCase {
    func testMainlandChinaCoordinateIsAdjustedForMapDisplay() {
        let coordinate = CLLocationCoordinate2D(latitude: 39.908823, longitude: 116.397470)

        let converted = MapCoordinateConverter.displayCoordinate(for: coordinate)

        XCTAssertGreaterThan(abs(converted.latitude - coordinate.latitude), 0.001)
        XCTAssertGreaterThan(abs(converted.longitude - coordinate.longitude), 0.001)
    }

    func testOverseasCoordinateIsNotAdjusted() {
        let coordinate = CLLocationCoordinate2D(latitude: 51.507222, longitude: -0.1275)

        let converted = MapCoordinateConverter.displayCoordinate(for: coordinate)

        XCTAssertEqual(converted.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(converted.longitude, coordinate.longitude, accuracy: 0.000001)
    }

    func testHongKongCoordinateIsNotAdjusted() {
        let coordinate = CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)

        let converted = MapCoordinateConverter.displayCoordinate(for: coordinate)

        XCTAssertEqual(converted.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(converted.longitude, coordinate.longitude, accuracy: 0.000001)
    }
}
