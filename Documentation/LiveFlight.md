# GroundStation — real-aircraft flight commissioning

**Status: Experimental code pushed, real-aircraft behavior not verified.**
Simulator success confirms command wiring, not reliable live pilot control.

The original Mavic Pro is supported by DJI Mobile SDK v4, which exposes
DJIFlightController.startTakeoff, startLanding, startGoHome and Virtual Sticks
over the linked original remote controller (NOT the Mavic Pro Wi-Fi mode).
DJI recommends a 5–25 Hz Virtual Stick command interval; this bridge uses
10 Hz while enabled. Official reference:
https://developer.dji.com/api-reference/ios-api/Components/FlightController/DJIFlightController.html

## Non-negotiable requirements

- Genuine Mavic Pro linked to its physical RC, iPhone bridge foregrounded,
  Mac and iPhone on reliable trusted Wi-Fi.
- Safe **outdoor** operating area, clear of uninvolved people, animals,
  obstacles, roads and buildings, and within legal visual line of sight.
- Competent pilot continuously ready at the **physical controller** and aware
  of how to take over from Virtual Stick. DJI documents moving the Mavic
  Pro flight-mode switch out of P-mode to override automation:
  https://developer.dji.com/mobile-sdk/documentation/introduction/component-guide-remotecontroller.html
- DJI GO 4 used in advance (not simultaneously connected) to confirm RC
  failsafe behavior, RTH height, home point, aircraft firmware and flight
  settings. Do not assume these settings are correct just because
  GroundStation shows a home point.
- Takeoff area free of obstacles, appropriate wind conditions, usable GPS,
  battery and airspace authorization.
- Use normal VLOS piloting for flight: the Mac's Wi-Fi camera is not a
  certified low-latency piloting link. Monitor real surroundings.

**Do not perform a real takeoff in an indoor bench test or with propellers
removed.** Removing propellers is only for simulator and non-flight tests.

## App operating procedure

1. Update both Mac and iPhone bridge from
   \`feature/dji-v4-readonly\`; open the Xcode **workspace**.
2. With the aircraft grounded and motors off, connect the RC and aircraft.
3. Pair with the bridge key and current session code. Use **Flight-control pairing** on the connected Mac to verify the separate flight key.
4. Open the cockpit with **⌘3**, then choose **Flight setup → Live flight**. Inspect the aircraft readings and resolve any incomplete item.
5. With the aircraft grounded, complete the four pilot acknowledgments and type `ENABLE LIVE FLIGHT`.
6. Choose **Authorize real aircraft (15m)**, confirm and wait for the iPhone’s approval.
7. Choose **Arm for takeoff** and confirm **Take off…** within the 30-second window.
8. Once airborne, choose **Fly with keyboard** and wait for the iPhone’s grant. Press **?** for directions. Hold Space with a direction to move, release Space to request neutral, or press Esc to request controller handoff. The guide also offers local key practice. [Keyboard map](VirtualCockpit.md#virtual-cockpit)
9. For landing, click **Land** and confirm, or initiate RTH only after
   confirming the real home location and flight path.
10. After landing, use **Revoke live controls** and disconnect.

## iPhone-side safeguards implemented

- Live-flight authority exists only in RAM, expires after 15 minutes, and
  is cleared on network disconnect or aircraft disconnect.
- Only encrypted authenticated commands are accepted for movement.
- Explicit authorization requires real DJI aircraft, grounded/no motors,
  ≥40% battery, ≥10 satellites, GPS position and valid home point, IMU ready,
  and flight state received within 1.5 seconds.
- Takeoff requires a distinct 30-second armed window and rechecks GPS/home
  and battery. It never starts automatically on connect.
- Virtual Sticks require airborne status, battery ≥25%, home and GPS ≥8;
  watchdog accepts bounded velocities only.
- Mac sends bounded axes at 10 Hz. Releasing Space sends neutral. The iPhone
  stops Virtual Sticks after 0.8 s without fresh commands; on release it
  attempts to send neutral data before disabling Virtual Stick authority.
- On RC/aircraft drop, battery/IMU abnormality, expired authorization or
  telemetry stall, the iPhone revokes authorization and releases Virtual
  Sticks rather than continuing to send the last motion vector.
- Landing and RTH are separately confirmed, and remain reachable as
  emergency actions even if the live authorization expires.

## Known limitations: must verify before operational flight

- CI compiles the unsigned device bridge with the real DJI iOS SDK and builds the simulator scaffold. Physical aircraft response, SDK simulator behaviour on the controller and motor behaviour require hardware validation.
- No guarantee of physical-RC takeover on Wi-Fi failure or iPhone crash
  until proven in model-specific supervised tests.
- Both app targets must use the same paired TLS protocol. Each protected flight command also requires the separate AES-GCM flight key. The static PSK transport is intended for a local network. [Transport review](WorkspaceReview.md#trust-boundary)
- The flight-video latency, high frame rate, interference and packet loss
  under motion have not been characterized.
- DJI's landing procedure may require additional confirmation near the
  ground. The physical DJI controller must be available to complete landing.
- Obstacle sensing is limited on original Mavic Pro and no independent
  collision-avoidance/geofencing planner has been implemented by this app.
- GroundStation does not promise GPS hold if aircraft GPS becomes unusable.
- Keyboard movement is a direct pilot input, not waypoint guidance or an
  autonomous navigation system.
- **Native DJI ActiveTrack / automatic person and vehicle following remains
  separately locked** until target-loss, obstacle and failsafe behavior
  has been tested on compatible hardware.

Never use real motor actuation simply to test that this code compiles. Use
DJI Simulator for functional tests and carry out real-world validation under
an appropriate supervised flight-test plan.
