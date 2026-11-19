# DJI App Key and real aircraft connection (iPhone 15 + Original Mavic Pro)

## DJI developer portal

Your DJI developer app has already been created as a **Mobile SDK / iOS** app.

**Bundle Identifier:** \`com.benmacaulay.mavic.flightbridge\`

Keep that identifier byte-for-byte identical in DJI Developer Center and the iPhone app's \`PRODUCT_BUNDLE_IDENTIFIER\`. The generated App Key is bound to this value.

1. Visit https://developer.dji.com/user/apps .
2. Open the app and check whether DJI requires you to activate it using an email confirmation.
3. Copy your **App Key** privately. It is an SDK application identifier; avoid posting it in public GitHub.
4. Do **not** register another app and do **not** use Mobile SDK v5 for the original Mavic Pro. This repository targets iOS SDK **v4.16.2**.

## Configure the Xcode project

You have already proven the Mac↔iPhone simulator works. Preserve that working milestone.

From Terminal:

\`\`\`bash
git fetch origin
git switch feature/dji-v4-readonly
xcodegen generate
cp Configurations/DJIKeys.xcconfig.example Configurations/DJIKeys.xcconfig
\`\`\`

Open the newly created \`Configurations/DJIKeys.xcconfig\` file and replace only the placeholder with your actual DJI App Key:

\`\`\`text
DJI_SDK_APP_KEY = <paste-the-key-from-your-DJI-account>
\`\`\`

The real file is gitignored. **Never commit it.** If Xcode fails to find it, confirm \`Configurations/Bridge.xcconfig\` includes the optional local config file. Xcode embeds the value in \`DJISDKAppKey\` within \`iOSFlightBridge/Info.plist\` at build time.

Important: your app **Bundle Identifier has changed** from the previous placeholder to the DJI-registered \`com.benmacaulay.mavic.flightbridge\`. Run \`xcodegen generate\` after switching branches. If signing complains, select your Apple Team again and enable automatic signing.

## First validate DJI's official sample

DJI SDK v4 is legacy software; a listed Mavic Pro support entry does **not** prove compatibility with modern iOS/Xcode/iPhone 15.

Get DJI's [official Swift sample](https://github.com/dji-sdk/Mobile-SDK-iOS/tree/master/Sample%20Code/SwiftSampleCode).

Use a local clone separate from GroundStation:

\`\`\`bash
git clone https://github.com/dji-sdk/Mobile-SDK-iOS.git
cd Mobile-SDK-iOS/"Sample Code"/SwiftSampleCode
pod install
open DJISDKSwiftDemo.xcworkspace
\`\`\`

Before running the official sample, create a **second DJI iOS app** in Developer Center for its own unique Bundle Identifier, OR change the Swift sample target's bundle identifier to your already registered \`com.benmacaulay.mavic.flightbridge\` and use your existing key. The latter is simplest if you are only running one iPhone app at a time. Replace the sample's \`DJISDKAppKey\` Info.plist placeholder using a local, non-committed edit.

Make sure the sample **builds and registers with DJI** before moving to the custom bridge integration.

## DJI SDK build into GroundStation

Once the official sample is confirmed functional:

\`\`\`bash
cd /path/to/groundstation
xcodegen generate
# Install CocoaPods if necessary: sudo gem install cocoapods
pod install
open MavicGroundStation.xcworkspace
\`\`\`

Select the **iOSFlightBridge** scheme and iPhone 15 device, confirm **Signing & Capabilities → Automatically manage signing** and the correct Team, then press **Run**.

The \`Podfile\` pins \`DJI-SDK-iOS\` v4.16.2. If this old SDK fails to compile or link under your current Xcode/iOS version, capture the exact error; don't change SDK majors or rewrite calls blindly.

## Physical connection

1. Keep the iPhone and Mac on the same trusted Wi-Fi network. DJI may require initial internet access for App Key activation.
2. Turn off the Mavic Pro propellers for bench testing **by removing them** before powering on the aircraft.
3. Power on the standard DJI remote controller and aircraft, and confirm they link.
4. Connect the iPhone 15 to the controller with a compatible **Mavic Pro USB-C remote-controller cable** (side controller port), or a compatible data cable through the controller's bottom USB port with the side cable disconnected.
5. Unlock the iPhone, respond to any accessory permission prompts, keep the Flight Bridge app in the foreground.
6. Look for DJI SDK registered / DJI aircraft connected on the iPhone.
7. Connect the Mac dashboard to the iPhone IP as before. It should show read-only GPS, altitude, speed and battery **only after real DJI callbacks arrive**.

The bridge's port \`8765\` is unencrypted and unauthenticated: **LAN test only, never port-forward**.

## What has NOT been implemented

- Camera video stream
- Gimbal and camera controls
- Waypoint missions
- Virtual sticks, takeoff/landing, return-to-home
- Remote internet control
- Flight failsafe validation

Keep the physical controller and DJI failsafes in normal operation. Do not fly using this code. Check applicable UK CAA flight rules.
