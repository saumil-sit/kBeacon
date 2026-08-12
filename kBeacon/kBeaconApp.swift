//
//  kBeaconApp.swift
//  kBeacon
//
//  Created by Saumil on 06/08/26.
//

import SwiftUI

@main
struct kBeaconApp: App {

    // ADD THIS LINE
    private let locationPermissionManager = LocationPermissionManager()

    @StateObject private var viewModel: BeaconViewModel

    init() {
        let client = SupabaseClient(
            baseURL: "https://eeqlwtpeqdtbenscaijt.supabase.co",
            apiKey: "sb_publishable_JNnsFdpBxEPX6NKM-fA8Rw_7TsA339L"
        )

        let logger = BleLogger(client: client)

        _viewModel = StateObject(
            wrappedValue: BeaconViewModel(bleLogger: logger)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
