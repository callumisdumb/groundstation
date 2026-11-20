# DJI Integration Plan

## Version and compatibility gate

This repository targets DJI Mobile SDK v4 for the **original Mavic Pro**. DJI's official iOS SDK repository documents version 4.16.2:

- https://github.com/dji-sdk/Mobile-SDK-iOS
- https://developer.dji.com/mobile-sdk/documentation/quick-start/index.html
- https://developer.dji.com/mobile-sdk/documentation/ios-tutorials/

The iPhone 15, modern iOS releases, your Xcode version and the drone/RC firmware are **not validated**. The iPhone adapter contains SDK registration and aircraft callbacks. Real-device compatibility remains open.

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

## Implemented integration and remaining checks

The Mac provides a local MapKit project, an offline route editor and an H.264 viewer. The iPhone connects through the legacy DJI adapter. Hardware testing must establish registration, current telemetry, sustained video, link recovery and control-authority behaviour. [Hardware test plan](TestingPlan.md) · [Design and security review](WorkspaceReview.md)
