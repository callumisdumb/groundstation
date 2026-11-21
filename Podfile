bridge_ios_version = '16.0'
platform :ios, bridge_ios_version

# XcodeGen creates this project locally; its generated scheme contains the bridge target.
project 'MavicGroundStation.xcodeproj'

# Legacy DJI SDK v4 required by the original Mavic Pro.
# DJIWidget is DJI's video decoder; installation on current Xcode still
# requires compatibility checks with the real iPhone 15.
target 'iOSFlightBridge' do
  pod 'DJI-SDK-iOS', '4.16.2'
  pod 'DJIWidget', '1.6.8'
  pod 'DJIFlySafeDatabaseResource', '~> 01.00.01.18'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    next unless target.name == 'DJIWidget'

    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = bridge_ios_version
      # Keep diagnostics from the legacy decoder out of the app's build warnings.
      config.build_settings['GCC_WARN_INHIBIT_ALL_WARNINGS'] = 'YES'
      # In 1.6.8 this file only imports its header and produces an empty object.
      config.build_settings['EXCLUDED_SOURCE_FILE_NAMES'] = '$(inherited) DJIStreamCommon.m'
    end
  end
end
