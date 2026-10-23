import AppKit
import ApplicationServices
import AVFoundation
import GlanceCore
import IOKit.pwr_mgt
import OSLog

/// Local unified log only: `log stream --predicate 'subsystem == "local.glance"'`.
private let log = Logger(subsystem: "local.glance", category: "gaze")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum State {
        case paused, singleDisplay, cameraDenied, needsCalibration, tracking
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let camera = GazeCamera()
    private let defaults = UserDefaults.standard
    private var tracker: GazeTracker?
    private var calibrator: CalibrationController?
    private var faceVisible = false
    /// No face for 5 s means you've left the seat: switching pauses until a face is back.
    private var presence = Presence(awayDelay: 5)
    private var screensAsleep = false
    private var locked = false
    /// Another user is on the console (fast user switching).
    private var sessionInactive = false
    private var activityID = IOPMAssertionID(0)

    private static let delays: [(String, TimeInterval)] = [("Instant", 0), ("Short (0.2 s)", 0.2), ("Medium (0.4 s)", 0.4), ("Long (0.8 s)", 0.8)]

    // MARK: Settings

    private var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    private var movePointer: Bool {
        get { defaults.object(forKey: "movePointer") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "movePointer") }
    }

    private var dwell: TimeInterval {
        get { defaults.object(forKey: "dwell") as? TimeInterval ?? 0 }
        set { defaults.set(newValue, forKey: "dwell"); tracker?.dwell = newValue }
    }

    /// Keeps the camera on while the displays sleep or the screen is locked, so returning to the seat can wake them.
    private var wakeOnReturn: Bool {
        get { defaults.object(forKey: "wakeOnReturn") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "wakeOnReturn") }
    }

    private var calibration: Calibration? {
        get { defaults.data(forKey: "calibration").flatMap { try? JSONDecoder().decode(Calibration.self, from: $0) } }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "calibration") }
    }

    /// The saved calibration, if it was made for exactly the displays connected now, in the same arrangement.
    private var activeCalibration: Calibration? {
        guard let calibration, calibration.layout == NSScreen.leftToRight.map(\.displayKey) else { return nil }
        return calibration
    }

    private var state: State {
        if !enabled { return .paused }
        if NSScreen.screens.count < 2 { return .singleDisplay }
        if [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video)) { return .cameraDenied }
        if activeCalibration == nil { return .needsCalibration }
        return .tracking
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        camera.onSample = { [weak self] sample, time in self?.handle(sample, at: time) }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.calibrator?.cancel() // its targets belong to the old arrangement
            self?.camera.stop() // restart so the camera choice is re-evaluated (e.g. lid closed)
            self?.refresh()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }

        refresh()
        if state == .needsCalibration { startCalibration() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ update: @escaping (AppDelegate) -> Void) {
        _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            update(self)
            refresh()
        }
    }

    /// Brings the camera and tracker in line with the current state. Safe to call any time.
    private func refresh() {
        let current = state
        if current == .tracking, let calibration = activeCalibration {
            if tracker?.calibration != calibration { tracker = GazeTracker(calibration: calibration, dwell: dwell) }
        } else {
            tracker = nil
        }

        // The camera is off whenever nobody could be using these displays, unless it's needed to notice you coming back.
        let idle = screensAsleep || locked
        if calibrator != nil || (current == .tracking && !sessionInactive && (!idle || wakeOnReturn)) {
            // While nobody is working, a slower pace is enough to notice a return.
            camera.frameInterval = presence.isAway || idle ? 1.0 / 4 : 1.0 / 12
            startCamera()
        } else {
            camera.stop()
            faceVisible = false
            presence.reset()
        }
        updateIcon()
    }

    private func updateIcon() {
        let glyph: GlanceIcon.Glyph
        switch state {
        case .tracking: glyph = presence.isAway ? .closed : faceVisible ? .looking(gazeDirection) : .searching
        case .paused, .singleDisplay: glyph = .closed
        case .cameraDenied, .needsCalibration: glyph = .attention
        }
        statusItem.button?.image = GlanceIcon.image(glyph)
        statusItem.button?.image?.accessibilityDescription = "Glance: \(statusText)"
    }

    /// Where the tracked display sits in the arrangement: -1 leftmost ... 1 rightmost.
    private var gazeDirection: CGFloat {
        let screens = NSScreen.leftToRight
        guard screens.count > 1, let index = screens.firstIndex(where: { $0.displayKey == tracker?.current }) else { return 0 }
        return CGFloat(index) / CGFloat(screens.count - 1) * 2 - 1
    }

    private func startCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in DispatchQueue.main.async { self.refresh() } }
        default:
            break
        }
    }

    private func handle(_ sample: GazeSample?, at time: TimeInterval) {
        if let calibrator { return calibrator.add(sample) }
        let visible = sample != nil
        let change = presence.update(faceVisible: visible, at: time)
        switch change {
        case .returned:
            log.notice("Back at the seat")
            if screensAsleep && wakeOnReturn { wakeDisplays() }
        case .left:
            log.notice("Away from the seat, switching paused")
        case nil:
            break
        }
        if visible != faceVisible || change != nil {
            faceVisible = visible
            refresh()
        }
        guard let tracker, !screensAsleep, !locked else { return }
        guard let sample else { return tracker.faceLost() }
        let previous = tracker.current
        let switched = tracker.update(sample, at: time)
        if tracker.current != previous { updateIcon() }
        if let key = switched, let screen = NSScreen.screens.first(where: { $0.displayKey == key }) {
            log.notice("Gaze moved to \(screen.localizedName, privacy: .public) (yaw \(sample.yaw, format: .fixed(precision: 2)), pupil \(sample.pupil, format: .fixed(precision: 2)))")
            DisplayFocuser.focus(screen, movePointer: movePointer)
        }
    }

    private func wakeDisplays() {
        let result = IOPMAssertionDeclareUserActivity("Glance: user returned to the seat" as CFString, kIOPMUserActiveLocal, &activityID)
        log.notice("Waking displays: \(result == kIOReturnSuccess ? "ok" : "failed \(result)", privacy: .public)")
    }

    // MARK: Calibration

    @objc private func startCalibration() {
        guard calibrator == nil, NSScreen.screens.count >= 2 else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            // Ask first, so the calibration timeout doesn't run while the permission prompt is up.
            return AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.startCalibration() : self.refresh() }
            }
        default:
            return showAlert("Camera access is off", "Allow Glance in System Settings › Privacy & Security › Camera, then calibrate again.")
        }
        calibrator = CalibrationController { [weak self] outcome in
            guard let self else { return }
            calibrator = nil
            switch outcome {
            case .done(let result):
                log.notice("Calibrated \(result.layout.count) displays, separation \(result.separation, format: .fixed(precision: 1))")
                calibration = result
                enabled = true
            case .cancelled:
                break
            case .failed(let message):
                log.error("Calibration failed: \(message, privacy: .public)")
                showAlert("Calibration didn't finish", message)
            }
            refresh()
        }
        refresh()
        calibrator?.start()
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: statusText, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        menu.addItem(item(enabled ? "Pause Tracking" : "Resume Tracking", #selector(toggleEnabled)))
        let calibrate = item(activeCalibration == nil ? "Calibrate…" : "Recalibrate…", #selector(startCalibration))
        calibrate.isEnabled = NSScreen.screens.count >= 2 && calibrator == nil
        menu.addItem(calibrate)
        if state == .cameraDenied {
            menu.addItem(item("Open Camera Privacy Settings…", #selector(openCameraSettings)))
        }
        menu.addItem(.separator())

        let delayMenu = NSMenu()
        for (index, (title, value)) in Self.delays.enumerated() {
            let delayItem = item(title, #selector(setDelay(_:)))
            delayItem.tag = index
            delayItem.state = value == dwell ? .on : .off
            delayMenu.addItem(delayItem)
        }
        let delay = NSMenuItem(title: "Switch Delay", action: nil, keyEquivalent: "")
        delay.submenu = delayMenu
        menu.addItem(delay)

        let pointer = item("Move Pointer With Focus", #selector(toggleMovePointer))
        pointer.state = movePointer ? .on : .off
        menu.addItem(pointer)

        let wake = item("Wake Displays When I Return", #selector(toggleWakeOnReturn))
        wake.state = wakeOnReturn ? .on : .off
        wake.toolTip = "Keeps the camera on while the displays sleep or the screen is locked, which also keeps the Mac from sleeping."
        menu.addItem(wake)

        let trusted = AXIsProcessTrusted()
        let exact = item(trusted ? "Raise Exact Window" : "Raise Exact Window (needs Accessibility)…", #selector(requestAccessibility))
        exact.state = trusted ? .on : .off
        exact.toolTip = "When one app has windows on several displays, raise the window on the display you look at, not just the app."
        menu.addItem(exact)

        menu.addItem(.separator())
        menu.addItem(item("Quit Glance", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private var statusText: String {
        switch state {
        case .paused: return "Paused"
        case .singleDisplay: return "One display connected — camera off"
        case .cameraDenied: return "Camera access is off"
        case .needsCalibration: return calibrator != nil ? "Calibrating…" : "Calibrate for these displays"
        case .tracking:
            if sessionInactive { return "Another user is active — camera off" }
            if screensAsleep || locked { return wakeOnReturn ? "Displays will wake when you return" : "Screen asleep or locked — camera off" }
            if presence.isAway { return "Away — paused until you're back" }
            guard faceVisible else { return "Looking for your face…" }
            let name = NSScreen.screens.first { $0.displayKey == tracker?.current }?.localizedName
            return name.map { "Looking at \($0)" } ?? "Tracking"
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        refresh()
    }

    @objc private func toggleMovePointer() { movePointer.toggle() }

    @objc private func toggleWakeOnReturn() {
        wakeOnReturn.toggle()
        refresh()
    }

    @objc private func setDelay(_ sender: NSMenuItem) { dwell = Self.delays[sender.tag].1 }

    @objc private func requestAccessibility() {
        if AXIsProcessTrusted() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    @objc private func openCameraSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }
}
