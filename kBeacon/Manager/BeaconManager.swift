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

    @Published var connectedBeacon: KBeacon?



    // Password prompt

    @Published var authFailedBeacon: KBeacon?

    // Packet history

    @Published var packetCount = 0

    @Published var receivedPackets: [ReceivedPacketEntry] = []

    @Published var advDataByMac: [String: [KeyValue]] = [:]

    private let bleLogger: BleLogger

    // MARK: - Callbacks for logging

    var onScanResult: ((Bool) -> Void)?

    var onDeviceDiscovered: ((BeaconDeviceModel) -> Void)?

    var onConnectionStateChanged: ((KBeacon, KBConnState, KBConnEvtReason) -> Void)?

    var onBeaconsDiscoveredBatch: ((Int) -> Void)?

    var onAdvDataChanged: ((_ mac: String, _ rssi: Int, _ advData: [KeyValue]) -> Void)?

    var onBluetoothStateChanged: ((String) -> Void)?

    var onConnectRejected: ((KBeacon) -> Void)?

    // Fires immediately after beacon.connect() returns, for BOTH outcomes (not just

    // rejection) - lets us see in Supabase, without any device/console access, whether the

    // SDK actually accepted the call at all. Complements onConnectRejected rather than

    // replacing it.

    var onConnectApiResult: ((KBeacon, Bool) -> Void)?

    var onCommonCfgUnavailable: ((_ mac: String) -> Void)?

    var onDeviceCapabilities: ((_ mac: String, _ capabilities: [String: Bool], _ model: String?, _ version: String?) -> Void)?

    var onTriggerConfigRead: ((_ mac: String, _ triggerType: Int, _ triggerAction: Int) -> Void)?

    var onTriggerNotConfigured: ((_ mac: String, _ triggerType: Int) -> Void)?

    var onTriggerConfigureSkipped: ((_ mac: String, _ reason: String) -> Void)?

    var onTriggerConfigureRequested: ((_ mac: String, _ triggerType: Int, _ triggerPara: Int?) -> Void)?

    var onTriggerConfigureResult: ((_ mac: String, _ triggerType: Int, _ success: Bool, _ error: String?) -> Void)?

    var onSubscribeResult: ((_ mac: String, _ success: Bool, _ error: String?, _ elapsedMs: Int?) -> Void)?

    var onPacketReceivedLogged: ((_ mac: String, _ evt: Int, _ byteCount: Int, _ packetNumber: Int, _ rawHex: String, _ elapsedMs: Int?) -> Void)?

    var onNoDataTimeout: ((_ mac: String, _ elapsedMs: Int?) -> Void)?

    // The device should report a humidity/temperature reading on this interval once

    // subscribed - same value as the Android side's periodicReportIntervalSeconds.

    private let periodicReportIntervalSeconds = 15

    private let noDataTimeoutSeconds: UInt64 = 30

    private var connectedAt: Date?

    private var noDataWatchdogToken = 0

    private var lastSeenAt: [String: Date] = [:]

    private let staleDeviceTimeoutSeconds: TimeInterval = 15

    // BLE logging correlation IDs.
    private var managerCorrelationId = UUID().uuidString
    private var scanCorrelationId = UUID().uuidString
    private var connectCorrelationId = UUID().uuidString

    // KKM's own factory-default connection password - matches Android's defaultPassword

    // constant. Exposed so BeaconViewModel can log usingDefaultPassword/passwordLength

    // without duplicating this literal.

    static let defaultPassword = "0000000000000000"

    // MARK: - Init

    init(bleLogger: BleLogger) {
        self.bleLogger = bleLogger
        super.init()

        print("BeaconManager init called")

        bleLogger.log(
            correlationId: managerCorrelationId,
            stage: "manager",
            event: "manager_initialized"
        )

        KBeaconsMgr.sharedBeaconManager.delegate = self

        print("KBeacon delegate assigned")

        bleLogger.log(
            correlationId: managerCorrelationId,
            stage: "manager",
            event: "kbeacon_delegate_assigned"
        )

        bleLogger.flushNow()
    }

    // MARK: - Scan

    func startScan() {
        print("Start scan button tapped")

        scanCorrelationId = UUID().uuidString

        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "scan_requested_by_user"
        )

        devices.removeAll()
        lastSeenAt.removeAll()
        advDataByMac.removeAll()

        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "scan_state_reset",
            extra: [
                "deviceCount": "0",
                "advDataCacheCleared": "true"
            ]
        )

        let started = KBeaconsMgr.sharedBeaconManager.startScanning()
        print("KBeacon scan started: \(started)")
        isScanning = started

        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: started ? "sdk_scan_started" : "sdk_scan_start_failed",
            extra: [
                "acceptedBySdk": "\(started)",
                "bluetoothState": bluetoothState
            ]
        )

        onScanResult?(started)

        if !started {
            bleLogger.flushNow()
        }
    }

    func stopScan() {
        print("Stop scan button tapped")

        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "scan_stop_requested",
            extra: [
                "deviceCount": "\(devices.count)",
                "isScanning": "\(isScanning)"
            ]
        )

        KBeaconsMgr.sharedBeaconManager.stopScanning()
        isScanning = false

        bleLogger.log(
            correlationId: scanCorrelationId,
            stage: "scan",
            event: "sdk_scan_stopped"
        )

        bleLogger.flushNow()
    }

    // MARK: - Connect

    func connect(_ beacon: KBeacon) {
        connectCorrelationId = UUID().uuidString

        let mac = beacon.mac ?? "Unknown"
        let name = beacon.name ?? "Unknown"

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "connect_requested",
            deviceMac: mac,
            extra: [
                "name": name,
                "usingDefaultPassword": "true",
                "passwordLength": "\(BeaconManager.defaultPassword.count)",
                "timeoutSeconds": "20"
            ]
        )

        connectionState = .Connecting
        connectedDeviceLabel = name
        connectedBeacon = beacon

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "local_connection_state_set",
            deviceMac: mac,
            extra: ["state": "Connecting"]
        )

        let accepted = beacon.connect(
            BeaconManager.defaultPassword,
            timeout: 20.0,
            delegate: self
        )

        print("Connect API accepted: \(accepted)")

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "connect_api_result",
            deviceMac: mac,
            extra: ["accepted": "\(accepted)"]
        )

        onConnectApiResult?(beacon, accepted)

        if !accepted {
            bleLogger.log(
                correlationId: connectCorrelationId,
                stage: "connect",
                event: "connect_rejected_by_sdk",
                deviceMac: mac,
                extra: ["reason": "SDK returned false immediately"]
            )

            connectionState = .Disconnected
            connectedDeviceLabel = nil
            connectedBeacon = nil
            onConnectRejected?(beacon)
            bleLogger.flushNow()
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        print("Disconnect tapped")

        let mac = connectedBeacon?.mac ?? "Unknown"

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "disconnect_requested",
            deviceMac: mac
        )

        noDataWatchdogToken += 1
        connectedAt = nil
        connectedBeacon?.disconnect()
        connectedBeacon = nil
        KBeaconsMgr.sharedBeaconManager.stopScanning()
        connectionState = .Disconnected
        connectedDeviceLabel = nil
        packetCount = 0
        receivedPackets.removeAll()

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "disconnect_local_cleanup",
            deviceMac: mac
        )
        bleLogger.flushNow()
    }

    // MARK: - Password prompt helpers

    func dismissPasswordPrompt() {
        let mac = authFailedBeacon?.mac ?? "Unknown"
        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "password_prompt_cancelled_by_user",
            deviceMac: mac
        )
        authFailedBeacon = nil
    }

    func retryConnectWithPassword(_ password: String) {
        guard let beacon = authFailedBeacon else {
            bleLogger.log(
                correlationId: connectCorrelationId,
                stage: "connect",
                event: "password_retry_ignored",
                extra: ["reason": "No authentication-failed beacon is available"]
            )
            return
        }

        connectCorrelationId = UUID().uuidString
        let mac = beacon.mac ?? "Unknown"
        let name = beacon.name ?? "Unknown"

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "password_retry_by_user",
            deviceMac: mac,
            extra: [
                "name": name,
                "usingDefaultPassword": "\(password == BeaconManager.defaultPassword)",
                "passwordLength": "\(password.count)",
                "timeoutSeconds": "20"
            ]
        )

        authFailedBeacon = nil
        connectionState = .Connecting
        connectedDeviceLabel = name
        connectedBeacon = beacon

        let accepted = beacon.connect(password, timeout: 20.0, delegate: self)

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "password_retry_api_result",
            deviceMac: mac,
            extra: ["accepted": "\(accepted)"]
        )

        onConnectApiResult?(beacon, accepted)

        if !accepted {
            bleLogger.log(
                correlationId: connectCorrelationId,
                stage: "connect",
                event: "password_retry_rejected_by_sdk",
                deviceMac: mac
            )
            connectionState = .Disconnected
            connectedDeviceLabel = nil
            connectedBeacon = nil
            onConnectRejected?(beacon)
            bleLogger.flushNow()
        }
    }

    func disconnectCurrent() {
        let mac = connectedBeacon?.mac ?? "Unknown"

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "disconnect_current_requested",
            deviceMac: mac
        )

        noDataWatchdogToken += 1
        connectedAt = nil
        connectedBeacon?.disconnect()
        connectedBeacon = nil
        connectionState = .Disconnected
        connectedDeviceLabel = nil

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "connect",
            event: "disconnect_current_local_cleanup",
            deviceMac: mac
        )
        bleLogger.flushNow()
    }

    // MARK: - Diagnostics, trigger configuration, and live-data subscription
    // MARK: - Diagnostics, trigger configuration, and live-data subscription

    // Mirrors the Android ViewModel's logDeviceDiagnostics/configureAvailableTriggers/

    // subscribeSensorDataNotify flow, run once per successful connection.

    private func elapsedMsSinceConnected() -> Int? {

        guard let connectedAt else { return nil }

        return Int(Date().timeIntervalSince(connectedAt) * 1000)

    }

    private func logDeviceDiagnostics(_ beacon: KBeacon) {
        let mac = beacon.mac ?? "Unknown"

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "diagnostics",
            event: "common_cfg_requested",
            deviceMac: mac
        )

        guard let commonCfg = beacon.getCommonCfg() else {
            bleLogger.log(
                correlationId: connectCorrelationId,
                stage: "diagnostics",
                event: "common_cfg_null",
                deviceMac: mac
            )
            onCommonCfgUnavailable?(mac)
            return
        }

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "diagnostics",
            event: "common_cfg_read",
            deviceMac: mac,
            extra: [
                "model": commonCfg.getModel() ?? "unknown",
                "version": commonCfg.getVersion() ?? "unknown"
            ]
        )

        let capabilities: [String: Bool] = [
            "humidity": commonCfg.isSupportHumiditySensor(),
            "co2": commonCfg.isSupportCO2Sensor(),
            "light": commonCfg.isSupportLightSensor(),
            "pir": commonCfg.isSupportPIRSensor(),
            "acc": commonCfg.isSupportAccSensor(),
            "geo": commonCfg.isSupportGEOSensor(),
            "button": commonCfg.isSupportButton()
        ]

        var capabilityExtra = capabilities.mapValues { $0 ? "true" : "false" }
        capabilityExtra["model"] = commonCfg.getModel() ?? "unknown"
        capabilityExtra["version"] = commonCfg.getVersion() ?? "unknown"

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "diagnostics",
            event: "device_capabilities",
            deviceMac: mac,
            extra: capabilityExtra
        )

        onDeviceCapabilities?(mac, capabilities, commonCfg.getModel(), commonCfg.getVersion())

        var triggersToCheck: [Int] = []
        if commonCfg.isSupportHumiditySensor() { triggersToCheck.append(KBTriggerType.HTHumidityPeriodically) }
        if commonCfg.isSupportPIRSensor() { triggersToCheck.append(KBTriggerType.PIRBodyInfraredDetected) }
        if commonCfg.isSupportLightSensor() { triggersToCheck.append(KBTriggerType.LightLUXAbove) }
        if commonCfg.isSupportAccSensor() { triggersToCheck.append(KBTriggerType.AccMotion) }
        if commonCfg.isSupportButton() { triggersToCheck.append(KBTriggerType.BtnSingleClick) }

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "diagnostics",
            event: "trigger_diagnostics_started",
            deviceMac: mac,
            extra: ["triggerCount": "\(triggersToCheck.count)"]
        )

        for triggerType in triggersToCheck {
            if let cfg = beacon.getTriggerCfg(triggerType) {
                let action = cfg.getTriggerAction()
                bleLogger.log(
                    correlationId: connectCorrelationId,
                    stage: "diagnostics",
                    event: "trigger_config_read",
                    deviceMac: mac,
                    extra: [
                        "triggerType": "\(triggerType)",
                        "triggerAction": "\(action)"
                    ]
                )
                onTriggerConfigRead?(mac, triggerType, action)
            } else {
                bleLogger.log(
                    correlationId: connectCorrelationId,
                    stage: "diagnostics",
                    event: "trigger_not_configured",
                    deviceMac: mac,
                    extra: ["triggerType": "\(triggerType)"]
                )
                onTriggerNotConfigured?(mac, triggerType)
            }
        }
    }

    // Writes a Report2App trigger    // Writes a Report2App trigger for every sensor this device actually reports having,

    // so whatever sensors exist on the connected beacon all report to the app.

    private func configureAvailableTriggers(_ beacon: KBeacon, onComplete: @escaping () -> Void) {
        let mac = beacon.mac ?? "Unknown"

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "configure",
            event: "trigger_configuration_started",
            deviceMac: mac
        )

        guard let commonCfg = beacon.getCommonCfg() else {
            bleLogger.log(
                correlationId: connectCorrelationId,
                stage: "configure",
                event: "trigger_configure_skipped",
                deviceMac: mac,
                extra: ["reason": "commonCfg null"]
            )
            onTriggerConfigureSkipped?(mac, "commonCfg null")
            onComplete()
            return
        }

        var triggersToWrite: [KBCfgTrigger] = []

        if commonCfg.isSupportHumiditySensor() {
            let trigger = KBCfgTrigger(0, triggerType: KBTriggerType.HTHumidityPeriodically)
            trigger.setTriggerAction(KBTriggerAction.ReportToApp)
            trigger.setTriggerPara(periodicReportIntervalSeconds)
            triggersToWrite.append(trigger)
        }

        if commonCfg.isSupportAccSensor() {
            let trigger = KBCfgTrigger(0, triggerType: KBTriggerType.AccMotion)
            trigger.setTriggerAction(KBTriggerAction.ReportToApp)
            trigger.setTriggerPara(KBCfgTrigger.DEFAULT_MOTION_SENSITIVITY)
            triggersToWrite.append(trigger)
        }

        if commonCfg.isSupportButton() {
            let trigger = KBCfgTrigger(0, triggerType: KBTriggerType.BtnSingleClick)
            trigger.setTriggerAction(KBTriggerAction.ReportToApp)
            triggersToWrite.append(trigger)
        }

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "configure",
            event: "trigger_configuration_plan_ready",
            deviceMac: mac,
            extra: ["triggerCount": "\(triggersToWrite.count)"]
        )

        guard !triggersToWrite.isEmpty else {
            bleLogger.log(
                correlationId: connectCorrelationId,
                stage: "configure",
                event: "trigger_configure_skipped",
                deviceMac: mac,
                extra: ["reason": "no configurable sensors reported by device"]
            )
            onTriggerConfigureSkipped?(mac, "no configurable sensors reported by device")
            onComplete()
            return
        }

        writeNextTrigger(beacon, remaining: triggersToWrite, onComplete: onComplete)
    }

    private func writeNextTrigger(_ beacon: KBeacon, remaining: [KBCfgTrigger], onComplete: @escaping () -> Void) {
        guard let trigger = remaining.first else {
            let mac = beacon.mac ?? "Unknown"
            bleLogger.log(
                correlationId: connectCorrelationId,
                stage: "configure",
                event: "trigger_configuration_completed",
                deviceMac: mac
            )
            onComplete()
            return
        }

        let rest = Array(remaining.dropFirst())
        let mac = beacon.mac ?? "Unknown"
        let triggerType = trigger.getTriggerType()
        let triggerPara = trigger.getTriggerPara()
        let normalizedPara = triggerPara == KBCfgBase.INVALID_INT ? nil : triggerPara

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "configure",
            event: "trigger_configure_requested",
            deviceMac: mac,
            extra: [
                "triggerType": "\(triggerType)",
                "triggerPara": normalizedPara.map { "\($0)" } ?? ""
            ]
        )

        onTriggerConfigureRequested?(mac, triggerType, normalizedPara)

        beacon.modifyConfig(obj: trigger) { success, error in
            Task { @MainActor in
                let errorText = error?.errorDescription ?? ""

                self.bleLogger.log(
                    correlationId: self.connectCorrelationId,
                    stage: "configure",
                    event: success ? "trigger_configure_succeeded" : "trigger_configure_failed",
                    deviceMac: mac,
                    extra: [
                        "triggerType": "\(triggerType)",
                        "success": "\(success)",
                        "error": errorText
                    ]
                )

                self.onTriggerConfigureResult?(mac, triggerType, success, errorText)
                self.writeNextTrigger(beacon, remaining: rest, onComplete: onComplete)
            }
        }
    }

    private func subscribeToSensorData(_ beacon: KBeacon) {
        let mac = beacon.mac ?? "Unknown"

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "subscribe",
            event: "subscribe_requested",
            deviceMac: mac,
            extra: [
                "triggerType": "\(KBTriggerType.TriggerNull)",
                "elapsedMs": "\(elapsedMsSinceConnected() ?? -1)"
            ]
        )

        beacon.subscribeSensorDataNotify(KBTriggerType.TriggerNull, notifyDelegate: self) { success, error in
            Task { @MainActor in
                let elapsed = self.elapsedMsSinceConnected()
                let errorText = error?.errorDescription ?? ""

                self.bleLogger.log(
                    correlationId: self.connectCorrelationId,
                    stage: "subscribe",
                    event: success ? "subscribe_succeeded" : "subscribe_failed",
                    elapsedMs: elapsed,
                    deviceMac: mac,
                    extra: [
                        "success": "\(success)",
                        "error": errorText
                    ]
                )

                self.onSubscribeResult?(mac, success, errorText, elapsed)

                if success {
                    self.startNoDataWatchdog(mac: mac)
                }
            }
        }
    }

    // Makes "nothing arrived" an explicit logged fact instead of indefinite silence. Each

    // call gets a fresh token so an earlier watchdog (from a previous connection) can't fire

    // late and report against the wrong attempt.

    private func startNoDataWatchdog(mac: String) {
        noDataWatchdogToken += 1
        let myToken = noDataWatchdogToken

        bleLogger.log(
            correlationId: connectCorrelationId,
            stage: "data",
            event: "no_data_watchdog_started",
            deviceMac: mac,
            extra: [
                "timeoutSeconds": "\(noDataTimeoutSeconds)",
                "packetCount": "\(packetCount)"
            ]
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: noDataTimeoutSeconds * 1_000_000_000)

            guard myToken == self.noDataWatchdogToken else {
                self.bleLogger.log(
                    correlationId: self.connectCorrelationId,
                    stage: "data",
                    event: "no_data_watchdog_cancelled",
                    deviceMac: mac,
                    extra: ["reason": "Connection/watchdog token changed"]
                )
                return
            }

            if self.packetCount == 0 {
                let elapsed = self.elapsedMsSinceConnected()

                self.bleLogger.log(
                    correlationId: self.connectCorrelationId,
                    stage: "data",
                    event: "no_data_timeout",
                    elapsedMs: elapsed,
                    deviceMac: mac,
                    extra: [
                        "packetCount": "0",
                        "timeoutSeconds": "\(self.noDataTimeoutSeconds)",
                        "reason": "No notification packet received after successful subscription"
                    ]
                )

                self.onNoDataTimeout?(mac, elapsed)
                self.bleLogger.flushNow()
            } else {
                self.bleLogger.log(
                    correlationId: self.connectCorrelationId,
                    stage: "data",
                    event: "no_data_watchdog_satisfied",
                    deviceMac: mac,
                    extra: ["packetCount": "\(self.packetCount)"]
                )
            }
        }
    }

    // Minimal implementation to satisfy compile-time needs.
    // This can be extended to parse beacon.allAdvPackets if desired.
    private func parseAdvData(_ beacon: KBeacon) -> [KeyValue] {
        let macKV = KeyValue(key: "mac", value: beacon.mac ?? "Unknown")
        let nameKV = KeyValue(key: "name", value: beacon.name ?? "Unknown")
        let uuidKV = KeyValue(key: "uuid", value: beacon.uuidString ?? "N/A")
        let rssiKV = KeyValue(key: "rssi", value: String(Int(beacon.rssi)))
        return [macKV, nameKV, uuidKV, rssiKV]
    }
}

