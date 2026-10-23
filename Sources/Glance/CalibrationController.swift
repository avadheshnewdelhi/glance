import AppKit
import GlanceCore

/// Shows a target on each display in turn and records where the user's gaze sits while looking at it.
final class CalibrationController {
    enum Outcome {
        case done(Calibration)
        case cancelled
        case failed(String)
    }

    private static let settle: TimeInterval = 1.2   // time to turn and look before we start recording
    private static let samplesPerDisplay = 24       // ~2 s at 12 analyses per second
    private static let timeout: TimeInterval = 12

    private let screens = NSScreen.leftToRight
    private let completion: (Outcome) -> Void
    private var index = 0
    private var samples: [String: [GazeSample]] = [:]
    private var phaseStart = Date()
    private var window: OverlayWindow?
    private var timer: Timer?

    init(completion: @escaping (Outcome) -> Void) {
        self.completion = completion
    }

    func start() {
        NSApp.activate()
        showTarget()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
    }

    func add(_ sample: GazeSample?) {
        guard let sample, index < screens.count, Date().timeIntervalSince(phaseStart) >= Self.settle else { return }
        samples[screens[index].displayKey, default: []].append(sample)
    }

    func cancel() { finish(.cancelled) }

    private func showTarget() {
        let screen = screens[index]
        window?.orderOut(nil)
        let overlay = OverlayWindow(screen: screen)
        overlay.target.caption = "Look at the dot the way you normally look at this display"
        overlay.target.detail = "Display \(index + 1) of \(screens.count) · \(screen.localizedName) · Esc to cancel"
        overlay.onCancel = { [weak self] in self?.cancel() }
        overlay.makeKeyAndOrderFront(nil)
        window = overlay
        phaseStart = Date()
    }

    private func tick() {
        let collected = samples[screens[index].displayKey]?.count ?? 0
        window?.target.progress = Double(collected) / Double(Self.samplesPerDisplay)
        if collected >= Self.samplesPerDisplay {
            index += 1
            if index < screens.count { showTarget() } else { complete() }
        } else if Date().timeIntervalSince(phaseStart) > Self.timeout {
            finish(.failed("Couldn't see your face clearly. Make sure the camera isn't covered and your face is lit, then try again."))
        }
    }

    private func complete() {
        guard let calibration = Calibration(samples: samples, layout: screens.map(\.displayKey)) else {
            return finish(.failed("Calibration needs at least two displays."))
        }
        guard calibration.separation >= 3 else {
            return finish(.failed("Your gaze looked too similar across displays. Turn your head naturally toward each display and try again."))
        }
        finish(.done(calibration))
    }

    private func finish(_ outcome: Outcome) {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        completion(outcome)
    }
}

private final class OverlayWindow: NSWindow {
    let target = TargetView()
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.6)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = target
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private final class TargetView: NSView {
    var caption = "" { didSet { needsDisplay = true } }
    var detail = "" { didSet { needsDisplay = true } }
    var progress = 0.0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)).fill()

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: 34, startAngle: 0, endAngle: 360)
        track.lineWidth = 4
        NSColor.white.withAlphaComponent(0.2).setStroke()
        track.stroke()

        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: 34, startAngle: 90, endAngle: 90 - 360 * min(progress, 1), clockwise: true)
        arc.lineWidth = 4
        NSColor.controlAccentColor.setStroke()
        arc.stroke()

        drawCentered(caption, font: .systemFont(ofSize: 22, weight: .medium), y: center.y - 90)
        drawCentered(detail, font: .systemFont(ofSize: 14), y: center.y - 120, alpha: 0.7)
    }

    private func drawCentered(_ text: String, font: NSFont, y: CGFloat, alpha: CGFloat = 1) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(alpha)]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: y), withAttributes: attributes)
    }
}
