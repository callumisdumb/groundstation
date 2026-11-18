# iPhone network permissions

The XcodeGen \`project.yml\` sets:

- \`NSLocalNetworkUsageDescription\` — explains local Mac/iPhone communication.

In Xcode verify the key appears in the generated iOS target's Info settings. If iOS does not prompt, inspect Settings > Privacy & Security > Local Network. This first prototype uses manually entered IP addresses; Bonjour discovery is not yet implemented.

Do not enable arbitrary public-network access or port forwarding for this prototype.