// MARK: - Scan delegate

extension BeaconManager: KBeaconMgrDelegate {

    nonisolated func onBeaconDiscovered(beacons: [KBeacon]) {
        Task { @MainActor in
            let now = Date()
            let previousAdvDataByMac = self.advDataByMac

            bleLogger.log(
                correlationId: scanCorrelationId,
                stage: "scan",
                event: "beacon_discovery_callback",
                extra: ["batchCount": "\(beacons.count)"]
            )

            var byMac = Dictionary(
                self.devices.map { ($0.mac, $0) },
                uniquingKeysWith: { _, new in new }
            )
            var freshlyReported: [BeaconDeviceModel] = []

            for beacon in beacons {
                let mac = beacon.mac ?? "Unknown"
                let name = beacon.name ?? "Unknown"
                let rssi = Int(beacon.rssi)

                bleLogger.log(
                    correlationId: scanCorrelationId,
                    stage: "advertisement",
                    event: "adv_data_parse_requested",
                    deviceMac: mac,
                    extra: [
                        "name": name,
                        "rssi": "\(rssi)",
                        "hasAdvPackets": "\(beacon.allAdvPackets != nil)"
                    ]
                )

                let advData = self.parseAdvData(beacon)
                let advDataLog = advData
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")

                if beacon.allAdvPackets == nil {
                    bleLogger.log(
                        correlationId: scanCorrelationId,
                        stage: "advertisement",
                        event: "adv_data_unavailable",
                        deviceMac: mac,
                        extra: [
                            "reason": "allAdvPackets is nil",
                            "advDataCount": "0"
                        ]
                    )
                } else {
                    bleLogger.log(
                        correlationId: scanCorrelationId,
                        stage: "advertisement",
                        event: "adv_data_parsed",
                        deviceMac: mac,
                        extra: [
                            "advDataCount": "\(advData.count)",
                            "advData": advDataLog
                        ]
                    )
                }

                let device = BeaconDeviceModel(
                    beacon: beacon,
                    name: name,
                    mac: mac,
                    uuid: beacon.uuidString ?? "N/A",
                    rssi: rssi,
                    advData: advData
                )

                bleLogger.log(
                    correlationId: scanCorrelationId,
                    stage: "scan",
                    event: "beacon_discovered",
                    deviceMac: mac,
                    extra: [
                        "name": name,
                        "rssi": "\(rssi)",
                        "uuid": beacon.uuidString ?? "N/A",
                        "advDataCount": "\(advData.count)",
                        "advData": advDataLog
                    ]
                )

                bleLogger.log(
                    correlationId: scanCorrelationId,
                    stage: "advertisement",
                    event: "adv_data_received",
                    deviceMac: mac,
                    extra: [
                        "rssi": "\(rssi)",
                        "advDataCount": "\(advData.count)",
                        "advData": advDataLog
                    ]
                )

                byMac[mac] = device
                self.lastSeenAt[mac] = now
                freshlyReported.append(device)

                let previous = previousAdvDataByMac[mac] ?? []

                if advData.isEmpty {
                    bleLogger.log(
                        correlationId: scanCorrelationId,
                        stage: "advertisement",
                        event: "adv_data_empty",
                        deviceMac: mac,
                        extra: ["previousCount": "\(previous.count)"]
                    )
                } else if previous.isEmpty {
                    bleLogger.log(
                        correlationId: scanCorrelationId,
                        stage: "advertisement",
                        event: "adv_data_first_seen",
                        deviceMac: mac,
                        extra: ["current": advDataLog]
                    )
                } else if self.advDataEqual(previous, advData) {
                    bleLogger.log(
                        correlationId: scanCorrelationId,
                        stage: "advertisement",
                        event: "adv_data_unchanged",
                        deviceMac: mac,
                        extra: ["current": advDataLog]
                    )
                } else {
                    let previousLog = previous
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: ", ")

                    bleLogger.log(
                        correlationId: scanCorrelationId,
                        stage: "advertisement",
                        event: "adv_data_changed",
                        deviceMac: mac,
                        extra: [
                            "previous": previousLog,
                            "current": advDataLog,
                            "rssi": "\(rssi)"
                        ]
                    )

                    onAdvDataChanged?(mac, rssi, advData)
                }
            }

            let beforeFilterCount = byMac.count

            byMac = byMac.filter { mac, _ in
                guard let lastSeen = self.lastSeenAt[mac] else {
                    bleLogger.log(
                        correlationId: scanCorrelationId,
                        stage: "scan",
                        event: "device_removed_no_last_seen",
                        deviceMac: mac
                    )
                    return false
                }

                let age = now.timeIntervalSince(lastSeen)
                let keep = age <= self.staleDeviceTimeoutSeconds

                if !keep {
                    bleLogger.log(
                        correlationId: scanCorrelationId,
                        stage: "scan",
                        event: "device_stale_removed",
                        deviceMac: mac,
                        extra: [
                            "ageSeconds": String(format: "%.2f", age),
                            "timeoutSeconds": "\(self.staleDeviceTimeoutSeconds)"
                        ]
                    )
                }
                return keep
            }

            let mapped = byMac.values.sorted { $0.rssi > $1.rssi }
            self.devices = mapped
            self.advDataByMac = Dictionary(
                mapped.map { ($0.mac, $0.advData) },
                uniquingKeysWith: { _, new in new }
            )

            print("Discovered devices count: \(mapped.count)")

            bleLogger.log(
                correlationId: scanCorrelationId,
                stage: "scan",
                event: "device_list_updated",
                extra: [
                    "previousCount": "\(beforeFilterCount)",
                    "currentCount": "\(mapped.count)"
                ]
            )

            onBeaconsDiscoveredBatch?(mapped.count)

            for device in freshlyReported {
                bleLogger.log(
                    correlationId: scanCorrelationId,
                    stage: "scan",
                    event: "device_discovered_callback",
                    deviceMac: device.mac,
                    extra: [
                        "name": device.name,
                        "rssi": "\(device.rssi)",
                        "advDataCount": "\(device.advData.count)"
                    ]
                )
                onDeviceDiscovered?(device)
            }
        }
    }

    private func advDataEqual(_ lhs: [KeyValue], _ rhs: [KeyValue]) -> Bool {

        guard lhs.count == rhs.count else { return false }

        return zip(lhs, rhs).allSatisfy { $0.key == $1.key && $0.value == $1.value }

    }

    nonisolated func onCentralBleStateChange(newState: BLECentralMgrState) {
        Task { @MainActor in
            switch newState {
            case .PowerOn:
                bluetoothState = "Powered On"
            case .PowerOff:
                bluetoothState = "Powered Off"
                isScanning = false
            case .Unauthorized:
                bluetoothState = "Unauthorized"
                isScanning = false
            case .Unknown:
                bluetoothState = "Unknown"
                isScanning = false
            @unknown default:
                bluetoothState = "Unknown"
                isScanning = false
            }

            print("KBeacon Bluetooth state: \(bluetoothState)")

            bleLogger.log(
                correlationId: scanCorrelationId,
                stage: "bluetooth",
                event: "central_ble_state_changed",
                extra: [
                    "state": bluetoothState,
                    "isScanning": "\(isScanning)"
                ]
            )

            onBluetoothStateChanged?(bluetoothState)

            if bluetoothState != "Powered On" {
                bleLogger.flushNow()
            }
        }
    }
}// MARK: - Connection delegate

