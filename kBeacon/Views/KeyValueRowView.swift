//
//  Untitled.swift
//  kBeacon
//
//  Created by Saumil on 10/08/26.
//

import SwiftUI

struct KeyValueRowView: View {
    let item: KeyValue

    var body: some View {
        HStack {
            Text(item.key).foregroundColor(.secondary)
            Spacer()
            Text(item.value)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
        Divider()
    }
}
