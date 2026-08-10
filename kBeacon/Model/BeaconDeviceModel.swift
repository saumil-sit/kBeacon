//
//  BeaconDevice.swift
//  kBeacon
//
//  Created by Saumil on 07/08/26.
//

import Foundation
import kbeaconlib2

struct BeaconDeviceModel: Identifiable, Hashable {

    let id = UUID()
    let beacon: KBeacon
    let name: String
    let mac: String
    let uuid: String
    let rssi: Int
    let advData: [KeyValue]

    static func == (lhs: BeaconDeviceModel, rhs: BeaconDeviceModel) -> Bool {
        lhs.mac == rhs.mac
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(mac)
    }
}