extension BeaconManager: ConnStateDelegate {

    nonisolated func onConnStateChange(
        _ beacon: KBeacon,
        state: KBConnState,
        evt: KBConnEvtReason
    ) {
        Task { @MainActor in
            let mac = beacon.mac ?? "Unknown"
            let reasonText = self.connectionReasonText(evt)
            let elapsed = self.elapsedMsSinceConnected()

            print("Connection state changed: \(state) reason: \(evt)")

            self.bleLogger.log(
                correlationId: self.connectCorrelationId,
                stage: "connect",
                event: "state_changed",
                reasonCode: evt.rawValue,
                elapsedMs: elapsed,
                deviceMac: mac,
                extra: [
                    "state": "\(state)",
                    "reason": reasonText
                ]
            )

            self.connectionState = state

            switch state {
            case .Connected:
                self.connectedDeviceLabel = beacon.name ?? beacon.mac ?? "Unknown"
                self.connectedBeacon = beacon
                self.packetCount = 0
                self.connectedAt = Date()

                self.bleLogger.log(
                    correlationId: self.connectCorrelationId,
                    stage: "connect",
                    event: "connection_succeeded",
                    reasonCode: evt.rawValue,
                    deviceMac: mac,
                    extra: ["reason": reasonText]
                )

                self.logDeviceDiagnostics(beacon)
                self.configureAvailableTriggers(beacon) {
                    self.subscribeToSensorData(beacon)
                }

            case .Disconnected:
                let event = evt == .ConnManualDisconnting ? "disconnected_by_request" : "connection_failed"

                self.bleLogger.log(
                    correlationId: self.connectCorrelationId,
                    stage: "connect",
                    event: event,
                    reasonCode: evt.rawValue,
                    elapsedMs: elapsed,
                    deviceMac: mac,
                    extra: ["reason": reasonText]
                )

                self.connectedDeviceLabel = nil
                self.connectedBeacon = nil
                self.connectedAt = nil
                self.noDataWatchdogToken += 1

                if evt == .ConnAuthFail {
                    self.authFailedBeacon = beacon
                    self.bleLogger.log(
                        correlationId: self.connectCorrelationId,
                        stage: "connect",
                        event: "authentication_failed",
                        reasonCode: evt.rawValue,
                        deviceMac: mac,
                        extra: ["reason": reasonText]
                    )
                }

                self.bleLogger.flushNow()

            default:
                break
            }

            self.onConnectionStateChanged?(beacon, state, evt)
        }
    }

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
            let elapsed = self.elapsedMsSinceConnected()
            let mac = beacon.mac ?? "Unknown"

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

