# Mavic Ground Station

A development prototype for the **original DJI Mavic Pro**, with an Apple Silicon **Mac ground station** and an **iPhone 15 communications bridge** connected to the standard DJI remote controller.

> **Prototype only, not flight-ready.** The included Mac↔iPhone network connection displays **SIMULATED** telemetry. No DJI connection, video, waypoint execution, or flight controls have been implemented. Never use this prototype for flight decisions.

## Hardware

- Apple Silicon Mac and Xcode
- iPhone 15 (USB-C), with Apple development signing configured
- Original DJI Mavic Pro and standard remote controller
- DJI Mavic Pro USB-C controller cable, or suitable data cable through the controller's bottom USB port (disconnect the side cable when using the bottom port)
- Trusted Wi-Fi network shared by iPhone and Mac

## Project layout

```text
MacGroundStation/        macOS SwiftUI ground-control dashboard
iOSFlightBridge/         iPhone SwiftUI network bridge; DJI integration placeholder
Shared/Protocol/         versioned JSON wire models shared by both targets
Documentation/           DJI integration and testing plans
project.yml              XcodeGen project definition
Podfile                  DJI-SDK-iOS 4.16.2 (legacy integration milestone)
```

## Quick start — local simulated telemetry

1. Install **Xcode** and launch it once. Configure Apple developer signing for physical iPhone deployment.
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
3. Clone and generate:

   ```bash
   git clone https://github.com/callumisdumb/groundstation.git
   cd groundstation
   xcodegen generate
   open MavicGroundStation.xcodeproj
   ```

4. Select the `MacGroundStation` scheme, then build and run on your Mac.
5. Select `iOSFlightBridge`, set your **Apple Team** and a unique bundle ID, then build and run on your actual iPhone 15.
6. Put both devices on the same trusted Wi-Fi network. Allow the iPhone app to access the Local Network and keep it in the foreground.
7. The iPhone bridge listens on TCP port **8765** and displays its local IP. Enter that IP in the Mac app and press **Connect**.
8. Confirm that the Mac dashboard shows one **simulated** status message per second.

The initial TCP link is **unauthenticated and unencrypted**. Use on a trusted LAN **only**; never forward its port to the internet. A later remote-monitoring phase must add authentication and encryption.

## DJI SDK integration: next milestone

The original Mavic Pro is documented by DJI's legacy **Mobile SDK v4**. The iOS SDK version targeted here is **4.16.2**, but compatibility with modern iOS, Apple Silicon Xcode, an iPhone 15 and your firmware versions is **not verified**.

Before changing the prototype:

