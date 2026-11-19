# Test Plan

## Milestone A (verified by operator screenshot)

- [x] iOS bridge and Mac dashboard communicate over local TCP port 8765.
- [x] Mac receives one simulated \`aircraftStatus\` message per second.
- [x] Source is explicitly marked SIMULATED.

## Milestone B: DJI registration and read-only telemetry (not yet verified)

- [ ] Confirm the DJI Developer portal app is activated.
- [ ] Confirm app Bundle Identifier exactly matches \`com.benmacaulay.mavic.flightbridge\`.
- [ ] Configure local gitignored \`Configurations/DJIKeys.xcconfig\`.
- [ ] Check iOS/Xcode compatibility by building the official DJI iOS Swift sample.
- [ ] Confirm official sample registers and detects original Mavic Pro.
- [ ] Build the branch \`feature/dji-v4-readonly\` with CocoaPods linked.
- [ ] Remove drone propellers for bench testing.
- [ ] Connect original Mavic Pro RC to iPhone 15 via USB-C data cable; verify aircraft link.
- [ ] Show actual aircraft connection, battery, location, speed and altitude in Mac.
- [ ] Verify disconnected aircraft clears stale readings.
- [ ] Verify Mac Wi-Fi disconnect leaves aircraft flight unaffected.
- [ ] Confirm no flight-command methods are present.

## Later (not implemented)

- [ ] Live video rendering and streaming.
- [ ] Camera/gimbal controls.
- [ ] Flight planning (offline first).
- [ ] Separately reviewed flight-control implementation.
