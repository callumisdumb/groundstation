# DJI Integration Plan

## Version and compatibility gate

This repository targets DJI Mobile SDK v4 for the **original Mavic Pro**. DJI's official iOS SDK repository documents version 4.16.2:

- https://github.com/dji-sdk/Mobile-SDK-iOS
- https://developer.dji.com/mobile-sdk/documentation/quick-start/index.html
- https://developer.dji.com/mobile-sdk/documentation/ios-tutorials/

The iPhone 15, modern iOS releases, your Xcode version and the drone/RC firmware are **not validated**. This scaffold does not implement DJI SDK registration or aircraft communication.

## Prerequisites

1. Record macOS and Xcode versions using \`sw_vers\` and \`xcodebuild -version\`.
2. Record the iOS version, aircraft firmware, and remote-controller firmware.
3. Create a DJI developer account and obtain a valid app key. Do not commit credentials.
4. Clone the official DJI Mobile SDK iOS repository.
5. Follow its Swift sample setup and Cocoapods install, and enter \`DJISDKAppKey\` as its instructions require.
6. Run the official sample on the *actual* iPhone 15 with the Mavic Pro controller connected using the correct USB-C data cable.
7. Verify registration, activation where required, connected product/model, aircraft telemetry and battery callbacks.
8. Stop if the official sample does not work: don't build the custom flight system on an unverified SDK assumption.

## Adapter contract

After the official sample works, implement \`iOSFlightBridge/DJIAdapter.swift\`:

- Subscribe to SDK registration/connection state.
- Subscribe to read-only aircraft location and flight controller state callbacks.
- Subscribe to battery, gimbal and camera status.
- Convert the values to \`GroundStationMessage.Payload\`.
- Set \`simulated = false\` **only** for real SDK callbacks.
- Deliver messages via the local bridge; never expose DJI framework types to the Mac project.

## Future roadmap

- Local video decoding on iPhone, then WebRTC encoded feed to Mac.
- Map display with GPS tracks and telemetry logging.
- Waypoint editor and mission management.
- Flight control only after separate safety review, simulator tests, arming/authorisation design, watchdog and physical-controller fallback.
- Encrypted authenticated VPN transport for remote **monitoring**, before any internet command path.

Do not enable unrestricted internet flight control or use virtual joysticks with unverified latency/failsafe handling.
