//
//  Untitled.swift
//  kBeacon
//
//  Created by Saumil on 11/08/26.
//

import Foundation
import UIKit

final class BleLogger {
    private let client: SupabaseClient
    private let flushIntervalSeconds: TimeInterval = 2.0
    private let batchSize = 20
    private let maxQueueSize = 500

    let sessionId = UUID().uuidString

    private var queue: [BleLogEntry] = []
    private let queueLock = NSLock()
    private var flushTask: Task<Void, Never>?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(client: SupabaseClient) {
        self.client = client
        startFlushLoop()
    }

    private func startFlushLoop() {
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(flushIntervalSeconds * 1_000_000_000))
                await flush()
            }
        }
    }

    func log(
        correlationId: String,
        stage: String,
        event: String,
        reasonCode: Int? = nil,
        elapsedMs: Int? = nil,
        deviceMac: String? = nil,
        extra: [String: String]? = nil
    ) {
        let entry = BleLogEntry(
            correlationId: correlationId,
            eventTime: dateFormatter.string(from: Date()),
            stage: stage,
            event: event,
            reasonCode: reasonCode,
            elapsedMs: elapsedMs,
            deviceMac: deviceMac,
            phoneModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            sessionId: sessionId,
            extra: extra
        )

        print("[KBeaconBLE] \(entry.eventTime) [\(stage)] \(event) mac=\(deviceMac ?? "") reason=\(reasonCode.map(String.init) ?? "") elapsedMs=\(elapsedMs.map(String.init) ?? "") correlationId=\(correlationId)")

        queueLock.lock()
        if queue.count >= maxQueueSize {
            queue.removeFirst()
        }
        queue.append(entry)
        let shouldFlushNow = queue.count >= batchSize
        queueLock.unlock()

        if shouldFlushNow {
            Task { await flush() }
        }
    }

    func flushNow() {
        Task { await flush() }
    }

    private func flush() async {
        queueLock.lock()
        guard !queue.isEmpty else { queueLock.unlock(); return }
        let batch = queue
        queue.removeAll()
        queueLock.unlock()

        do {
            try await client.insertLogs(batch)
            print("[KBeaconBLE] flushed \(batch.count) log row(s) to Supabase")
        } catch {
            print("[KBeaconBLE] flush failed: \(error)")
            queueLock.lock()
            queue = (batch + queue).suffix(maxQueueSize).map { $0 }
            queueLock.unlock()
        }
    }
}
