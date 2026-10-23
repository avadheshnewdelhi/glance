# Testing

What's covered by automated tests, what was verified by hand, and what hasn't been verified yet.

## Automated: `swift test`

12 unit tests cover `GlanceCore`, the pure logic with no camera or UI:

- **Calibration:** fits per-display centroids, rejects too little data or a single display, and survives a JSON round trip.
- **Tracker:**
  - the first fix after starting is adopted without moving focus;
  - a switch happens only after the switch delay, and a brief glance doesn't switch;
  - jitter at the boundary between displays doesn't flip-flop, at both 0 s and 0.2 s delay;
  - losing the face resets a pending switch;
  - Instant switches on the second frame.
- **Presence:** marked away after 5 s, short drop-outs are ignored, and back on the first face.

The app target (camera, focusing, calibration overlay, menu) has no automated tests. CI runs the unit tests and a full build on every push.

## Verified by hand

On macOS 27 with a MacBook's built-in display and an external monitor to its right. The test scripts were one-off and aren't part of the repo.

- **Live camera, end to end.** In about two minutes of turning between the two displays, Glance logged 52 focus switches. Each one went to the display being looked at, with switches as little as ~0.7 s apart. Head yaw was about −0.8 to −1.0 rad facing the external monitor and about 0 to +0.2 rad facing the built-in display. Pupil offset stayed near 0, so the head turn carries the signal.
- **Gaze pipeline with face images instead of the camera, sandboxed.** Public test portraits and their mirror images went as camera frames through the real `GazeCamera`, calibration, `GazeTracker` and `DisplayFocuser` code.
  - A turned head gave a yaw of ±0.61 rad, with the face found in 24/24 frames and a calibration separation of 61.
  - Focus moved right and back. With Instant, the switch came on the 2nd frame.
  - A near-frontal face gave only a weak signal (separation 2.8), which calibration rejects.
- **Focus switching in the sandbox,** with and without Accessibility. The right app came to front on each display and the pointer followed.
- **Waking displays from the sandbox:** after `pmset displaysleepnow`, Glance's wake call turned the displays back on.
- **No network:** a request from the sandboxed build was blocked.
- **Release DMG:** ad hoc signature valid, no team ID, and no build paths or personal strings in the app bundle.
- **Homebrew cask:** install (adopting an existing manual install), `brew upgrade` from 1.0.0 to 1.0.1, uninstall and reinstall. Homebrew quit the running app before upgrading and reopened it after; no quarantine flag remained. `brew style` passes. `brew audit` was not run, because it needs newer Command Line Tools than this Mac had.

## Not verified yet

- Leaving and returning with the live camera, including waking the displays. The logic is unit-tested and the wake call was tested separately, but not together.
- Three or more displays, the lid closed with an external webcam, Continuity Camera, and several people in view.
- The downloaded DMG on a second Mac (Gatekeeper's "Open Anyway" flow, then camera permission).

Tried one of these? Please open an issue with what you saw.
