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

    // MARK: - Callbacks for logging

    var onScanResult: ((Bool) -> Void)?
    var onDeviceDiscovered: ((BeaconDeviceModel) -> Void)?
    var onConnectionStateChanged: ((KBeacon, KBConnState, KBConnEvtReason) -> Void)?
    var onBeaconsDiscoveredBatch: ((Int) -> Void)?
    var onAdvDataChanged: ((_ mac: String, _ rssi: Int, _ advData: [KeyValue]) -> Void)?
    var onBluetoothStateChanged: ((String) -> Void)?
    var onConnectRejected: ((KBeacon) -> Void)?
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

    // KKM's own factory-default connection password - matches Android's defaultPassword
    // constant. Exposed so BeaconViewModel can log usingDefaultPassword/passwordLength
    // without duplicating this literal.
    static let defaultPassword = "0000000000000000"

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
        lastSeenAt.removeAll()

        let started = KBeaconsMgr.sharedBeaconManager.startScanning()

        print("KBeacon scan started: \(started)")

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
        connectedBeacon = beacon

        let accepted = beacon.connect(
            BeaconManager.defaultPassword,
            timeout: 20.0,
            delegate: self
        )

        print("Connect API accepted: \(accepted)")

        if !accepted {

            connectionState = .Disconnected
            connectedDeviceLabel = nil
            connectedBeacon = nil
            onConnectRejected?(beacon)
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        print("Disconnect tapped")
        noDataWatchdogToken += 1
        connectedAt = nil
        connectedBeacon?.disconnect()
        connectedBeacon = nil
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
        connectedBeacon = beacon

        let accepted = beacon.connect(
            password,
            timeout: 20.0,
            delegate: self
        )

        print("Retry connect accepted: \(accepted)")

        if !accepted {

            connectionState = .Disconnected
            connectedDeviceLabel = nil
            connectedBeacon = nil
            onConnectRejected?(beacon)
        }
    }

    func disconnectCurrent() {

        print("Disconnect current device")

        noDataWatchdogToken += 1
        connectedAt = nil
        connectedBeacon?.disconnect()
        connectedBeacon = nil

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

            switch packet {

            case let sensor as KBAdvPacketSensor:

                if sensor.batteryLevel != KBCfgBase.INVALID_UINT16 {
                    rows.append(KeyValue(key: "Battery", value: "\(sensor.batteryLevel) mV"))
                }

                if sensor.temperature != KBCfgBase.INVALID_FLOAT {
                    rows.append(KeyValue(key: "Temperature", value: String(format: "%.2f°C", sensor.temperature)))
                }

                if sensor.humidity != KBCfgBase.INVALID_FLOAT {
                    rows.append(KeyValue(key: "Humidity", value: String(format: "%.2f%%", sensor.humidity)))
                }

                if let acc = sensor.accSensor {
                    rows.append(KeyValue(key: "Accelerometer", value: "x:\(acc.xAis) y:\(acc.yAis) z:\(acc.zAis)"))
                }

                if sensor.pirIndication != KBCfgBase.INVALID_UINT8 {
                    rows.append(KeyValue(key: "PIR", value: "\(sensor.pirIndication)"))
                }

                if sensor.luxLevel != KBCfgBase.INVALID_UINT16 {
                    rows.append(KeyValue(key: "Light (lux)", value: "\(sensor.luxLevel)"))
                }

                // Best-effort match to Android's "Alarm" field - iOS's KBAdvPacketSensor has
                // no distinctly-named alarm property; `cutoff` is the closest equivalent
                // (same SENSOR_MASK_CUTOFF bit), not a confirmed 1:1 semantic match.
                if sensor.cutoff != KBCfgBase.INVALID_UINT8 {
                    rows.append(KeyValue(key: "Alarm", value: "\(sensor.cutoff)"))
                }

            case let tlm as KBAdvPacketEddyTLM:

                rows.append(KeyValue(key: "TLM Battery", value: "\(tlm.batteryLevel) mV"))
                rows.append(KeyValue(key: "TLM Temperature", value: String(format: "%.2f°C", tlm.temperature)))
                rows.append(KeyValue(key: "TLM Adv Count", value: "\(tlm.advCount)"))

            case let system as KBAdvPacketSystem:

                rows.append(KeyValue(key: "Model", value: "\(system.model)"))
                rows.append(KeyValue(key: "Firmware", value: system.firmwareVersion))
                rows.append(KeyValue(key: "Battery", value: "\(system.batteryPercent)%"))

            case let ibeacon as KBAdvPacketIBeacon:

                if ibeacon.majorID != KBCfgBase.INVALID_UINT {
                    rows.append(KeyValue(key: "Major", value: "\(ibeacon.majorID)"))
                }

                if ibeacon.minorID != KBCfgBase.INVALID_UINT {
                    rows.append(KeyValue(key: "Minor", value: "\(ibeacon.minorID)"))
                }

                if let uuid = ibeacon.uuid {
                    rows.append(KeyValue(key: "iBeacon UUID", value: uuid))
                }

            case let uid as KBAdvPacketEddyUID:

                if let nid = uid.nid {
                    rows.append(KeyValue(key: "Eddystone NID", value: nid))
                }

                if let sid = uid.sid {
                    rows.append(KeyValue(key: "Eddystone SID", value: sid))
                }

                if uid.refTxPower != KBCfgBase.INVALID_INT8 {
                    rows.append(KeyValue(key: "Eddystone Ref TX Power", value: "\(uid.refTxPower)"))
                }

            case let url as KBAdvPacketEddyURL:

                rows.append(KeyValue(key: "Eddystone URL", value: url.url))

                // KBAdvPacketEddyURL.refTxPower defaults to -24, not KBCfgBase.INVALID_INT8,
                // so there's no reliable "unset" sentinel to guard against here - it's always
                // populated from real data once parseAdvPacket succeeds (which is required for
                // this packet to appear in allAdvPackets at all), so log unconditionally.
                rows.append(KeyValue(key: "Eddystone URL Ref TX Power", value: "\(url.refTxPower)"))

            case let ebeacon as KBAdvPacketEBeacon:

                if let uuid = ebeacon.uuid {
                    rows.append(KeyValue(key: "Encrypted Beacon UUID", value: uuid))
                }

                rows.append(KeyValue(key: "Encrypted Beacon UTC", value: "\(ebeacon.utcSecCount)"))

                // Android's Kotlin model names this field "refTxPower"; iOS's KBAdvPacketEBeacon
                // names the same concept "measurePower" - no distinct "unset" sentinel exists
                // for it either, so logged unconditionally like EddyURL's refTxPower above.
                rows.append(KeyValue(key: "Encrypted Beacon Ref TX Power", value: "\(ebeacon.measurePower)"))

            default:

                // Matches Android's `else -> "Unrecognized adv packet type"` fallback - without
                // this, any packet type not explicitly handled above produced an empty row,
                // which meant onAdvDataChanged never fired at all for that device (it's gated
                // on `!advData.isEmpty`) - silently dropping it from Supabase logging entirely.
                rows.append(KeyValue(key: "Unrecognized adv packet type", value: "\(packet.getAdvType())"))
            }
        }

        return rows
    }

    // MARK: - Diagnostics, trigger configuration, and live-data subscription
    // Mirrors the Android ViewModel's logDeviceDiagnostics/configureAvailableTriggers/
    // subscribeSensorDataNotify flow, run once per successful connection.

    private func elapsedMsSinceConnected() -> Int? {
        guard let connectedAt else { return nil }
        return Int(Date().timeIntervalSince(connectedAt) * 1000)
    }

    private func logDeviceDiagnostics(_ beacon: KBeacon) {

        let mac = beacon.mac ?? "Unknown"

        guard let commonCfg = beacon.getCommonCfg() else {
            onCommonCfgUnavailable?(mac)
            return
        }

        let capabilities: [String: Bool] = [
            "humidity": commonCfg.isSupportHumiditySensor(),
            "co2": commonCfg.isSupportCO2Sensor(),
            "light": commonCfg.isSupportLightSensor(),
            "pir": commonCfg.isSupportPIRSensor(),
            "acc": commonCfg.isSupportAccSensor(),
            "geo": commonCfg.isSupportGEOSensor(),
            "button": commonCfg.isSupportButton()
        ]

        onDeviceCapabilities?(mac, capabilities, commonCfg.getModel(), commonCfg.getVersion())

        var triggersToCheck: [Int] = []
        if commonCfg.isSupportHumiditySensor() { triggersToCheck.append(KBTriggerType.HTHumidityPeriodically) }
        if commonCfg.isSupportPIRSensor() { triggersToCheck.append(KBTriggerType.PIRBodyInfraredDetected) }
        if commonCfg.isSupportLightSensor() { triggersToCheck.append(KBTriggerType.LightLUXAbove) }
        if commonCfg.isSupportAccSensor() { triggersToCheck.append(KBTriggerType.AccMotion) }
        if commonCfg.isSupportButton() { triggersToCheck.append(KBTriggerType.BtnSingleClick) }

        for triggerType in triggersToCheck {

            if let cfg = beacon.getTriggerCfg(triggerType) {
                onTriggerConfigRead?(mac, triggerType, cfg.getTriggerAction())
            } else {
                onTriggerNotConfigured?(mac, triggerType)
            }
        }
    }

    // Writes a Report2App trigger for every sensor this device actually reports having,
    // so whatever sensors exist on the connected beacon all report to the app.
    private func configureAvailableTriggers(_ beacon: KBeacon, onComplete: @escaping () -> Void) {

        let mac = beacon.mac ?? "Unknown"

        guard let commonCfg = beacon.getCommonCfg() else {
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

        guard !triggersToWrite.isEmpty else {
            onTriggerConfigureSkipped?(mac, "no configurable sensors reported by device")
            onComplete()
            return
        }

        writeNextTrigger(beacon, remaining: triggersToWrite, onComplete: onComplete)
    }

    private func writeNextTrigger(_ beacon: KBeacon, remaining: [KBCfgTrigger], onComplete: @escaping () -> Void) {

        guard let trigger = remaining.first else {
            onComplete()
            return
        }

        let rest = Array(remaining.dropFirst())
        let mac = beacon.mac ?? "Unknown"
        let triggerType = trigger.getTriggerType()
        let triggerPara = trigger.getTriggerPara()

        onTriggerConfigureRequested?(mac, triggerType, triggerPara == KBCfgBase.INVALID_INT ? nil : triggerPara)

        beacon.modifyConfig(obj: trigger) { success, error in
            Task { @MainActor in
                self.onTriggerConfigureResult?(mac, triggerType, success, error?.errorDescription)
                self.writeNextTrigger(beacon, remaining: rest, onComplete: onComplete)
            }
        }
    }

    private func subscribeToSensorData(_ beacon: KBeacon) {

        let mac = beacon.mac ?? "Unknown"

        beacon.subscribeSensorDataNotify(KBTriggerType.TriggerNull, notifyDelegate: self) { success, error in
            Task { @MainActor in
                self.onSubscribeResult?(mac, success, error?.errorDescription, self.elapsedMsSinceConnected())

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

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: noDataTimeoutSeconds * 1_000_000_000)

            guard myToken == self.noDataWatchdogToken else { return }

            if self.packetCount == 0 {
                self.onNoDataTimeout?(mac, self.elapsedMsSinceConnected())
            }
        }
    }
}

