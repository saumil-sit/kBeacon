import Foundation

struct ReceivedPacketEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let eventType: Int
    let rawHex: String
    let byteCount: Int
}

