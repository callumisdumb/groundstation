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
unencrypted LAN + sampled JPEG video are not suitable for live flight control. They
must not be enabled simply by changing a build flag without a secure transport and
controlled hardware/simulator testing. A checked, production pilot must have the physical
controller and direct visual line of sight.

Camera video is an experimental DJIWidget decoder on iPhone, relaying a JPEG snapshot
every ~2 seconds to Mac; this is not an FPV piloting feed. DJIWidget may require legacy
Xcode compatibility work. See
[Mac-only controls and testing](Documentation/MacControlTesting.md).
