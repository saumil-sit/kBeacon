//
//  BeaconDevice.swift
//  kBeacon
//
//  Created by Saumil on 07/08/26.
//

import Foundation

struct BeaconDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let mac: String
    let uuid: String
    let rssi: Int
}
