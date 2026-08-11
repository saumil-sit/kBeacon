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

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "connection_succeeded",
            deviceMac: beacon.mac
        )
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

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "disconnected_by_request"
        )
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
}
