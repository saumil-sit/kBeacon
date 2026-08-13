//
//  kBeaconApp.swift
//  kBeacon
//
//  Created by Saumil on 06/08/26.
//

import SwiftUI
import kbeaconlib2

@main
struct kBeaconApp: App {

    private let locationPermissionManager = LocationPermissionManager()

    @StateObject private var beaconManager = BeaconManager()
    @StateObject private var viewModel: BeaconViewModel
    private let bluetoothPermissionManager = BluetoothPermissionManager()

    init() {

        let client = SupabaseClient(
            baseURL: "https://eeqlwtpeqdtbenscaijt.supabase.co",
            apiKey: "sb_publishable_JNnsFdpBxEPX6NKM-fA8Rw_7TsA339L"
        )

        let logger = BleLogger(client: client)

        let viewModel = BeaconViewModel(bleLogger: logger)
        _viewModel = StateObject(wrappedValue: viewModel)

        beaconManager.onScanResult = { [weak beaconManager] started in
            guard !started, let beaconManager else { return }
            viewModel.logScanFailed(reason: beaconManager.bluetoothState)
        }

        beaconManager.onBeaconsDiscoveredBatch = { count in
            viewModel.logBeaconsDiscovered(count: count)
        }

        beaconManager.onAdvDataChanged = { mac, rssi, advData in
            viewModel.logAdvDataChanged(mac: mac, rssi: rssi, advData: advData)
        }

        beaconManager.onBluetoothStateChanged = { state in
            viewModel.logCentralBleStateChanged(state: state)
        }

        beaconManager.onConnectRejected = { beacon in
            viewModel.logConnectRejected(mac: beacon.mac ?? "Unknown")
        }

        beaconManager.onConnectionStateChanged = { beacon, state, reason in
            viewModel.logConnStateChanged(mac: beacon.mac ?? "Unknown", state: state, reason: reason)
        }

        beaconManager.onCommonCfgUnavailable = { mac in
            viewModel.logCommonCfgUnavailable(mac: mac)
        }

        beaconManager.onDeviceCapabilities = { mac, capabilities, model, version in
            viewModel.logDeviceCapabilities(mac: mac, capabilities: capabilities, model: model, version: version)
        }

        beaconManager.onTriggerConfigRead = { mac, triggerType, triggerAction in
            viewModel.logTriggerConfigRead(mac: mac, triggerType: triggerType, triggerAction: triggerAction)
        }

        beaconManager.onTriggerNotConfigured = { mac, triggerType in
            viewModel.logTriggerNotConfigured(mac: mac, triggerType: triggerType)
        }

        beaconManager.onTriggerConfigureSkipped = { mac, reason in
            viewModel.logTriggerConfigureSkipped(mac: mac, reason: reason)
        }

        beaconManager.onTriggerConfigureRequested = { mac, triggerType, triggerPara in
            viewModel.logTriggerConfigureRequested(mac: mac, triggerType: triggerType, triggerPara: triggerPara)
        }

        beaconManager.onTriggerConfigureResult = { mac, triggerType, success, error in
            viewModel.logTriggerConfigureResult(mac: mac, triggerType: triggerType, success: success, error: error)
        }

        beaconManager.onSubscribeResult = { mac, success, error, elapsedMs in
            viewModel.logSubscribeResult(mac: mac, success: success, error: error, elapsedMs: elapsedMs)
        }

        beaconManager.onPacketReceivedLogged = { mac, evt, byteCount, packetNumber, rawHex, elapsedMs in
            viewModel.logPacketReceived(
                mac: mac,
                evt: evt,
                byteCount: byteCount,
                packetNumber: packetNumber,
                rawHex: rawHex,
                elapsedMs: elapsedMs
            )
        }

        beaconManager.onNoDataTimeout = { mac, elapsedMs in
            viewModel.logNoDataTimeout(mac: mac, elapsedMs: elapsedMs)
        }
    }

    var body: some Scene {

        WindowGroup {

            ContentView(
                viewModel: viewModel,
                beaconManager: beaconManager
            )
        }
    }
}
