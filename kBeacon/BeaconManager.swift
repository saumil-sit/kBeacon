import Foundation
import SwiftUI
import CoreBluetooth
import Combine

// Temporary model for UI.
// Remove this struct if the real KBeacon SDK already provides a device model.
struct BeaconDevice: Identifiable {
    let id = UUID()
    let name: String
    let mac: String
    let rssi: Int
}

@MainActor
final class BeaconManager: NSObject, ObservableObject, CBCentralManagerDelegate {

    @Published var bluetoothState: String = "Unknown"
    @Published var devices: [BeaconDevice] = []

    private var centralManager: CBCentralManager!

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        devices.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    func stopScan() {
        centralManager.stopScan()
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            bluetoothState = "Unknown"
        case .resetting:
            bluetoothState = "Resetting"
        case .unsupported:
            bluetoothState = "Unsupported"
        case .unauthorized:
            bluetoothState = "Unauthorized"
        case .poweredOff:
            bluetoothState = "Powered Off"
        case .poweredOn:
            bluetoothState = "Powered On"
        @unknown default:
            bluetoothState = "Unknown"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let name = peripheral.name ?? "Unknown Device"
        let mac = peripheral.identifier.uuidString

        devices.append(
            BeaconDevice(
                name: name,
                mac: mac,
                rssi: RSSI.intValue
            )
        )
    }
}