// MARK: - Scan delegate

extension BeaconManager: KBeaconMgrDelegate {

    nonisolated func onBeaconDiscovered(beacons: [KBeacon]) {

        Task { @MainActor in

            let now = Date()
            let previousAdvDataByMac = self.advDataByMac

            var byMac = Dictionary(uniqueKeysWithValues: self.devices.map { ($0.mac, $0) })
            var freshlyReported: [BeaconDeviceModel] = []

            for beacon in beacons {

                let device = BeaconDeviceModel(
                    beacon: beacon,
                    name: beacon.name ?? "Unknown",
                    mac: beacon.mac ?? "Unknown",
                    uuid: beacon.uuidString ?? "N/A",
                    rssi: Int(beacon.rssi),
                    advData: self.parseAdvData(beacon)
                )

                byMac[device.mac] = device
                self.lastSeenAt[device.mac] = now
                freshlyReported.append(device)
            }

            byMac = byMac.filter { mac, _ in
                guard let lastSeen = self.lastSeenAt[mac] else { return false }
                return now.timeIntervalSince(lastSeen) <= self.staleDeviceTimeoutSeconds
            }

            let mapped = byMac.values.sorted { $0.rssi > $1.rssi }

            self.devices = mapped

            // Store adv data by MAC
            self.advDataByMac = Dictionary(
                uniqueKeysWithValues: mapped.map { ($0.mac, $0.advData) }
            )

            print("Discovered devices count: \(mapped.count)")
            onBeaconsDiscoveredBatch?(mapped.count)

            for device in freshlyReported {

                if !device.advData.isEmpty {

                    let previous = previousAdvDataByMac[device.mac] ?? []

                    if !self.advDataEqual(previous, device.advData) {
                        onAdvDataChanged?(device.mac, device.rssi, device.advData)
                    }
                }

                onDeviceDiscovered?(device)
            }
        }
    }

