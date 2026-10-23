import XCTest
@testable import GlanceCore

final class GazeTests: XCTestCase {
    /// Two displays: "L" at yaw -0.3, "R" at yaw +0.3, with a little jitter.
    private func makeCalibration() -> Calibration {
        func cluster(_ yaw: Double, _ pupil: Double) -> [GazeSample] {
            (0..<20).map { i in GazeSample(yaw: yaw + Double(i % 5 - 2) * 0.01, pupil: pupil + Double(i % 3 - 1) * 0.01) }
        }
        return Calibration(samples: ["L": cluster(-0.3, -0.1), "R": cluster(0.3, 0.1)], layout: ["L", "R"])!
    }

    func testCalibrationFitsCentroidsAndSeparates() {
        let c = makeCalibration()
        XCTAssertEqual(c.centroids["L"]![0], -0.3, accuracy: 1e-9)
        XCTAssertEqual(c.centroids["R"]![1], 0.1, accuracy: 1e-9)
        XCTAssertGreaterThan(c.separation, 10)
        XCTAssertLessThan(c.distance(from: GazeSample(yaw: -0.29, pupil: -0.1), to: "L"),
                          c.distance(from: GazeSample(yaw: -0.29, pupil: -0.1), to: "R"))
    }

    func testCalibrationRejectsInsufficientData() {
        let few = Array(repeating: GazeSample(yaw: 0, pupil: 0), count: 3)
        let many = Array(repeating: GazeSample(yaw: 0, pupil: 0), count: 10)
        XCTAssertNil(Calibration(samples: ["L": many], layout: ["L"]))
        XCTAssertNil(Calibration(samples: ["L": many, "R": few], layout: ["L", "R"]))
    }

    func testCalibrationRoundTripsThroughJSON() throws {
        let c = makeCalibration()
        let decoded = try JSONDecoder().decode(Calibration.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(decoded, c)
    }

    func testFirstFixIsAdoptedSilently() {
        let t = GazeTracker(calibration: makeCalibration(), dwell: 0.4)
        XCTAssertNil(t.update(GazeSample(yaw: -0.3, pupil: -0.1), at: 0))
        XCTAssertEqual(t.current, "L")
    }

    func testSwitchesOnlyAfterDwell() {
        let t = GazeTracker(calibration: makeCalibration(), dwell: 0.4)
        _ = t.update(GazeSample(yaw: -0.3, pupil: -0.1), at: 0)
        var switched: [(TimeInterval, String)] = []
        for i in 1...20 {
            let time = Double(i) * 0.1
            if let key = t.update(GazeSample(yaw: 0.3, pupil: 0.1), at: time) { switched.append((time, key)) }
        }
        XCTAssertEqual(switched.count, 1)
        XCTAssertEqual(switched.first?.1, "R")
        XCTAssertGreaterThanOrEqual(switched.first!.0, 0.4)
        XCTAssertLessThan(switched.first!.0, 1.0)
    }

    func testBriefGlanceDoesNotSwitch() {
        let t = GazeTracker(calibration: makeCalibration(), dwell: 0.4)
        _ = t.update(GazeSample(yaw: -0.3, pupil: -0.1), at: 0)
        for i in 1...3 { XCTAssertNil(t.update(GazeSample(yaw: 0.3, pupil: 0.1), at: Double(i) * 0.1)) }
        for i in 4...20 { XCTAssertNil(t.update(GazeSample(yaw: -0.3, pupil: -0.1), at: Double(i) * 0.1)) }
        XCTAssertEqual(t.current, "L")
    }

    func testJitterAtBoundaryDoesNotFlipFlop() {
        for dwell in [0, 0.2] {
            let t = GazeTracker(calibration: makeCalibration(), dwell: dwell)
            _ = t.update(GazeSample(yaw: -0.3, pupil: -0.1), at: 0)
            var switches = 0
            for i in 1...100 {
                let yaw = (i % 2 == 0 ? 0.004 : -0.004)
                if t.update(GazeSample(yaw: yaw, pupil: 0), at: Double(i) * 0.1) != nil { switches += 1 }
            }
            XCTAssertLessThanOrEqual(switches, 1, "dwell \(dwell)")
        }
    }

    func testInstantDelaySwitchesWithinTwoFrames() {
        let t = GazeTracker(calibration: makeCalibration(), dwell: 0)
        _ = t.update(GazeSample(yaw: -0.3, pupil: -0.1), at: 0)
        XCTAssertNil(t.update(GazeSample(yaw: 0.3, pupil: 0.1), at: 1.0 / 12)) // smoothing: still nearer L
        XCTAssertEqual(t.update(GazeSample(yaw: 0.3, pupil: 0.1), at: 2.0 / 12), "R")
    }

    func testFaceLostResetsPendingSwitch() {
        let t = GazeTracker(calibration: makeCalibration(), dwell: 0.4)
        _ = t.update(GazeSample(yaw: -0.3, pupil: -0.1), at: 0)
        _ = t.update(GazeSample(yaw: 0.3, pupil: 0.1), at: 0.1)
        _ = t.update(GazeSample(yaw: 0.3, pupil: 0.1), at: 0.2)
        t.faceLost()
        // The pending timer restarts, so 0.3s after reacquiring isn't enough.
        XCTAssertNil(t.update(GazeSample(yaw: 0.3, pupil: 0.1), at: 0.5))
        XCTAssertNil(t.update(GazeSample(yaw: 0.3, pupil: 0.1), at: 0.8))
        XCTAssertEqual(t.update(GazeSample(yaw: 0.3, pupil: 0.1), at: 0.95), "R")
    }
}
