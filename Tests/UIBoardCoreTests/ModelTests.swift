import CoreGraphics
import XCTest
@testable import UIBoardCore

final class ModelTests: XCTestCase {
    func testPaletteCyclesByIndex() {
        XCTAssertEqual(Palette.rgb(at: 0), 0xFF3B30)
        XCTAssertEqual(Palette.rgb(at: 6), Palette.rgb(at: 0))
    }

    func testZeroSizeRectIsPin() {
        XCTAssertTrue(Mark(rect: CGRect(x: 10, y: 20, width: 0, height: 0)).isPin)
        XCTAssertFalse(Mark(rect: CGRect(x: 10, y: 20, width: 5, height: 0)).isPin)
    }
}
