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

    // Explicit encode(to:), not the compiler-synthesized one - synthesized Encodable uses
    // encodeIfPresent for every Optional property, which OMITS the key entirely when nil
    // instead of writing `null`. Since reasonCode/elapsedMs/deviceMac/appVersion/extra are
    // nil on some events and set on others, entries in the same flush batch ended up as JSON
    // objects with different key sets, which PostgREST's bulk insert rejects outright with
    // PGRST102 "All object keys must match" - it builds one INSERT with a fixed column list
    // from the first row and errors on any row that doesn't match it exactly.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(correlationId, forKey: .correlationId)
        try container.encode(eventTime, forKey: .eventTime)
        try container.encode(stage, forKey: .stage)
        try container.encode(event, forKey: .event)
        try container.encode(reasonCode, forKey: .reasonCode)
        try container.encode(elapsedMs, forKey: .elapsedMs)
        try container.encode(deviceMac, forKey: .deviceMac)
        try container.encode(phoneModel, forKey: .phoneModel)
        try container.encode(osVersion, forKey: .osVersion)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(extra, forKey: .extra)
    }
}
