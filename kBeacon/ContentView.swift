import SwiftUI
import kbeaconlib2

struct ContentView: View {

    @StateObject private var beaconManager = BeaconManager()

    var body: some View {

        NavigationStack {

            VStack {

                // Bluetooth Status
                Text("Bluetooth: \(beaconManager.bluetoothState)")
                    .font(.headline)
                    .padding(.top)

                // Buttons
                HStack(spacing: 16) {

                    Button("Start Scan") {
                        beaconManager.startScan()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop Scan") {
                        beaconManager.stopScan()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                // Device List
                if beaconManager.devices.isEmpty {

                    Spacer()

                    Text("No KBeacon devices found")
                        .foregroundColor(.secondary)

                    Spacer()

                } else {

                    List(beaconManager.devices) { beacon in

                        VStack(alignment: .leading) {

                            Text(beacon.name)
                                .font(.headline)

                            Text(beacon.mac)

                            Text("RSSI: \(beacon.rssi)")

                            Text(beacon.uuid)
                                .font(.caption)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("KBeacon Scanner")
        }
    }
}

#Preview {
    ContentView()
}
