//
//  Untitled.swift
//  kBeacon
//
//  Created by Saumil on 10/08/26.
//

import SwiftUI

struct LiveDataVerdictView: View {
    let packetCount: Int

    private var isReceiving: Bool { packetCount > 0 }

    var body: some View {
        HStack {
            Image(systemName: isReceiving ? "checkmark.circle.fill" : "wifi")
                .foregroundColor(isReceiving ? .green : .orange)
            Text(isReceiving ? "Working — \(packetCount) packet(s) received" : "Waiting for data from device…")
                .font(.subheadline)
                .foregroundColor(isReceiving ? .green : .orange)
        }
        .padding(12)
        .background(isReceiving ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
        .cornerRadius(8)
    }
}
