import Foundation
import Combine
import kbeaconlib2

final class BeaconViewModel: ObservableObject {

    @Published var connectionState: KBConnState = .Disconnected
    @Published var connectedDeviceLabel: String? = nil
    @Published var isScanning: Bool = false
    @Published var packetCount: Int = 0
    @Published var receivedPackets: [ReceivedPacketEntry] = []
    @Published var discoveredBeacons: [KBeacon] = []
    @Published var advDataByMac: [String: [KeyValue]] = [:]
    @Published var authFailedBeacon: KBeacon? = nil

    private let bleLogger: BleLogger

    // Same pattern as Android
    private var scanCorrelationId = UUID().uuidString
    private var connectCorrelationId = UUID().uuidString

    init(bleLogger: BleLogger) {
        self.bleLogger = bleLogger
    }

    // MARK: - Scan

    func startScan() {

        scanCorrelationId = UUID().uuidString

        // Android event
        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "scan_requested_by_user"
        )

        isScanning = true

        // Android event
        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "scan_started"
        )
    }

    func stopScan() {

        isScanning = false

        // Android event
        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "scan_stopped"
        )
    }

    // MARK: - Connect

    func connect(_ beacon: KBeacon) {

        connectCorrelationId = UUID().uuidString

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "connect_requested",
            deviceMac: beacon.mac
        )

        connectedDeviceLabel = beacon.name ?? beacon.mac
        connectionState = .Connected
    }

    func disconnect() {

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "disconnect_requested"
        )

        connectionState = .Disconnected
        connectedDeviceLabel = nil
        packetCount = 0
        receivedPackets.removeAll()
    }

    // MARK: - Password

    func dismissPasswordPrompt() {

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "password_prompt_cancelled_by_user"
        )

        authFailedBeacon = nil
    }

    func retryConnectWithPassword(_ password: String) {

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "password_retry_by_user"
        )

        authFailedBeacon = nil
    }
    
    func logAppOpened() {

        bleLogger.log(
            correlationId: UUID().uuidString,
            stage: "test",
            event: "app_opened"
        )
    }

    // MARK: - SDK-driven events (ground truth, wired from BeaconManager's delegate callbacks)

    // Ground truth for these reason codes pulled from the SDK's own KBeacon.swift
    // (KBConnEvtReason enum), matching the Android side's connectionReasonText.
    private func connectionReasonText(_ reason: KBConnEvtReason) -> String {
        switch reason {
        case .ConnNull: return "No reason"
        case .ConnSuccess: return "Success"
        case .ConnTimeout: return "Timed out - device did not respond in time"
        case .ConnException: return "Connection exception (BLE stack error)"
        case .ConnServiceNotSupport: return "App could not identify/support this device"
        case .ConnManualDisconnting: return "Manually disconnected"
        case .ConnAuthFail: return "Wrong password"
        @unknown default: return "Unrecognized reason"
        }
    }

    func logScanFailed(reason: String) {
        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "scan_failed",
            extra: ["reason": reason]
        )
    }

    func logBeaconsDiscovered(count: Int) {
        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "beacons_discovered",
            extra: ["count": "\(count)"]
        )
    }

    func logAdvDataChanged(mac: String, rssi: Int, advData: [KeyValue]) {
        var extra = Dictionary(uniqueKeysWithValues: advData.map { ($0.key, $0.value) })
        extra["rssi"] = "\(rssi)"

        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "advertisement",
            event: "adv_data_changed",
            deviceMac: mac,
            extra: extra
        )
    }

    func logCentralBleStateChanged(state: String) {
        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "central_ble_state_changed",
            extra: ["state": state]
        )
    }

    func logConnectRejected(mac: String) {
        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "connect_rejected_by_sdk",
            deviceMac: mac,
            extra: ["reason": "SDK rejected connect() immediately - device may still be finishing a previous disconnect"]
        )
    }

    // Mirrors the Android ViewModel's onConnStateChange: always logs the raw state
    // transition, then the specific success/failure verdict event.
    func logConnStateChanged(mac: String, state: KBConnState, reason: KBConnEvtReason) {

        let reasonText = connectionReasonText(reason)

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "state_changed:\(state)",
            reasonCode: reason.rawValue,
            deviceMac: mac,
            extra: ["reason": reasonText]
        )

        switch state {

        case .Connected:
            bleLogger.log(
                correlationId: connectCorrelationId,
                stage: "connect",
                event: "connection_succeeded",
                deviceMac: mac
            )

        case .Disconnected:
            let verdictEvent = reason == .ConnManualDisconnting ? "disconnected_by_request" : "connection_failed"

            bleLogger.log(
                correlationId: connectCorrelationId,
                stage: "connect",
                event: verdictEvent,
                reasonCode: reason.rawValue,
                deviceMac: mac,
                extra: ["reason": reasonText]
            )

        default:
            break
        }
    }
}
