import SwiftUI
import kbeaconlib2

struct ContentView: View {

    @ObservedObject var viewModel: BeaconViewModel
    @ObservedObject var beaconManager: BeaconManager

    var body: some View {

        NavigationStack {

            VStack(spacing: 16) {

                // Connection status card
                ConnectionStatusView(
                    state: beaconManager.connectionState,
                    deviceLabel: beaconManager.connectedDeviceLabel,
                    onDisconnect: {
                        beaconManager.disconnect()
                        viewModel.disconnect()
                    }
                )

                // Bluetooth status
                HStack {

                    Circle()
                        .fill(beaconManager.isScanning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)

                    Text(beaconManager.isScanning
                         ? "Bluetooth: Scanning"
                         : "Bluetooth: Idle")
                        .font(.headline)

                    Spacer()
                }

                // Scan buttons
                HStack(spacing: 16) {

                    Button("Start Scan") {
                        beaconManager.startScan()
                        viewModel.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(beaconManager.isScanning)

                    Button("Stop Scan") {
                        beaconManager.stopScan()
                        viewModel.stopScan()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!beaconManager.isScanning)

                    if beaconManager.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                // Live data status
                if beaconManager.connectionState == .Connected {

                    LiveDataVerdictView(packetCount: beaconManager.packetCount)

                    if !beaconManager.receivedPackets.isEmpty {

                        Text("Received packets")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        List(beaconManager.receivedPackets) { packet in
                            ReceivedPacketRowView(entry: packet)
                        }
                        .frame(height: 220)
                    }
                }

                Divider()

                // Device list
                if beaconManager.devices.isEmpty {

                    Spacer()

                    Text(beaconManager.isScanning
                         ? "Scanning for KBeacon devices…"
                         : "No KBeacon devices found")
                        .foregroundColor(.secondary)

                    Spacer()

                } else {

                    ScrollView {

                        LazyVStack(alignment: .leading, spacing: 12) {

                            ForEach(beaconManager.devices, id: \.id) { beacon in

                                VStack(alignment: .leading, spacing: 6) {

                                    HStack {

                                        VStack(alignment: .leading, spacing: 2) {

                                            Text(
                                                beacon.name.isEmpty == false
                                                ? beacon.name
                                                : "(unnamed device)"
                                            )
                                            .font(.headline)

                                            Text(beacon.mac.isEmpty ? "Unknown MAC" : beacon.mac)
                                                .font(.caption)

                                            Text("RSSI: \(beacon.rssi)")
                                                .font(.caption)
                                        }

                                        Spacer()

                                        Button("Connect") {
                                            beaconManager.connect(beacon.beacon)
                                            viewModel.connect(beacon.beacon)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }

                                    // Advertisement data
                                    if let advData = beaconManager.advDataByMac[beacon.mac],
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
                viewModel.logAppOpened()
            }
            .sheet(item: $beaconManager.authFailedBeacon) { beacon in

                PasswordPromptView(
                    deviceLabel: beacon.name ?? beacon.mac ?? "Device",
                    onCancel: {
                        beaconManager.dismissPasswordPrompt()
                        viewModel.dismissPasswordPrompt()
                    },
                    onConfirm: { password in
                        viewModel.retryConnectWithPassword(password)
                        beaconManager.retryConnectWithPassword(password)
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

    let viewModel = BeaconViewModel(bleLogger: logger)
    let beaconManager = BeaconManager()

    return ContentView(
        viewModel: viewModel,
        beaconManager: beaconManager
    )
}
