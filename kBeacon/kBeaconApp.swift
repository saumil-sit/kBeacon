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

    @StateObject private var beaconManager: BeaconManager
    @StateObject private var viewModel: BeaconViewModel
    private let bluetoothPermissionManager = BluetoothPermissionManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {

        let client = SupabaseClient(
            baseURL: "https://eeqlwtpeqdtbenscaijt.supabase.co",
            apiKey: "sb_publishable_JNnsFdpBxEPX6NKM-fA8Rw_7TsA339L"
        )

        let logger = BleLogger(client: client)

        let viewModel = BeaconViewModel(bleLogger: logger)
        _viewModel = StateObject(wrappedValue: viewModel)

        let manager = BeaconManager(bleLogger: logger)

        manager.onScanResult = { [weak manager] started in
            guard !started, let manager else { return }
            viewModel.logScanFailed(reason: manager.bluetoothState)
        }

        manager.onBeaconsDiscoveredBatch = { count in
            viewModel.logBeaconsDiscovered(count: count)
        }

        manager.onAdvDataChanged = { mac, rssi, advData in
            viewModel.logAdvDataChanged(mac: mac, rssi: rssi, advData: advData)
        }

        manager.onBluetoothStateChanged = { state in
            viewModel.logCentralBleStateChanged(state: state)
        }

        manager.onConnectRejected = { beacon in
            viewModel.logConnectRejected(mac: beacon.mac ?? "Unknown")
        }

        manager.onConnectionStateChanged = { beacon, state, reason in
            viewModel.logConnStateChanged(mac: beacon.mac ?? "Unknown", state: state, reason: reason)
        }

        manager.onCommonCfgUnavailable = { mac in
            viewModel.logCommonCfgUnavailable(mac: mac)
        }

        manager.onDeviceCapabilities = { mac, capabilities, model, version in
            viewModel.logDeviceCapabilities(mac: mac, capabilities: capabilities, model: model, version: version)
        }

        manager.onTriggerConfigRead = { mac, triggerType, triggerAction in
            viewModel.logTriggerConfigRead(mac: mac, triggerType: triggerType, triggerAction: triggerAction)
        }

        manager.onTriggerNotConfigured = { mac, triggerType in
            viewModel.logTriggerNotConfigured(mac: mac, triggerType: triggerType)
        }

        manager.onTriggerConfigureSkipped = { mac, reason in
            viewModel.logTriggerConfigureSkipped(mac: mac, reason: reason)
        }

        manager.onTriggerConfigureRequested = { mac, triggerType, triggerPara in
            viewModel.logTriggerConfigureRequested(mac: mac, triggerType: triggerType, triggerPara: triggerPara)
        }

        manager.onTriggerConfigureResult = { mac, triggerType, success, error in
            viewModel.logTriggerConfigureResult(mac: mac, triggerType: triggerType, success: success, error: error)
        }

        manager.onSubscribeResult = { mac, success, error, elapsedMs in
            viewModel.logSubscribeResult(mac: mac, success: success, error: error, elapsedMs: elapsedMs)
        }

        manager.onPacketReceivedLogged = { mac, evt, byteCount, packetNumber, rawHex, elapsedMs in
            viewModel.logPacketReceived(
                mac: mac,
                evt: evt,
                byteCount: byteCount,
                packetNumber: packetNumber,
                rawHex: rawHex,
                elapsedMs: elapsedMs
            )
        }

        manager.onNoDataTimeout = { mac, elapsedMs in
            viewModel.logNoDataTimeout(mac: mac, elapsedMs: elapsedMs)
        }

        _beaconManager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {

        WindowGroup {

            ContentView(
                viewModel: viewModel,
                beaconManager: beaconManager
            )
        }
        .onChange(of: scenePhase) { newPhase in
            // BleLogger's queue is in-memory only - without this, anything queued but not
            // yet flushed (2s timer / 20-row batch) is lost the moment iOS suspends or kills
            // the app in the background, with no way to recover it afterward.
            if newPhase == .background {
                viewModel.flushLogsNow()
            }
        }
    }
}
