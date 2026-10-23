# Changelog

## 1.0.0

First release.

- Focus follows your gaze between displays, using the Mac's camera and Apple's on-device Vision framework.
- Per-display calibration that works with any left-to-right arrangement.
- Switch delay: Instant by default (~0.17 s), or 0.2, 0.4 or 0.8 s, with hysteresis against flicker.
- Away detection: switching pauses after 5 s with no one in view and resumes as soon as you're back.
- Optional display wake when you return.
- Optional "Move Pointer With Focus", and "Raise Exact Window" (with Accessibility).
- Menu bar icon whose pupil glances toward the focused display.
- App Sandbox with only the camera entitlement, so the OS blocks all network access.
