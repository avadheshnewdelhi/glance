import Foundation

/// One camera frame's worth of gaze evidence.
public struct GazeSample: Equatable, Sendable {
    /// Head yaw in radians, as reported by Vision.
    public var yaw: Double
    /// Mean horizontal pupil offset inside the eye, in eye widths (roughly -0.5...0.5).
    public var pupil: Double

    public init(yaw: Double, pupil: Double) {
        self.yaw = yaw
        self.pupil = pupil
    }

    var vector: [Double] { [yaw, pupil] }
}

/// Where the user's gaze sits while looking at each display, learned during calibration.
public struct Calibration: Codable, Equatable, Sendable {
    /// Display key -> median feature vector while looking at that display.
    public let centroids: [String: [Double]]
    /// Pooled within-display standard deviation per feature; distances are measured in these units.
    public let scale: [Double]
    /// Display keys ordered left to right at calibration time.
    public let layout: [String]

    /// Keeps a feature that happened to be very steady during calibration from dominating.
    static let minimumScale = [0.02, 0.02]

    public init?(samples: [String: [GazeSample]], layout: [String]) {
        guard samples.count >= 2, samples.values.allSatisfy({ $0.count >= 5 }) else { return nil }
        var centroids: [String: [Double]] = [:]
        var sumSquares = [0.0, 0.0]
        var count = 0
        for (key, list) in samples {
            let vectors = list.map(\.vector)
            let centroid = (0..<2).map { i in median(vectors.map { $0[i] }) }
            centroids[key] = centroid
            for v in vectors {
                for i in 0..<2 { sumSquares[i] += (v[i] - centroid[i]) * (v[i] - centroid[i]) }
            }
            count += vectors.count
        }
        self.centroids = centroids
        self.scale = (0..<2).map { max(sqrt(sumSquares[$0] / Double(count)), Self.minimumScale[$0]) }
        self.layout = layout
    }

    public func distance(from sample: GazeSample, to key: String) -> Double {
        guard let centroid = centroids[key] else { return .infinity }
        let v = sample.vector
        return sqrt((0..<2).reduce(0) { $0 + pow((v[$1] - centroid[$1]) / scale[$1], 2) })
    }

    /// Smallest distance between any two display centroids. Below ~3 the displays are hard to tell apart.
    public var separation: Double {
        let values = Array(centroids.values)
        var best = Double.infinity
        for i in values.indices {
            for j in values.indices where j > i {
                let d = sqrt((0..<2).reduce(0) { $0 + pow((values[i][$1] - values[j][$1]) / scale[$1], 2) })
                best = min(best, d)
            }
        }
        return best
    }
}

/// Turns a noisy stream of gaze samples into stable "now looking at display X" transitions.
public final class GazeTracker {
    public let calibration: Calibration
    /// How long a different display must keep winning before we switch to it.
    public var dwell: TimeInterval
    /// How much closer (in calibration units) a different display must be, so we don't flicker at the boundary.
    public var margin = 1.0
    /// Weight of the newest sample in the moving average.
    public var smoothing = 0.35

    public private(set) var current: String?
    private var smoothed: GazeSample?
    private var pending: (key: String, since: TimeInterval)?

    public init(calibration: Calibration, dwell: TimeInterval) {
        self.calibration = calibration
        self.dwell = dwell
    }

    /// Returns a display key only when the gaze has settled on a different display than before.
    public func update(_ sample: GazeSample, at time: TimeInterval) -> String? {
        let s = smoothed.map {
            GazeSample(yaw: $0.yaw + smoothing * (sample.yaw - $0.yaw),
                       pupil: $0.pupil + smoothing * (sample.pupil - $0.pupil))
        } ?? sample
        smoothed = s

        let distances = calibration.centroids.keys.map { ($0, calibration.distance(from: s, to: $0)) }
        guard let best = distances.min(by: { $0.1 < $1.1 }) else { return nil }
        guard let current else {
            // First fix after starting: adopt it silently rather than yanking focus.
            self.current = best.0
            return nil
        }
        let currentDistance = distances.first { $0.0 == current }?.1 ?? .infinity
        guard best.0 != current, currentDistance - best.1 >= margin else {
            pending = nil
            return nil
        }
        if pending?.key != best.0 { pending = (best.0, time) }
        guard let pending, time - pending.since >= dwell else { return nil }
        self.current = best.0
        self.pending = nil
        return best.0
    }

    /// Call when no face is visible, so stale samples don't carry over.
    public func faceLost() {
        smoothed = nil
        pending = nil
    }
}

private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

/// Decides when the user has left the seat and when they're back.
public struct Presence {
    public enum Change { case left, returned }

    public let awayDelay: TimeInterval
    public private(set) var isAway = false
    private var lastSeen: TimeInterval?

    public init(awayDelay: TimeInterval) {
        self.awayDelay = awayDelay
    }

    /// Returns `.left` once no face has been seen for `awayDelay`, and `.returned` on the first face after that.
    public mutating func update(faceVisible: Bool, at time: TimeInterval) -> Change? {
        if faceVisible || lastSeen == nil { lastSeen = time }
        let nowAway = !faceVisible && time - lastSeen! >= awayDelay
        guard nowAway != isAway else { return nil }
        isAway = nowAway
        return nowAway ? .left : .returned
    }

    public mutating func reset() {
        isAway = false
        lastSeen = nil
    }
}
