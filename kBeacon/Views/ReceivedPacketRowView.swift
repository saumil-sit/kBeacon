//
//  ReceivedPacketRowView.swift
//  kBeacon
//
//  Created by Saumil on 10/08/26.
//

import SwiftUI

struct ReceivedPacketRowView: View {
    let entry: ReceivedPacketEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.timestamp).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("Event type \(entry.eventType) · \(entry.byteCount)B").font(.caption).foregroundColor(.secondary)
            }
            Text(entry.rawHex.isEmpty ? "(no payload)" : entry.rawHex).font(.body)
        }
        .padding(.vertical, 4)
    }
}
