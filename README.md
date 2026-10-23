# Glance

A macOS menu bar utility that watches where you look, using the Mac's camera, and moves focus to that display.
If you turn toward the monitor on your right, the frontmost window there gets keyboard focus. The same goes for a monitor on the left.

## Build & run

Needs macOS 14 or later and Xcode (or the Swift toolchain).

```sh
./build.sh                 # builds and signs build/Glance.app
open build/Glance.app   # or copy it to /Applications first
swift test                 # unit tests for the gaze logic
```

On first launch macOS asks for camera access. Glance then runs a short calibration: a dot appears on each display in turn, and you look at it the way you normally look at that display. Recalibrate from the menu after you move a monitor or your seat. If you connect a different set of displays or rearrange them, it asks you to calibrate again.

## Menu

- **Pause / Resume Tracking**: turns the camera off or back on.
- **Recalibrate…**
- **Switch Delay**: how long you must keep looking at a display before focus moves. The default, Instant, switches about two camera frames (~0.17 s) after your gaze crosses over; 0.2, 0.4 and 0.8 s are also available.
- **Move Pointer With Focus**: puts the mouse pointer on the newly focused window, so scrolling works there too.
- **Wake Displays When I Return** (on by default): if the displays went to sleep while you were away, they wake as soon as the camera sees you again.
- **Raise Exact Window (optional, needs Accessibility)**: without this permission, Glance activates the *app* that owns the frontmost window on that display. That's right unless one app has windows on both displays (for example two Chrome windows). In that case, grant Accessibility so the exact window is raised.

## Menu bar icon

The icon is an eye drawn in code (`GlanceIcon.swift`) as a template image, so macOS tints it for light and dark menu bars.

| Icon | Meaning |
|---|---|
| Eye, solid pupil | Tracking. The pupil glances toward the focused display: far left for the leftmost display, far right for the rightmost, evenly spaced in between. |
| Eye, hollow pupil | Tracking, but no face in view |
| Closed eye with lashes | Paused, away from the seat, or only one display connected |
| Eye with "!" | Needs calibration or camera access |

## Privacy & system access

- **No network, enforced by macOS.** The app runs in the App Sandbox and has no network entitlement, so the OS blocks every connection attempt. Check this yourself with `codesign -d --entitlements - build/Glance.app`. It lists only `app-sandbox` and `device.camera`.
- **Camera frames never leave memory.** Each frame goes through Apple's on-device Vision face landmarks (head yaw plus pupil position) and is then discarded. Nothing is recorded or written to disk. Only the calibration numbers (a few floats per display) are saved in the app's sandbox container.
- **The camera only runs when it's useful.** It stays off with one display, while paused, and while another user is logged in at the console. While the displays are asleep or the screen is locked, it stays on only if **Wake Displays When I Return** is enabled. A running camera also keeps the Mac from sleeping, so turn that option off if you'd rather the Mac sleep when the displays do.
- **Away detection.** If no face is seen for 5 seconds, Glance pauses switching and drops to 4 analysed frames per second. It resumes on the first frame that sees you again.
- **Window info is minimal.** To find the window to focus, the app reads only the owner and bounds of on-screen windows, never titles or contents. It doesn't need Screen Recording permission.

## How it works

1. `GazeCamera` analyses about 12 frames per second. For each frame it records head yaw and the mean horizontal pupil offset within the eyes.
2. Calibration saves the median of these values for each display, plus their typical spread.
3. `GazeTracker` smooths incoming samples and picks the nearest display. It only switches when a different display is clearly closer (hysteresis) for the whole switch delay. It acts only on changes, so it never fights you when you click into another display yourself.
4. `DisplayFocuser` activates the app that owns the frontmost window on the new display. With Accessibility granted, it raises that exact window.
5. `Presence` marks you as away after 5 s without a face and back on the first face after that. While away, the app can also wake the displays (see the menu option).

## Test coverage

### Automated (`swift test`, 12 tests, `GlanceCore` only)

- **Calibration:** fits per-display centroids, rejects too little data or a single display, and survives a JSON round trip.
- **Tracker:**
  - the first fix after starting is adopted without moving focus;
  - a switch happens only after the switch delay, and a brief glance doesn't switch;
  - jitter at the boundary between displays doesn't flip-flop, at both 0 s and 0.2 s delay;
  - losing your face resets a pending switch;
  - Instant switches on the second frame.
- **Presence:** you're marked away after 5 s, short drop-outs are ignored, and you're back on the first face.

The app target (camera, focusing, calibration UI, menu) has no automated tests.

### Verified manually

Tested on macOS 27 with a MacBook built-in display and an external monitor to its right. These were one-off scripts and aren't part of the repo.

- **Gaze pipeline end to end, sandboxed, with face images instead of the live camera.** Public test portraits and their mirror images went as camera frames through the real `GazeCamera`, calibration, `GazeTracker` and `DisplayFocuser` code.
  - A turned head gave a yaw of ±0.61 rad, with the face found in 24/24 frames and a calibration separation of 61.
  - Focus moved to the right display and back. With Instant, the switch came on the 2nd frame.
  - A near-frontal face gave only a weak signal (separation 2.8), which calibration would reject.
- **Focus switching in the sandbox**, both with and without Accessibility. The correct app came to front on each display and the pointer followed.
- **Display wake from the sandbox:** after `pmset displaysleepnow`, Glance's wake call turned the displays back on.
- **Network blocked:** a request from the sandboxed build failed as expected.
- **Running app:** Glance runs in the menu bar with camera access. The icon showed it tracking a live face on the built-in display.

### Not yet verified

- A live, logged focus switch driven by the real camera. To check one, run `log stream --predicate 'subsystem == "local.glance"'` and look between displays.
- Leaving and returning to the seat with the live camera, including waking the displays. The logic is unit-tested and the wake call was tested separately, but not together.
- Three or more displays, lid closed with an external webcam, Continuity Camera, and several people in view.

## Limitations

- **Left and right only.** Glance reads head yaw and horizontal pupil position, so it can't tell apart displays stacked above each other.
- **Turn your head, at least slightly.** At webcam resolution, eye-only movement gives a weak signal. Calibration rejects displays it can't tell apart and asks you to turn your head more. The more displays side by side, the smaller the turn between neighbours, and the harder they are to separate.
- **Calibration is tied to your setup.** It's saved for an exact set of displays in a specific left-to-right order. Recalibrate after moving your seat or a monitor. Two identical monitors without serial numbers are told apart by display ID, which can change when they reconnect, so they may ask for recalibration.
- **Any face counts.** Glance tracks the largest face in view and can't tell people apart. Someone else at your desk steers focus, and anyone passing in front of the camera counts as you coming back, which can wake the displays.
- **Without Accessibility, focus is per app.** If one app has windows on several displays, the window that comes to front may be on the wrong display. If the target display has no normal windows (for example an empty desktop), only the pointer moves. Windows in other Spaces or behind a full-screen app aren't considered.
- **Lighting and camera position matter.** In low light, with strong glare on glasses, or with the camera off to one side, faces are missed and switching pauses until one is found again.
- **Camera and sleep.** The green camera indicator is on whenever Glance is tracking. With **Wake Displays When I Return** on, the camera also runs while the displays sleep, and that keeps the Mac awake.
- **Lid closed.** The built-in camera isn't available, so Glance falls back to any other connected camera (untested).
- **Icon with 4+ displays.** Pupil positions get close together. The menu's first line always names the focused display exactly.
- **Packaging.** Built and signed locally (your development certificate or ad hoc). It isn't notarized and doesn't launch at login.
