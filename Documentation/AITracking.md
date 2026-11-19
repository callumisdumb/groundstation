# AI People & Vehicle Tracking

## Overview

GroundStation performs computer vision **locally on the Mac** using
Apple Vision, Core ML and VideoToolbox. No cloud AI account is required
and video is not uploaded for AI inference.

- Built-in Apple Vision **human body detection** (no model download)
- Optional Apple Core ML **vehicle classification** using YOLOv3 Tiny
- Click a detection box to select it
- Drag a rectangle over a person, vehicle or other object to track it
- Vision `VNTrackObjectRequest` follows the selected box through frames
- Person/vehicle tracking is **video-only**, not drone movement

The optional Core ML model is excluded from Git because it is a third-party
~9 MB model. The app continues to compile without it.

## Add automatic vehicle recognition

Apple's public Core ML model page:
https://developer.apple.com/machine-learning/models/

From the root of the GroundStation repository:

```bash
bash scripts/install_vehicle_detector.sh
xcodegen generate
pod install
open MavicGroundStation.xcworkspace
```

The installer downloads Apple's official
`YOLOv3TinyInt8LUT.mlmodel` into
`MacGroundStation/Models/GroundStationDetector.mlmodel`.
XcodeGen adds the file to the Mac app target and Xcode compiles it to
`GroundStationDetector.mlmodelc`. The Vision worker loads that resource
from the Mac app bundle.

It detects COCO classes such as car, bus, truck, motorcycle and bicycle.
Results are not guaranteed; detection depends on weather, frame scale,
lighting, occlusions and aircraft camera quality. Accuracy must be validated
on representative data.

You can check whether the model loaded in **Virtual Cockpit → AI Tracking**.

## Using tracking boxes

1. Confirm that the drone is physically connected and the Mac video is live.
2. Select **AI Tracking** in the right inspector.
3. Turn on **Detect people on live video**.
4. Person boxes appear when Vision detects subjects; with the optional model,
   vehicle boxes also appear.
5. Click an object box to select it, or drag to draw your own bounding rectangle.
6. A green dashed box shows the tracked subject. If confidence drops,
   the overlay changes to **TARGET LOST** and movement is not authorised.
7. Click **Clear selection** to stop tracking locally.
8. Open **Activity & Logs** to inspect SDK messages.

## DJI-native autonomous following — deliberately gated

DJI Mobile SDK v4 supports ActiveTrack missions on the original Mavic Pro.
Sources:
- https://developer.dji.com/mobile-sdk/documentation/ios-tutorials/P4MissionsDemo.html
- https://developer.dji.com/api-reference/ios-api/Components/Missions/DJIActiveTrackMissionOperator.html

The custom Mac bridge protocol now has:
- `activeTrackPrepare`: provide a normalised selected subject rectangle
- `activeTrackConfirm`: separately approve DJI aircraft motion
- `activeTrackStop`: request immediate DJI ActiveTrack mission stop
- Status feedback for selected target, mission state, motion and errors

The iPhone contains a `DJIActiveTrackCoordinator` that follows DJI's two-stage
native ActiveTrack model: prepare target for tracking while hovering, **then**
confirm following/steering. When the Mac Wi-Fi link closes, it requests a
stop from the iPhone side. The existing physical DJI RC must remain the
emergency operator override.

**Live autonomous flight is not enabled.**
The project deliberately does not define
`GROUNDSTATION_ACTIVE_TRACK_TESTED` or `GROUNDSTATION_FLIGHT_TESTED`.
Even though native ActiveTrack exists, activation of aircraft steering
requires several independent checks:
- secure authenticated Mac↔iPhone command transport (the current TCP
  with six-digit pairing code is plaintext)
- measured command/video latency; adequate flight camera reliability
- simulator validation of mission start, stop, target loss and re-acquisition
- specific Mavic Pro firmware tests and obstacle limits
- a safe location, the physical controller, visual line of sight and
  CAA-compliant operation

Do NOT turn on test flags to bypass validation. A build that compiles is
not proof that moving the aircraft automatically is safe.

### Important Mavic Pro constraints

DJI's ActiveTrack uses onboard perception; it is not driven by the Mac's
Vision bounding box every frame. The Mac passes a target-selection rectangle
once, then DJI's onboard vision maintains the target.

DJI states that ActiveTrack manages the main camera gimbal itself; the
gimbal must not be manually commanded while DJI tracking is active.
Target following can fail in poor light, near obstacles, or when the target
is lost. For vehicle tracking, don't pursue vehicles over roads or crowds.

## Model and software caveats

The baseline (no-ML-model) GitHub Actions job compiles the Mac/iOS scaffold.
The Apple YOLO model must be downloaded on the Mac and tested in Xcode
separately. A third-party model's classification and tracking accuracy
are not guaranteed by this repository.

The original Mavic Pro's legacy iOS SDK, DJIWidget decoder and actual
hardware remain separate validation requirements.
