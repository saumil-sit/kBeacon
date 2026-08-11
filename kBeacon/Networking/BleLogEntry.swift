//
//  Untitled.swift
//  kBeacon
//
//  Created by Saumil on 11/08/26.
//

struct BleLogEntry: Codable {
    let correlationId: String
    let eventTime: String
    let stage: String
    let event: String
    let reasonCode: Int?
    let elapsedMs: Int?
    let deviceMac: String?
    let phoneModel: String?
    let osVersion: String?
    let appVersion: String?
    let sessionId: String?
    let extra: [String: String]?

    enum CodingKeys: String, CodingKey {
        case correlationId = "correlation_id"
        case eventTime = "event_time"
        case stage
        case event
        case reasonCode = "reason_code"
        case elapsedMs = "elapsed_ms"
        case deviceMac = "device_mac"
        case phoneModel = "phone_model"
        case osVersion = "os_version"
        case appVersion = "app_version"
        case sessionId = "session_id"
        case extra
    }
}
