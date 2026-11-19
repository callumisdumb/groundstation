import SwiftUI
import UIKit

struct BridgeView: View {
    @StateObject private var server = BridgeServer()
    @State private var showFlightKey = false
    @State private var copiedKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Mavic Flight Bridge", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.title2.bold())
                Text("Mac-controlled communications relay. Leave this app open with the iPhone connected to the remote controller.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label("Screen stays awake while Flight Bridge is active", systemImage: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.green)
                GroupBox("Pair with Mac") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(server.pairingCode)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Enter this code on the Mac. No flight controls are on this phone.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Encrypted Mac flight-control pairing") {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("256-bit flight key · one-time setup", systemImage: "lock.shield.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Copy this key once to the Mac's Connect panel. The key is stored in both devices' Keychains and is never sent over the Wi-Fi link.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if showFlightKey {
                            Text(server.flightAccessKey)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("••••••••••••••••••••••••••••••••")
                                .font(.system(size: 13, design: .monospaced))
                        }
                        HStack {
                            Button {
                                UIPasteboard.general.string = server.flightAccessKey
                                copiedKey = true
                            } label: {
                                Label(copiedKey ? "Copied" : "Copy flight key",
                                      systemImage: copiedKey ? "checkmark" : "doc.on.doc")
                            }
                            .disabled(server.flightAccessKey.isEmpty)
                            Button(showFlightKey ? "Hide" : "Reveal") {
                                showFlightKey.toggle()
                            }
                        }
                        Text("Keep this key private. Flight commands stay locked until the Mac verifies it.")
                            .font(.caption2).foregroundStyle(.orange)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Network server") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Status", value: server.running ? "Listening" : "Stopped")
                        LabeledContent("Address", value: server.localAddress ?? "Finding Wi-Fi address…")
                        LabeledContent("Telemetry / commands", value: "8765")
                        LabeledContent("Live H.264 video", value: "8766")
                        Button(server.running ? "Stop" : "Start") {
                            server.running ? server.stop() : server.start()
                        }
                    }
                }
                GroupBox("DJI link") {
                    Text(server.djiStatus).font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("DJI camera decoder (relay source)") {
                    DJIFramePreviewSurface()
                        .frame(height: 155)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .bottomLeading) {
                            Text("H.264 forwarded continuously to Mac on port 8766")
                                .font(.system(size: 9))
                                .padding(6)
                                .background(.black.opacity(0.7))
                        }
                }
                Text(server.lastEvent).font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }.padding(16)
        }
        .onAppear { server.start() }
        .onDisappear { server.stop() }
    }
}