            print("Packet received count: \(self.packetCount)")

            self.bleLogger.log(
                correlationId: self.connectCorrelationId,
                stage: "data",
                event: "packet_received",
                elapsedMs: elapsed,
                deviceMac: mac,
                extra: [
                    "eventType": "\(evt)",
                    "byteCount": "\(data.count)",
                    "packetNumber": "\(self.packetCount)",
                    "rawHex": hex
                ]
            )

            self.bleLogger.log(
                correlationId: self.connectCorrelationId,
                stage: "data",
                event: "sensor_data_received",
                elapsedMs: elapsed,
                deviceMac: mac,
                extra: [
                    "eventType": "\(evt)",
                    "byteCount": "\(data.count)",
                    "packetNumber": "\(self.packetCount)"
                ]
            )

            self.onPacketReceivedLogged?(
                mac,
                evt,
                data.count,
                self.packetCount,
                hex,
                elapsed
            )

            // A packet arrived, so cancel the pending no-data timeout for this connection.
            self.noDataWatchdogToken += 1

            self.bleLogger.log(
                correlationId: self.connectCorrelationId,
                stage: "data",
                event: "no_data_watchdog_satisfied",
                elapsedMs: elapsed,
                deviceMac: mac,
                extra: ["packetCount": "\(self.packetCount)"]
            )
        }
    }
}
