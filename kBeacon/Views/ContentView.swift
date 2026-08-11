import SwiftUI
import kbeaconlib2

struct ContentView: View {

    @ObservedObject var viewModel: BeaconViewModel

    var body: some View {

        NavigationStack {

            VStack(spacing: 16) {

                // Connection status card
                ConnectionStatusView(
                    state: viewModel.connectionState,
                    deviceLabel: viewModel.connectedDeviceLabel,
                    onDisconnect: {
                        viewModel.disconnect()
                    }
                )

                // Bluetooth status
                HStack {

                    Circle()
                        .fill(viewModel.isScanning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)

                    Text(viewModel.isScanning
                         ? "Bluetooth: Scanning"
                         : "Bluetooth: Idle")
                        .font(.headline)

                    Spacer()
                }

                // Scan buttons
                HStack(spacing: 16) {

                    Button("Start Scan") {
                        viewModel.startScan()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop Scan") {
                        viewModel.stopScan()
                    }
                    .buttonStyle(.bordered)

                    if viewModel.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                // Live data status
                if viewModel.connectionState == .Connected {

                    LiveDataVerdictView(packetCount: viewModel.packetCount)

                    if !viewModel.receivedPackets.isEmpty {

                        Text("Received packets")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        List(viewModel.receivedPackets) { packet in
                            ReceivedPacketRowView(entry: packet)
                        }
                        .frame(height: 220)
                    }
                }

                Divider()

                // Device list
                if viewModel.discoveredBeacons.isEmpty {

                    Spacer()

                    Text(viewModel.isScanning
                         ? "Scanning for KBeacon devices…"
                         : "No KBeacon devices found")
                        .foregroundColor(.secondary)

                    Spacer()

                } else {

                    ScrollView {

                        LazyVStack(alignment: .leading, spacing: 12) {

                            ForEach(viewModel.discoveredBeacons, id: \.id) { beacon in

                                VStack(alignment: .leading, spacing: 6) {

                                    HStack {

                                        VStack(alignment: .leading, spacing: 2) {

                                            Text(
                                                beacon.name?.isEmpty == false
                                                ? beacon.name!
                                                : "(unnamed device)"
                                            )
                                            .font(.headline)

                                            Text(beacon.mac ?? "Unknown MAC")
                                                .font(.caption)

                                            Text("RSSI: \(beacon.rssi)")
                                                .font(.caption)
                                        }

                                        Spacer()

                                        Button("Connect") {
                                            viewModel.connect(beacon)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }

                                    // Advertisement data
                                    if let mac = beacon.mac,
                                       let advData = viewModel.advDataByMac[mac],
                                       !advData.isEmpty {

                                        Divider()

                                        ForEach(advData) { item in
                                            KeyValueRowView(item: item)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("KBeacon Scanner")
            .onAppear {
                viewModel.startScan()
            }
            .sheet(item: $viewModel.authFailedBeacon) { beacon in

                PasswordPromptView(
                    deviceLabel: beacon.name ?? beacon.mac ?? "Device",
                    onCancel: {
                        viewModel.dismissPasswordPrompt()
                    },
                    onConfirm: { password in
                        viewModel.retryConnectWithPassword(password)
                    }
                )
            }
        }
    }
}

#Preview {

    let client = SupabaseClient(
        baseURL: "https://eeqlwtpeqdtbenscaijt.supabase.co",
        apiKey: "sb_publishable_JNnsFdpBxEPX6NKM-fA8Rw_7TsA339L"
    )

    let logger = BleLogger(client: client)

    return ContentView(
        viewModel: BeaconViewModel(bleLogger: logger)
    )
}

