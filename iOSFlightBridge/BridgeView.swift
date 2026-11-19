import SwiftUI

struct BridgeView: View {
    @StateObject private var server = BridgeServer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Mavic Flight Bridge", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.title2.bold())
                    .lineLimit(2)
                Text("The Mac is the control station. Keep this iPhone app open and connected to the RC.")
                    .font(.subheadline).foregroundStyle(.secondary)
                GroupBox("Mac pairing") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(server.pairingCode)
                            .font(.system(size: 38, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Enter this six-digit code on the Mac. The code changes when the bridge app restarts.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Network server") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Status", value: server.running ? "Listening" : "Stopped")
                        LabeledContent("IP address", value: server.localAddress ?? "Finding Wi-Fi address…")
                        LabeledContent("Port", value: "8765")
                        Button(server.running ? "Stop server" : "Start server") {
                            server.running ? server.stop() : server.start()
                        }
                    }
                }
                GroupBox("DJI aircraft") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(server.djiStatus).font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Read-only diagnostics and DJI SDK relay. Flight controls are operated from the Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(server.lastEvent).font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .onAppear { server.start() }
        .onDisappear { server.stop() }
    }
}
