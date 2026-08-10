//
//  Untitled.swift
//  kBeacon
//
//  Created by Saumil on 10/08/26.
//

import SwiftUI
import kbeaconlib2

struct ConnectionStatusView: View {
    let state: KBConnState
    let deviceLabel: String?
    let onDisconnect: () -> Void

    private var color: Color {
        switch state {
        case .Connected: return .green
        case .Connecting, .Disconnecting: return .orange
        default: return .red
        }
    }

    private var label: String {
        switch state {
        case .Connected: return "Connected" + (deviceLabel.map { " to \($0)" } ?? "")
        case .Connecting: return "Connecting…"
        case .Disconnecting: return "Disconnecting…"
        default: return "Disconnected"
        }
    }

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.headline)
            Spacer()
            if state == .Connected {
                Button("Disconnect", action: onDisconnect).buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}
