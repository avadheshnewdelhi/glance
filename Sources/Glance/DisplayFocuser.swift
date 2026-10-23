import AppKit
import ApplicationServices

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// Stable across reconnects, so a saved calibration survives unplugging the monitor.
    var displayKey: String {
        let id = displayID
        let serial = CGDisplaySerialNumber(id)
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(serial == 0 ? "id\(id)" : String(serial))"
    }

    static var leftToRight: [NSScreen] { screens.sorted { $0.frame.minX < $1.frame.minX } }
}

/// Moves keyboard focus to the frontmost window on a display.
///
/// Without extra permissions this activates the app that owns that window. If the user has granted
/// Accessibility, it also raises that exact window, which matters when one app has windows on several displays.
enum DisplayFocuser {
    private struct Window {
        let pid: pid_t
        let bounds: CGRect // global coordinates, origin at top-left of the primary display
        var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
    }

    static func focus(_ screen: NSScreen, movePointer: Bool) {
        let bounds = CGDisplayBounds(screen.displayID)
        let windows = onScreenWindows()
        let target = windows.first { bounds.contains($0.center) }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focused = windows.first { $0.pid == frontPID }

        if let target, !(focused.map { bounds.contains($0.center) } ?? false) {
            if AXIsProcessTrusted() { raiseExactWindow(target) }
            NSRunningApplication(processIdentifier: target.pid)?.activate()
        }
        if movePointer, !screen.frame.contains(NSEvent.mouseLocation) {
            CGWarpMouseCursorPosition(target?.center ?? CGPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    /// Normal app windows, front to back. Only owner and bounds are read — no titles or contents.
    private static func onScreenWindows() -> [Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 100, bounds.height > 100,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            else { return nil }
            return Window(pid: pid, bounds: bounds)
        }
    }

    private static func raiseExactWindow(_ window: Window) {
        let app = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return }
        for axWindow in axWindows {
            guard let frame = frame(of: axWindow),
                  abs(frame.minX - window.bounds.minX) < 4, abs(frame.minY - window.bounds.minY) < 4,
                  abs(frame.width - window.bounds.width) < 4, abs(frame.height - window.bounds.height) < 4 else { continue }
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            return
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
