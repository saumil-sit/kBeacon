import SwiftUI
import kbeaconlib2

struct ContentView: View {

    @StateObject private var beaconManager = BeaconManager()

    var body: some View {

        NavigationStack {

            VStack(spacing: 16) {

                // Connection status card
                ConnectionStatusView(
                    state: beaconManager.connectionState,
                    deviceLabel: beaconManager.connectedDeviceLabel,
                    onDisconnect: { beaconManager.disconnectCurrent() }
                )

                // Bluetooth status
                HStack {
                    Circle()
                        .fill(beaconManager.bluetoothState == "Powered On" ? .green : .red)
                        .frame(width: 10, height: 10)

                    Text("Bluetooth: \(beaconManager.bluetoothState)")
                        .font(.headline)

                    Spacer()
                }

                // Scan buttons
                HStack(spacing: 16) {

                    Button("Start Scan") {
                        beaconManager.startScan()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop Scan") {
                        beaconManager.stopScan()
                    }
                    .buttonStyle(.bordered)

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

                            ForEach(Array(beaconManager.devices.enumerated()), id: \.offset) { _, device in

                                VStack(alignment: .leading, spacing: 6) {

                                    HStack {

                                        VStack(alignment: .leading, spacing: 2) {

                                            Text(device.name)
                                                .font(.headline)

                                            Text(device.mac)
                                                .font(.caption)

                                            Text("RSSI: \(device.rssi)")
                                                .font(.caption)

                                            Text(device.uuid)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Button("Connect") {
                                            beaconManager.connect(device.beacon)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }

                                    // Advertisement data
                                    if !device.advData.isEmpty {

                                        Divider()

                                        ForEach(device.advData, id: \.id) { item in
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
                beaconManager.startScan()
            }
            .sheet(item: $beaconManager.authFailedBeacon) { beacon in

                PasswordPromptView(
                    deviceLabel: beacon.name ?? beacon.mac ?? "Device",
                    onCancel: {
                        beaconManager.authFailedBeacon = nil
                    },
                    onConfirm: { _ in
                        // Retry logic can be added later
                        beaconManager.authFailedBeacon = nil
                    }
                )
            }
        }
    }
}

#Preview {
    ContentView()
}
