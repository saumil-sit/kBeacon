//
//  BeaconViewModel.swift
//  kBeacon
//
//  Created by Saumil on 11/08/26.
//

import Foundation
import Combine
import kbeaconlib2

final class BeaconViewModel: ObservableObject {

    // MARK: - Published properties

    @Published var connectionState: KBConnState = .Disconnected
    @Published var connectedDeviceLabel: String? = nil
    @Published var isScanning: Bool = false
    @Published var packetCount: Int = 0
    @Published var receivedPackets: [ReceivedPacketEntry] = []
    @Published var discoveredBeacons: [KBeacon] = []
    @Published var advDataByMac: [String: [KeyValue]] = [:]
    @Published var authFailedBeacon: KBeacon? = nil

    // MARK: - Dependencies

    private let bleLogger: BleLogger

    init(bleLogger: BleLogger) {
        self.bleLogger = bleLogger
    }

    // MARK: - Actions

    func startScan() {
        isScanning = true
    }

    func stopScan() {
        isScanning = false
    }

    func connect(_ beacon: KBeacon) {
        connectedDeviceLabel = beacon.name ?? beacon.mac
        connectionState = .Connected
    }

    func disconnect() {
        connectionState = .Disconnected
        connectedDeviceLabel = nil
        packetCount = 0
        receivedPackets.removeAll()
    }

    func dismissPasswordPrompt() {
        authFailedBeacon = nil
    }

    func retryConnectWithPassword(_ password: String) {
        authFailedBeacon = nil
    }
}