1. Obtain a [DJI developer account](https://developer.dji.com/) and an SDK application key.
2. Clone DJI's [official iOS Mobile SDK sample](https://github.com/dji-sdk/Mobile-SDK-iOS).
3. Follow the [official Quick Start](https://developer.dji.com/mobile-sdk/documentation/quick-start/index.html), including the `DJISDKAppKey` setting, CocoaPods, signing, and controller connection.
4. First confirm the official sample registers, activates (if required), and detects your real aircraft.
5. Port only proven DJI registration, connection and read-only aircraft-state code into `iOSFlightBridge/DJIAdapter.swift`. Convert state changes to `GroundStationMessage` and forward to the Mac.
6. Keep DJI framework types in the iOS app; the Mac should know only about the shared protocol.

The root `Podfile` is a **future integration aid**, not required for the initial simulated demo. If used, generate the Xcode project first, run `pod install`, and open the resulting `.xcworkspace`. Legacy SDK constraints may require a different pinned toolchain.

## Roadmap

- [x] Mac and iPhone SwiftUI project scaffold
- [x] Local TCP/JSON link and simulated status dashboard
- [ ] Validate original Mavic Pro + iPhone 15 with official DJI sample
- [ ] Live read-only telemetry, battery and GPS from DJI SDK
- [ ] Video streaming to Mac
- [ ] Map and mission planning
- [ ] Carefully engineered flight control with arming, timeouts and physical-controller override
- [ ] Authenticated/encrypted remote monitoring

## Safety

No live flight commands are present. Never assume network loss means the aircraft has stopped. Keep DJI's physical controller and built-in failsafes available, and comply with applicable [UK CAA drone rules](https://www.caa.co.uk/drones/) including visual-line-of-sight obligations.

## Documentation

Read [DJI integration](Documentation/DJIIntegration.md) and [test plan](Documentation/TestingPlan.md) before extending this prototype.


## Mac-only controls (development branch)

The Mac application is intended to be the **only operator interface**. The iPhone runs
as a foreground communications bridge attached to the original Mavic Pro RC by USB-C.
The user must initially open the bridge and enter the six-digit pairing code on Mac,
but gimbal/camera/mission/flight operation will be managed from the Mac.

On `feature/dji-v4-readonly`, the UI contains aircraft diagnostics, map, DJI camera
commands, gimbal pitch controls, and a prototype for flight actions / held virtual sticks.
**Flight actions and motors are intentionally DISABLED** by default because an
unencrypted LAN + unvalidated H.264 network video are not suitable for live flight control. They
must not be enabled simply by changing a build flag without a secure transport and
controlled hardware/simulator testing. A checked, production pilot must have the physical
controller and direct visual line of sight.

Camera video now has a **continuous H.264** path: the iPhone forwards DJI's compressed
primary camera feed over a separate paired TCP port **8766**; the Mac parses and
displays H.264 using Apple's AVSampleBufferDisplayLayer. The telemetry/command
port **8765** remains separate. This is a development live preview, **not** a
flight-certified low-latency FPV system. DJIWidget may still require legacy
Xcode compatibility work. See
[Mac-only controls and testing](Documentation/MacControlTesting.md).


## Live H.264 camera preview (experimental)

See [Live Video Setup and Troubleshooting](Documentation/LiveVideo.md).
Rebuild **both** Xcode targets after pulling this branch. When the Mac connects
to the iPhone on port 8765, it also connects to the continuous DJI video relay
on port 8766 using the six-digit code. The Mac decodes the incoming compressed
H.264 stream instead of waiting for a JPEG snapshot every two seconds.

> If the video panel stays black, don't fly or guess at video latency; check
> the hardware aircraft link and follow the video diagnostics.


## FlightHub-inspired Virtual Cockpit redesign

GroundStation uses an **original dark operations design** with the core interaction
patterns studied from the current [DJI FlightHub 2 Virtual Cockpit manual](https://fh.dji.com/user-manual/en/real-time-project-information/virtual-cockpit.html).
It is **not** DJI FlightHub software and the original Mavic Pro is **not**
FlightHub 2 Virtual Cockpit compatible.

The Mac app now includes three workspaces:
1. **Virtual Cockpit** — large continuous H.264 camera view, live MapKit
   aircraft/home/route overlays, flight instruments and Mac-only camera/gimbal controls.
2. **Mission Planning** — locally saved flight-route drafts with manual waypoint
   editing, route overlays and GeoJSON export. This is **offline planning only**;
   uploading or executing waypoint missions is not implemented.
3. **Activity & Logs** — live operator and connection events, with unique IDs.

### Keyboard piloting preview

In Virtual Cockpit, enable **Capture keyboard in cockpit**, then use:

| Input | Proposed movement |
| --- | --- |
| W / S | Forward / back |
| A / D | Left / right |
| Q / E | Yaw left / right |
| C / Z | Ascend / descend |
| SPACE (held) | Additional held-to-move interlock |
| Esc, focus loss, key release | Release keyboard movement |

The new keyboard monitor displays key-state feedback even while flight actuation
is **disabled**. Unlike DJI FlightHub 2, we require holding SPACE as a dead-man
interlock for this custom application's eventual control system. Space is *not*
a takeoff, land or emergency-stop button.

**Current safety lock:** Flight commands are disabled via the intentionally
unset \`GROUNDSTATION_FLIGHT_TESTED\` compile condition. They must not be
unlocked on the strength of working UI or camera alone. Requirements include
secure authenticated transport, end-to-end latency tests, DJI simulator testing,
flight-controller fallback and tests supervised with the original physical RC.
The continuous video feed also needs measured control-to-photon latency.
Please see [Virtual Cockpit Guide](Documentation/VirtualCockpit.md).

### Upgrade (existing branch, no branch switch)

\`\`\`bash
git pull --ff-only origin feature/dji-v4-readonly
xcodegen generate
pod install
open MavicGroundStation.xcworkspace
\`\`\`

Build both \`MacGroundStation\` and \`iOSFlightBridge\` on the Mac and iPhone.


## AI person and vehicle tracking (native Mac)

GroundStation analyses decoded H.264 camera frames **locally** using Apple Vision.
Enable **AI Tracking** in the Virtual Cockpit inspector, click a detected
person, or draw a rectangle around any vehicle/object to track it.
Bounding boxes, confidence and lost-target indicators appear on the live feed.

Person detection works without extra downloads. For automatic car, bus, truck,
motorbike and bicycle recognition, install Apple's optional Core ML YOLOv3 Tiny
model on your Mac (source: Apple ML Models):

```bash
bash scripts/install_vehicle_detector.sh
xcodegen generate
pod install
open MavicGroundStation.xcworkspace
```

This downloads the 8-bit model directly from Apple's public model repository
into a **gitignored** local file. Build the Mac scheme again; the inspector
will indicate whether the detector was successfully loaded.
See [AI Tracking Setup](Documentation/AITracking.md).

The native DJI Mavic Pro **ActiveTrack** API offers a separate two-stage
subject-selection → confirmation → autonomous following mechanism.
The bridge now includes command and status scaffolding for this SDK flow.
**Actual autonomous aircraft following and steering are deliberately locked
by default** until the network transport, physical-controller failsafe and
subject-loss procedures have been verified. A local green AI tracking box
does not mean the aircraft is following that subject.

GroundStation's UI is entirely **native SwiftUI/AppKit/MapKit**, with no
Tailwind, web view or browser-dependent styling. The expanded live camera
mode and material-based panels are influenced by the workspace patterns
found in DJI FlightHub 2, but independently designed and branded.


## FlightHub-style cockpit layout revision (2026-11-19)

The active Mac **Virtual Cockpit** screen was rebuilt after comparing our UI with
DJI's official FlightHub 2 screenshots and documentation:
- https://fh.dji.com/user-manual/en/real-time-project-information/virtual-cockpit.html
- https://enterprise-insights.dji.com/blog/dji-flighthub-2-virtual-cockpit-now-available

The original three-column, card-heavy dashboard is no longer the active cockpit.
The new \`FlightCockpitView.swift\` uses:
- 35%-width **full-height satellite map** on the **left**
- 65%-width **full-height live H.264 feed** on the **right**
- An uninterrupted **bottom OSD deck** for battery, heading dial, altitude,
  horizontal/vertical velocity, flight mode, keyboard preview and flight status
- Compact **top command bar**, with connection pairing in a popover instead of
  using a permanent form row
- Small map toolbar and camera tool rail; AI tracking, camera/gimbal settings,
  aircraft status and flight control notes open as a **contextual drawer**
  over the camera only when requested
- **Map focus** toggles from 35% to 54% map width, without removing the video

This is an independently coded **native SwiftUI/AppKit/MapKit** interface,
not a DJI FlightHub 2 frontend, nor a Tailwind CSS implementation. The
original Mavic Pro is not officially compatible with FlightHub 2.

No changes were made to the iPhone SDK bridge or motor/flight safety lock
in this UI-only iteration.

### Update the Mac UI only

On the **already checked-out** \`feature/dji-v4-readonly\` branch:

\`\`\`bash
git pull --ff-only origin feature/dji-v4-readonly
xcodegen generate
pod install
open MavicGroundStation.xcworkspace
\`\`\`

Select \`MacGroundStation\` in Xcode and press **Cmd+R**. The iPhone bridge
does not need reinstalling for this layout-only update. Click **Connect**
in the upper right, enter your iPhone's IP and the six-digit bridge code.


## Explicitly authorized LIVE flight (experimental — physical aircraft)

**The live-flight code is implemented but has NOT been flight-tested by the
project maintainers. Simulator success does not validate live movement.**

The Mac Virtual Cockpit → **Control** panel supports separate modes:
- **DJI Simulator** — flight commands affect DJI's flight simulator.
- **LIVE FLIGHT** — actual Mavic Pro flight controller receives commands.

LIVE mode is **not automatically enabled** when connecting. The Mac pilot must
connect using the six-digit code and the 256-bit Keychain flight key, verify a
real, grounded Mavic Pro aircraft link, complete the live preflight checklist
and type \`ENABLE LIVE FLIGHT\`. The iPhone independently rejects live
authorization unless DJI reports a linked real Mavic Pro, grounded status,
no IMU preheat, home point, GPS ≥10 satellites, battery ≥40% and fresh flight
telemetry. The authorization lasts 15 minutes and is cleared on link loss.

Once authorized, the Mac can:
- Arm for 30 seconds, confirm **REAL takeoff** via DJI's startTakeoff API
- Enable Virtual Sticks after the aircraft is airborne, then control using
  **SPACE+WASD/QE/CZ** at 10 Hz with limited velocities
- Land or initiate DJI Return-to-Home (RTH) from Mac
- Release control to the physical RC using ESC or **Release to controller**
- Revoke the live pilot session and stop accepting new movement commands

The iPhone independently filters commands, validates telemetry freshness,
maintains its own Virtual Stick watchdog, and sends neutral control before
disabling Virtual Sticks when control is lost.

**Important:** Never attempt real takeoff with propellers removed. Bench tests
with propellers removed are strictly for non-takeoff diagnostics and simulator
testing. Real flight requires a safe outdoor area and a competent operator
with the physical remote controller ready to override. UK users must comply
with the CAA Drone Code and current airspace permissions.

This is NOT flight-certified software; do not rely on the streamed Wi-Fi
video as the sole flight viewpoint. Actual network, signal-loss, battery,
GPS, obstacle, landing-confirmation and manual-override behavior remain
hardware validation tasks. The RC→aircraft lost-signal action must be configured
via DJI GO 4 in advance. **AI autonomous following is still locked**.

Full details: [LIVE flight commissioning](Documentation/LiveFlight.md).
