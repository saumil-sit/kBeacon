import Foundation
import SwiftUI
import Combine
import kbeaconlib2

@MainActor
final class BeaconManager: NSObject, ObservableObject {

    @Published var devices: [BeaconDeviceModel] = []
    @Published var bluetoothState: String = "Unknown"
    @Published var isScanning = false

    // Connection state
    @Published var connectionState: KBConnState = .Disconnected
    @Published var connectedDeviceLabel: String?

    // Password prompt
    @Published var authFailedBeacon: KBeacon?

    // Packet history
    @Published var packetCount = 0
    @Published var receivedPackets: [ReceivedPacketEntry] = []

    override init() {
        super.init()
        KBeaconsMgr.sharedBeaconManager.delegate = self
    }

    func startScan() {
        devices.removeAll()
        let started = KBeaconsMgr.sharedBeaconManager.startScanning()
        isScanning = started
    }

    func stopScan() {
        KBeaconsMgr.sharedBeaconManager.stopScanning()
        isScanning = false
    }

    // Connect with default password
    func connect(_ beacon: KBeacon) {
        connectionState = .Connecting
        connectedDeviceLabel = beacon.name ?? beacon.mac ?? "Unknown"

        let accepted = beacon.connect(
            "0000000000000000",
            timeout: 20.0,
            delegate: self
        )

        if !accepted {
            connectionState = .Disconnected
            connectedDeviceLabel = nil
        }
    }

    func disconnectCurrent() {
        connectionState = .Disconnected
        connectedDeviceLabel = nil
        packetCount = 0
        receivedPackets.removeAll()
    }

    // MARK: Advertisement parsing

    private func parseAdvData(_ beacon: KBeacon) -> [KeyValue] {
        var rows: [KeyValue] = []

        guard let packets = beacon.allAdvPackets else { return rows }

        for packet in packets {

            if let sensor = packet as? KBAdvPacketSensor {

                if sensor.batteryLevel != KBCfgBase.INVALID_UINT16 {
                    rows.append(KeyValue(
                        key: "Battery",
                        value: "\(sensor.batteryLevel) mV"
                    ))
                }

                if sensor.temperature != KBCfgBase.INVALID_FLOAT {
                    rows.append(KeyValue(
                        key: "Temperature",
                        value: String(format: "%.2f°C", sensor.temperature)
                    ))
                }

                if sensor.humidity != KBCfgBase.INVALID_FLOAT {
                    rows.append(KeyValue(
                        key: "Humidity",
                        value: String(format: "%.2f%%", sensor.humidity)
                    ))
                }
            }
        }

        return rows
    }
}

// MARK: - Scan delegate

extension BeaconManager: KBeaconMgrDelegate {

    nonisolated func onBeaconDiscovered(beacons: [KBeacon]) {

        Task { @MainActor in

            self.devices = beacons.map { beacon in

                BeaconDeviceModel(
                    beacon: beacon,
                    name: beacon.name ?? "Unknown",
                    mac: beacon.mac ?? "Unknown",
                    uuid: beacon.uuidString ?? "N/A",
                    rssi: Int(beacon.rssi),
                    advData: self.parseAdvData(beacon)
                )
            }
        }
    }

    nonisolated func onCentralBleStateChange(newState: BLECentralMgrState) {

        Task { @MainActor in

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
}

// MARK: - Connection delegate

extension BeaconManager: ConnStateDelegate {

    nonisolated func onConnStateChange(
        _ beacon: KBeacon,
        state: KBConnState,
        evt: KBConnEvtReason
    ) {

        Task { @MainActor in

            self.connectionState = state

            if state == .Disconnected {

                self.connectedDeviceLabel = nil

                if evt == .ConnAuthFail {
                    self.authFailedBeacon = beacon
                }
            }
        }
    }
}

// MARK: - Notify delegate

extension BeaconManager: NotifyDataDelegate {

    nonisolated func onNotifyDataReceived(
        _ beacon: KBeacon,
        evt: Int,
        data: Data
    ) {

        Task { @MainActor in

            self.packetCount += 1

            let hex = data.map { String(format: "%02X", $0) }.joined()

            let entry = ReceivedPacketEntry(
                timestamp: DateFormatter.localizedString(
                    from: Date(),
                    dateStyle: .none,
                    timeStyle: .medium
                ),
                eventType: evt,
                rawHex: hex,
                byteCount: data.count
            )

            self.receivedPackets.insert(entry, at: 0)
        }
    }
}
