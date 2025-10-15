import XCTest
@testable import Ncurses

final class NcursesTests: XCTestCase {
  func testLink() {
    // simple présence symboles
    XCTAssertNotNil(Ncurses.start) 
  }
}
