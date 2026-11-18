import SwiftUI

struct BridgeView: View {
    @StateObject private var server = BridgeServer()

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 42))
            Text("Mavic Flight Bridge").font(.largeTitle.bold())
            Text("Milestone A • local network prototype")
                .foregroundStyle(.secondary)

            GroupBox("Network server") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Status", value: server.running ? "Listening" : "Stopped")
                    LabeledContent("Address", value: server.localAddress ?? "Finding Wi-Fi address…")
                    LabeledContent("Port", value: "8765")
                    Button(server.running ? "Stop server" : "Start server") {
                        server.running ? server.stop() : server.start()
                    }
                }
                .padding(.vertical, 5)
            }

            GroupBox("DJI connection") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DJI SDK not connected").font(.headline)
                    Text("The status stream is simulated. Next step: validate DJI Mobile SDK v4 on your Mavic Pro and replace the simulator with read-only aircraft telemetry.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Text(server.lastEvent)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .onAppear { server.start() }
        .onDisappear { server.stop() }
    }
}
