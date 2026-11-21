import SwiftUI

struct BridgeConnectionView: View {
    @ObservedObject var client: BridgeClient
    @Binding var host: String
    @State private var flightSetup = false
    @State private var flightKeyDraft = ""
    private var canEditFlightKey: Bool {
        !client.connecting && (!client.connected || (!client.flightKeyVerified && client.stickAuthority == .idle))
    }
    private var busy: Bool { client.connecting || client.connected }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bridge connection", systemImage: "iphone").font(.headline)
            Text("Use the address and current code shown on the iPhone.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("iPhone Wi-Fi address")
                TextField("192.168.1.20", text: $host).accessibilityLabel("iPhone Wi-Fi address")
                Text("Session code").padding(.top, 4)
                SecureField("Six digits", text: $client.pairingCode).accessibilityLabel("Session code")
                Text("Bridge key").padding(.top, 4)
                SecureField("Paste bridge key", text: $client.bridgeKeyInput).accessibilityLabel("Bridge key")
                if client.bridgeKeyInput.isEmpty && client.bridgeKey != nil {
                    Text("Using your paired flight key to establish the link.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(busy)
            Divider()
            DisclosureGroup("Flight-control pairing", isExpanded: $flightSetup) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(client.flightKeyVerified ? "Flight key verified on this connection." : "Paste the flight key from the iPhone to unlock preflight checks.")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("Flight key", text: $flightKeyDraft)
                        .disabled(!canEditFlightKey)
                    Button(client.connected ? "Verify flight key" : "Save flight key") { client.saveFlightKey(flightKeyDraft) }
                        .disabled(!canEditFlightKey || !FlightSecurity.validKey(flightKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)))
                }.padding(.top, 5)
            }
            Divider()
            HStack {
                Text(client.connectionStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("connection-status")
                Spacer()
                if busy {
                    Button(client.connected ? "Disconnect" : "Cancel") { client.disconnect() }
                } else {
                    Button("Connect") {
                        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
                        client.connect(host: host, port: 8765)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              !BridgeTransport.validCode(client.pairingCode) || client.bridgeKey == nil)
                }
            }
        }
        .onAppear {
            flightKeyDraft = client.flightKeyInput
            flightSetup = client.connected && !client.flightKeyVerified
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12))
        .padding(18).frame(width: 325)
    }
}
