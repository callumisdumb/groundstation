platform :ios, '16.0'

# XcodeGen creates this project locally; its generated scheme contains the bridge target.
project 'MavicGroundStation.xcodeproj'

# Legacy DJI SDK v4 required by the original Mavic Pro.
# DJIWidget is DJI's video decoder; installation on current Xcode still
# requires compatibility checks with the real iPhone 15.
target 'iOSFlightBridge' do
  pod 'DJI-SDK-iOS', '4.16.2'
  pod 'DJIWidget', '~> 1.6.8'
  pod 'DJIFlySafeDatabaseResource', '~> 01.00.01.18'
end
