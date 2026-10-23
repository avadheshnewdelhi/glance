import AppKit

/// Glance's menu bar icon: an eye whose pupil glances toward the display that has focus.
/// Drawn in code as a template image, so macOS tints it for light and dark menu bars.
enum GlanceIcon {
    enum Glyph {
        /// Tracking; the pupil sits at -1 (leftmost display) ... 1 (rightmost display).
        case looking(CGFloat)
        /// Tracking, but no face in view.
        case searching
        /// Paused, away, or only one display.
        case closed
        /// Needs calibration or camera access.
        case attention
    }

    static func image(_ glyph: Glyph) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.set()
            switch glyph {
            case .looking(let direction):
                let eye = almond()
                eye.stroke()
                NSGraphicsContext.saveGraphicsState()
                eye.addClip()
                circle(x: 10 + direction * 3.5, y: 8, radius: 3.4).fill()
                NSGraphicsContext.restoreGraphicsState()
            case .searching:
                almond().stroke()
                let pupil = circle(x: 10, y: 8, radius: 2.4)
                pupil.lineWidth = 1.3
                pupil.stroke()
            case .closed:
                let lid = NSBezierPath()
                lid.move(to: CGPoint(x: 1.5, y: 9))
                lid.curve(to: CGPoint(x: 18.5, y: 9), controlPoint1: CGPoint(x: 6, y: 3.5), controlPoint2: CGPoint(x: 14, y: 3.5))
                for (from, to) in [((5.4, 5.9), (4.2, 3.2)), ((10, 4.9), (10, 2)), ((14.6, 5.9), (15.8, 3.2))] {
                    lid.move(to: CGPoint(x: from.0, y: from.1))
                    lid.line(to: CGPoint(x: to.0, y: to.1))
                }
                lid.lineWidth = 1.5
                lid.lineCapStyle = .round
                lid.stroke()
            case .attention:
                almond().stroke()
                let mark = NSBezierPath()
                mark.move(to: CGPoint(x: 10, y: 10.6))
                mark.line(to: CGPoint(x: 10, y: 7.4))
                mark.lineWidth = 1.6
                mark.lineCapStyle = .round
                mark.stroke()
                circle(x: 10, y: 5.4, radius: 0.9).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func almond() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 1.5, y: 8))
        path.curve(to: CGPoint(x: 18.5, y: 8), controlPoint1: CGPoint(x: 6, y: 14.5), controlPoint2: CGPoint(x: 14, y: 14.5))
        path.curve(to: CGPoint(x: 1.5, y: 8), controlPoint1: CGPoint(x: 14, y: 1.5), controlPoint2: CGPoint(x: 6, y: 1.5))
        path.close()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        return path
    }

    private static func circle(x: CGFloat, y: CGFloat, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
}
