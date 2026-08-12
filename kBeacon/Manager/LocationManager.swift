//
//  LocationManager.swift
//  kBeacon
//
//  Created by Saumil on 12/08/26.
//

import Foundation
import CoreLocation

final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self

        // Request permission when app starts
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location permission granted")

        case .denied, .restricted:
            print("Location permission denied")

        case .notDetermined:
            print("Location permission not determined")

        @unknown default:
            break
        }
    }
}
