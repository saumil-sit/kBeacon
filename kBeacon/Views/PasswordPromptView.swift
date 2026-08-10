//
//  Untitled.swift
//  kBeacon
//
//  Created by Saumil on 10/08/26.
//

import SwiftUI

struct PasswordPromptView: View {
    let deviceLabel: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var password: String = ""
    @State private var isVisible = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Text("The default password didn't work for \"\(deviceLabel)\". Enter its connection password.")
                HStack {
                    if isVisible {
                        TextField("Device password", text: $password)
                    } else {
                        SecureField("Device password", text: $password)
                    }
                    Button(action: { isVisible.toggle() }) {
                        Image(systemName: isVisible ? "eye.slash" : "eye")
                    }
                }
            }
            .navigationTitle("Password required")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { onConfirm(password); dismiss() }
                        .disabled(password.isEmpty)
                }
            }
        }
    }
}
