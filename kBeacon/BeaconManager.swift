import Foundation
import SwiftUI
import Combine
import kbeaconlib2

@MainActor
final class BeaconManager: NSObject, ObservableObject {

    @Published var devices: [BeaconDevice] = []
    @Published var bluetoothState: String = "Unknown"

    override init() {
        super.init()

        KBeaconsMgr.sharedBeaconManager.delegate = self
    }

    func startScan() {
        devices.removeAll()
        _ = KBeaconsMgr.sharedBeaconManager.startScanning()
    }

    func stopScan() {
        KBeaconsMgr.sharedBeaconManager.stopScanning()
    }
}

extension BeaconManager: KBeaconMgrDelegate {

    func onBeaconDiscovered(beacons: [KBeacon]) {

        for beacon in beacons {

            let device = BeaconDevice(
                name: beacon.name ?? "Unknown",
                mac: beacon.mac ?? "SIT",
                uuid: beacon.uuidString ?? "123456",
                rssi: Int(beacon.rssi)
            )

            if !devices.contains(where: { $0.mac == device.mac }) {
                devices.append(device)
            }
        }
    }

    func onCentralBleStateChange(newState: BLECentralMgrState) {

        switch newState {
        case .PowerOn:
            bluetoothState = "Powered On"

        case .PowerOff:
            bluetoothState = "Powered Off"

        case .Unauthorized:
            bluetoothState = "Unauthorized"

        case .Unknown:
            bluetoothState = "Unknown"

        @unknown default:
            bluetoothState = "Unknown"
        }
    }
}
