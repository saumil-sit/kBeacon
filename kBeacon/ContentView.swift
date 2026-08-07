//  ContentView.swift
//  kBeacon

import SwiftUI
import CoreBluetooth
// import kbeaconlib2   // Uncomment only after the SDK is added correctly

struct ContentView: View {

    @StateObject private var beaconManager = BeaconManager()

    var body: some View {

        NavigationView {

            VStack(spacing: 16) {

                Text("Bluetooth: \(beaconManager.bluetoothState)")
                    .font(.headline)

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

                if beaconManager.devices.isEmpty {

                    Spacer()

                    Text("No KBeacon devices found")
                        .foregroundColor(.secondary)

                    Spacer()

                } else {

                    List(beaconManager.devices, id: \.mac) { beacon in

                        VStack(alignment: .leading, spacing: 4) {

                            Text(beacon.name)
                                .font(.headline)

                            Text("Identifier: \(beacon.mac)")
                                .font(.subheadline)

                            Text("RSSI: \(beacon.rssi)")
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("KBeacon Devices")
        }
    }
}

#Preview {
    ContentView()
}
