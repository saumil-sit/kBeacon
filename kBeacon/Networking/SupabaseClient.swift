//
//  SupabaseClient.swift
//  kBeacon
//
//  Created by Saumil on 11/08/26.
//

import Foundation

final class SupabaseClient {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    init(baseURL: String, apiKey: String) {
        self.baseURL = URL(string: baseURL)!
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func insertLogs(_ entries: [BleLogEntry]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/ble_logs"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(entries)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.httpError(httpResponse.statusCode, body)
        }
    }
}

enum SupabaseError: Error {
    case invalidResponse
    case httpError(Int, String)
}
