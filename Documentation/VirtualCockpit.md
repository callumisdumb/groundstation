# GroundStation — Virtual Cockpit

## Design reference

Reviewed DJI's current FlightHub 2 Virtual Cockpit guide (updated 2026-11-17):
- https://fh.dji.com/user-manual/en/real-time-project-information/virtual-cockpit.html
- https://enterprise.dji.com/flighthub-2
- https://fh.dji.com/user-manual/en/flight-route-library/edit-waypoint-flight-routes.html

Its layout combines the main video feed, map, flight instruments, a function
operation area, route library, device status and keyboard flight controls.

GroundStation reinterprets those concepts with its own brand, UI code and
architecture. FlightHub 2's enterprise-only features and dock workflows
do not magically become available on the original Mavic Pro.

## Implemented in macOS

- Native SwiftUI three-screen navigation with dark operational styling
- Mac ↔ iPhone connection and six-digit pairing UI
- Large native H.264 camera view with decoded-FPS status
- Dedicated DJI camera photo/record and gimbal pitch controls on Mac
- Aircraft MapKit map, home marker, planned-route markers and flight track
- Aircraft altitude, speed, battery, satellites, heading and flight time
- Device health and read-only flight status inspector
- Keyboard pilot **preview**, not physically enabled commands
- Local mission library with saved routes, waypoint table and GeoJSON export
- Activity and connection log with stable unique event identifiers

## Desktop keyboard mapping

| Key | Function |
| --- | --- |
| W | Forward |
| S | Backward |
| A | Move left |
| D | Move right |
| Q | Rotate left |
| E | Rotate right |
| C | Ascend |
| Z | Descend |
| SPACE | Hold-to-move interlock |
| ESC | Release all held movement commands |

This follows DJI's documented WASD/QE/CZ movement pattern with an additional
SPACE-held safety layer. The current \`KeyboardPilotController\` reads keys only
while keyboard capture is enabled, the Mac application has focus and no text
field is being edited. It releases control on deactivation and disconnect.
It must also receive a successfully acknowledged Virtual Stick enable event
and valid aircraft flight state before sending movement commands.

### Why the keyboard doesn't move the drone yet

The original physical DJI controller is the only proven flight-control path.
Although DJI Mobile SDK v4 provides Virtual Stick APIs, the custom iPhone bridge
currently uses unencrypted TCP between Mac/iPhone and has not had flight-
actuation latency or end-to-end failsafe qualification. It intentionally
rejects takeoff, landing, motor, RTH and stick input on actual aircraft.

Live video decoding does *not* guarantee safe flight video latency. Continue
testing without propellers and do not enable flight output simply to trial keys.

## Waypoint planning

The Mission Planning tab saves mission drafts in the user's macOS
Application Support directory under \`GroundStation/mission-routes.json\`.
Add waypoints by entering WGS84 latitude and longitude and a chosen altitude
or by adding the current GPS position when an actual aircraft location exists.
Export GeoJSON to use in GIS software.

**No upload/execute/schedule button is available.** Mission planning is
a separate desktop feature, pending a model-specific DJI Mavic Pro SDK
mission integration and thorough safety validation.

## What remains unimplemented

- FlightHub 2 cloud projects/team accounts, route collaboration and media sync
- Dock-based scheduling and automated dispatch
- Safe manual flight control over the Mac keyboard
- Validated cloud remote piloting, TLS, production authentication
- Live AI recognition, 3D maps, aircraft-dock management
- Photogrammetry/model-generation pipelines
- Audio and camera metadata beyond current supported SDK telemetry
- Fully measured flight-quality low-latency video
- DJI flight-controller control-authority arbitration and emergency failsafe tests

These features need substantial development, additional compatible hardware
or specific SDK support; they are **not** implied by the current UI.

## Testing

1. Stay on the current branch, pull, run \`xcodegen generate\`, \`pod install\`.
2. Open \`MavicGroundStation.xcworkspace\`, rebuild Mac and iOS targets.
3. With **propellers removed**, connect the Mavic Pro and RC to the iPhone.
4. Connect from Mac using IP + pairing code. Confirm telemetry and live H.264.
5. Choose **Virtual Cockpit**, toggle keyboard capture and press WASD.
   Keys illuminate in keyboard preview. DJI Simulator input moves the simulated drone; real movement requires the separately authorized experimental LIVE mode in LiveFlight.md.
6. Create a local route in **Mission Planning**, add points, export GeoJSON.
7. Check status messages in **Activity & Logs**.
8. If Xcode errors, capture exact lines from the build report.

Hardware DJI SDK v4/CocoaPods builds cannot be validated by GitHub's
scaffold-only CI and require your actual iPhone 15 and aircraft.

Safety: follow UK CAA rules and maintain visual line of sight. A Wi-Fi
video display is not a replacement for the original RC link or in-person
pilot observation.


## Revised cockpit presentation (2026-11-19)

The main Virtual Cockpit is **no longer** the previous side-navigation,
three-column set of cards. It has been replaced by a new
\`MacGroundStation/FlightCockpitView.swift\`, after comparing the layout against
the official DJI FlightHub 2 interface.

- Full-height **MapKit satellite map on the left**; overlays show current
  aircraft GPS and the planned mission only when the data exists.
- Large full-height **native H.264 camera** on the right with compact status
  overlay, AI target selection and unobtrusive camera controls.
- Fixed **bottom instrument/control ribbon**, including a graphical orientation
  dial, battery, satellites, speed, altitude, velocity, flight mode, keyboard
  preview and deliberately disabled flight-actuation controls.
- Connection and pairing via a top-right macOS popover, not a wide toolbar
  containing permanent IP and pairing input fields.
- Map-focus/video-focus split toggle and a context drawer for camera,
  aircraft status, AI tracking and flight-control information.
- Mission Planning and Activity remain available from the compact top menu.

The design follows DJI's **spatial hierarchy** (map / camera / instrument
ribbon / contextual tools), but uses independent colors, typography,
symbol art and native SwiftUI code. This is not an official DJI UI integration.

The local **iPhone bridge protocol is unchanged** by this layout revision.
Do not reinstall the phone simply to receive these visual changes.

Hardware telemetry, video decoding and original Mavic Pro DJI SDK v4 remain
subject to real-device testing. Flight/motor/autonomous motion continue to be
locked in the default build.