    // KeyValue's synthesized Hashable includes its random `id`, so `==` on [KeyValue]
    // would never match across discovery passes even with identical key/value pairs.
    private func advDataEqual(_ lhs: [KeyValue], _ rhs: [KeyValue]) -> Bool {

        guard lhs.count == rhs.count else { return false }

        return zip(lhs, rhs).allSatisfy { $0.key == $1.key && $0.value == $1.value }
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

            onBluetoothStateChanged?(bluetoothState)
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

            print("Connection state changed: \(state) reason: \(evt)")

            self.connectionState = state

            if state == .Connected {

                self.connectedDeviceLabel = beacon.name ?? beacon.mac ?? "Unknown"
                self.packetCount = 0
                self.connectedAt = Date()

                self.logDeviceDiagnostics(beacon)

                self.configureAvailableTriggers(beacon) {
                    self.subscribeToSensorData(beacon)
                }
            }

            if state == .Disconnected {

                self.connectedDeviceLabel = nil
                self.connectedBeacon = nil
                self.connectedAt = nil
                self.noDataWatchdogToken += 1

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

            print("Packet received count: \(self.packetCount)")

            onPacketReceivedLogged?(
                beacon.mac ?? "Unknown",
                evt,
                data.count,
                self.packetCount,
                hex,
                self.elapsedMsSinceConnected()
            )
        }
    }
}
