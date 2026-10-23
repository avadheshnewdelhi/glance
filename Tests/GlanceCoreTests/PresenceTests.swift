import XCTest
@testable import GlanceCore

final class PresenceTests: XCTestCase {
    func testLeavesAfterDelayAndReturnsOnFirstFace() {
        var p = Presence(awayDelay: 5)
        XCTAssertNil(p.update(faceVisible: true, at: 0))
        var left: TimeInterval?
        var t = 0.0
        while left == nil, t < 10 {
            t += 1.0 / 12
            if p.update(faceVisible: false, at: t) == .left { left = t }
        }
        XCTAssertEqual(left!, 5, accuracy: 1.0 / 12)
        XCTAssertTrue(p.isAway)
        XCTAssertNil(p.update(faceVisible: false, at: 30)) // stays away, no repeated events
        XCTAssertEqual(p.update(faceVisible: true, at: 30.25), .returned)
        XCTAssertFalse(p.isAway)
    }

    func testBriefDropoutsDoNotCountAsLeaving() {
        var p = Presence(awayDelay: 5)
        for i in 0..<600 { // 50 s with the face lost for 2 s out of every 4
            XCTAssertNil(p.update(faceVisible: (i / 24) % 2 == 0, at: Double(i) / 12))
        }
    }

    func testNoFaceFromStartCountsAsAway() {
        var p = Presence(awayDelay: 5)
        XCTAssertNil(p.update(faceVisible: false, at: 100))
        XCTAssertEqual(p.update(faceVisible: false, at: 105), .left)
    }
}
