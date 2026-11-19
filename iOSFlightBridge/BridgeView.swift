import SwiftUI

struct BridgeView: View {
    @StateObject private var server = BridgeServer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Mavic Flight Bridge", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.title2.bold())
                Text("Mac-controlled communications relay. Leave this app open with the iPhone connected to the remote controller.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                GroupBox("Pair with Mac") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(server.pairingCode)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Enter this code on the Mac. No flight controls are on this phone.")
                            .font(.caption).foregroundStyle(.secondary)
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
