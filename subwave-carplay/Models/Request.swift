//
//  Request.swift
//  subwave-carplay
//
//  Shapes mirror docs/api.md's POST /request and GET /request/:id examples.

import Foundation

struct RequestSubmission: Encodable {
    var text: String
    var name: String?
}

struct RequestReceipt: Decodable {
    var success: Bool
    var requestId: String
    var status: String
}

/// GET /request/:id — status walks pending -> resolved | rejected | failed.
/// A 404 (surfaced by the client as `unknown`) means stop polling.
struct RequestOutcome: Decodable {
    var status: String
    var success: Bool?
    var ack: String?
    var track: Track?
    var queuePosition: Int?
    var message: String?

    static let terminalStatuses: Set<String> = ["resolved", "rejected", "failed", "unknown"]

    var isTerminal: Bool { Self.terminalStatuses.contains(status) }
}
