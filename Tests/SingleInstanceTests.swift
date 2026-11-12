import XCTest
@testable import Adalmon

final class SingleInstanceTests: XCTestCase {
    func testOnlyHigherPIDYields() {
        XCTAssertNil(SingleInstance.pick(otherPIDs: [], myPID: 100))
        XCTAssertEqual(SingleInstance.pick(otherPIDs: [90], myPID: 100), 90, "eski kopya varsa yeni çıkar")
        XCTAssertNil(SingleInstance.pick(otherPIDs: [110], myPID: 100), "ben daha eskiysem kalırım")
        XCTAssertEqual(SingleInstance.pick(otherPIDs: [120, 95, 80], myPID: 100), 80)
    }
}
