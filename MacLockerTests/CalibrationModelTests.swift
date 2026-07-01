@testable import MacLocker
import XCTest

final class CalibrationModelTests: XCTestCase {
    func testCalibrationMidpointCalculation() throws {
        let result = try CalibrationModel.calibrate(
            nearRSSI: [-53, -55, -54, -56, -54],
            awayRSSI: [-78, -80, -79, -81, -80]
        )

        XCTAssertEqual(result.nearMedian, -54)
        XCTAssertEqual(result.awayMedian, -80)
        XCTAssertEqual(result.threshold, -67)
    }

    func testCalibrationRejectsOverlappingSamples() {
        XCTAssertThrowsError(
            try CalibrationModel.calibrate(
                nearRSSI: [-63, -64, -62, -63],
                awayRSSI: [-67, -68, -66, -67]
            )
        ) { error in
            XCTAssertEqual(error as? CalibrationError, .overlappingSamples(nearMedian: -63, awayMedian: -67))
        }
    }
}
