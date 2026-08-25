//
//  Station.swift
//  subwave-carplay
//

import Foundation

/// A saved SUB/WAVE station. `address` is stored exactly as the listener typed
/// it, credentials included (e.g. `dj:secret@radio.example.com`) — see
/// docs/private-station.md in the subwave repo: the URL *is* the shared
/// listening password, there's no separate account.
struct Station: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var address: String

    init(id: UUID = UUID(), name: String, address: String) {
        self.id = id
        self.name = name
        self.address = address
    }

    /// Parses `address` into a base URL (scheme + host + port + path, userinfo
    /// stripped) plus separately-extracted credentials. Defaults to `https`
    /// when the listener didn't type a scheme; LAN stations typed with an
    /// explicit `http://` are respected as-is (needs an ATS exception in
    /// Info.plist, per the feasibility note).
    var resolvedAddress: ResolvedAddress? {
        ResolvedAddress(typedAddress: address)
    }
}

struct StationCredentials: Equatable {
    let username: String
    let password: String
}

struct ResolvedAddress: Equatable {
    /// Credential-free, ready to use as the API/base URL. URLSession answers
    /// the server's basic-auth challenge from `credentials` itself, so this
    /// is also safe to hand directly to URLSession for API calls.
    let baseURL: URL
    let credentials: StationCredentials?

    init?(typedAddress: String) {
        let trimmed = typedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme) else { return nil }

        if let user = components.user, !user.isEmpty {
            credentials = StationCredentials(username: user, password: components.password ?? "")
        } else {
            credentials = nil
        }
        components.user = nil
        components.password = nil

        // Strip a trailing slash so endpoint paths can be appended uniformly.
        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        guard let url = components.url else { return nil }
        self.baseURL = url
    }
}
