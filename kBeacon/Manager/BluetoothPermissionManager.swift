//
//  Untitled.swift
//  kBeacon
//
//  Created by Saumil on 12/08/26.
//
import Foundation
import CoreBluetooth

final class BluetoothPermissionManager: NSObject, CBCentralManagerDelegate {

    private var central: CBCentralManager?

    override init() {
        super.init()

        print("Initializing CoreBluetooth manager")

        // This triggers the Bluetooth permission popup
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

        switch central.state {

        case .poweredOn:
            print("CoreBluetooth powered ON")

        case .poweredOff:
            print("CoreBluetooth powered OFF")

        case .unauthorized:
            print("CoreBluetooth unauthorized")

        case .unsupported:
            print("CoreBluetooth unsupported")

        default:
            print("CoreBluetooth state: \(central.state.rawValue)")
        }
    }
}
