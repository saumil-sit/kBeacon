import Foundation
import SwiftUI
import Combine
import kbeaconlib2

@MainActor
final class BeaconManager: NSObject, ObservableObject {

    // MARK: - Published state

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
    
    @Published var advDataByMac: [String: [KeyValue]] = [:]

    // MARK: - Callbacks for logging

    var onScanResult: ((Bool) -> Void)?
    var onDeviceDiscovered: ((BeaconDeviceModel) -> Void)?
    var onConnectionStateChanged: ((KBeacon, KBConnState, KBConnEvtReason) -> Void)?

    // MARK: - Init

    override init() {
        super.init()

        print("BeaconManager init called")

        KBeaconsMgr.sharedBeaconManager.delegate = self

        print("KBeacon delegate assigned")
    }

    // MARK: - Scan

    func startScan() {

        print("Start scan button tapped")

        devices.removeAll()

        let started = KBeaconsMgr.sharedBeaconManager.startScanning()

        print("KBeacon scan started: \\(started)")

        isScanning = started

        // Notify logger
        onScanResult?(started)
    }

    func stopScan() {

        print("Stop scan button tapped")

        KBeaconsMgr.sharedBeaconManager.stopScanning()

        isScanning = false
    }

    // MARK: - Connect

    func connect(_ beacon: KBeacon) {
        connectionState = .Connecting
        connectedDeviceLabel = beacon.name ?? beacon.mac ?? "Unknown"

        let accepted = beacon.connect(
            "0000000000000000",
            timeout: 20.0,
            delegate: self
        )

        print("Connect API accepted: \\(accepted)")

        if !accepted {

            connectionState = .Disconnected
            connectedDeviceLabel = nil
        }
    }
    
    // MARK: - Disconnect

    func disconnect() {

        print("Disconnect tapped")

        KBeaconsMgr.sharedBeaconManager.stopScanning()

        connectionState = .Disconnected
        connectedDeviceLabel = nil
        packetCount = 0
        receivedPackets.removeAll()
    }

    // MARK: - Password prompt helpers

    func dismissPasswordPrompt() {
        authFailedBeacon = nil
    }

    func retryConnectWithPassword(_ password: String) {

        guard let beacon = authFailedBeacon else { return }

        authFailedBeacon = nil

        connectionState = .Connecting
        connectedDeviceLabel = beacon.name ?? beacon.mac ?? "Unknown"

        let accepted = beacon.connect(
            password,
            timeout: 20.0,
            delegate: self
        )

        print("Retry connect accepted: \\(accepted)")

        if !accepted {

            connectionState = .Disconnected
            connectedDeviceLabel = nil
        }
    }

    func disconnectCurrent() {

        print("Disconnect current device")

        connectionState = .Disconnected
        connectedDeviceLabel = nil
        packetCount = 0
        receivedPackets.removeAll()
    }

    // MARK: - Advertisement parsing

    private func parseAdvData(_ beacon: KBeacon) -> [KeyValue] {

        var rows: [KeyValue] = []

        guard let packets = beacon.allAdvPackets else { return rows }

        for packet in packets {

            if let sensor = packet as? KBAdvPacketSensor {

                if sensor.batteryLevel != KBCfgBase.INVALID_UINT16 {
                    rows.append(KeyValue(
                        key: "Battery",
                        value: "\\(sensor.batteryLevel) mV"
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

            let mapped = beacons.map { beacon in

                BeaconDeviceModel(
                    beacon: beacon,
                    name: beacon.name ?? "Unknown",
                    mac: beacon.mac ?? "Unknown",
                    uuid: beacon.uuidString ?? "N/A",
                    rssi: Int(beacon.rssi),
                    advData: self.parseAdvData(beacon)
                )
            }

            self.devices = mapped

            // Store adv data by MAC
            self.advDataByMac = Dictionary(
                uniqueKeysWithValues: mapped.map { ($0.mac, $0.advData) }
            )

            print("Discovered devices count: \\(mapped.count)")

            for device in mapped {
                onDeviceDiscovered?(device)
            }
        }
    }

    nonisolated func onCentralBleStateChange(newState: BLECentralMgrState) {

        Task { @MainActor in

            switch newState {

            case .PowerOn:

                bluetoothState = "Powered On"
                print("KBeacon Bluetooth powered on")

            case .PowerOff:

                bluetoothState = "Powered Off"
                isScanning = false
                print("KBeacon Bluetooth powered off")

            case .Unauthorized:

                bluetoothState = "Unauthorized"
                isScanning = false
                print("KBeacon Bluetooth unauthorized")

            case .Unknown:

                bluetoothState = "Unknown"
                isScanning = false
                print("KBeacon Bluetooth unknown")

            @unknown default:

                bluetoothState = "Unknown"
                isScanning = false
                print("KBeacon Bluetooth unknown default")
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

            print("Connection state changed: \\(state) reason: \\(evt)")

            self.connectionState = state

            if state == .Connected {

                self.connectedDeviceLabel = beacon.name ?? beacon.mac ?? "Unknown"
            }

            if state == .Disconnected {

                self.connectedDeviceLabel = nil

                if evt == .ConnAuthFail {
                    self.authFailedBeacon = beacon
                }
            }

            // Notify logger
            onConnectionStateChanged?(beacon, state, evt)
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

            print("Packet received count: \\(self.packetCount)")
        }
    }
}
