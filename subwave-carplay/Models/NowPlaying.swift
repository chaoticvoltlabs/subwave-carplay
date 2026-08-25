//
//  NowPlaying.swift
//  subwave-carplay
//
//  docs/api.md's /now-playing example is simplified; the deployed shape
//  (confirmed live against radio.kluit.se) nests several fields as objects
//  rather than the doc's flat strings/ints. `context` is richer still (time
//  of day, weather, festival, clock — all objects, not the doc's plain
//  strings) and unused by this app's UI, so it's deliberately left
//  unmodeled rather than half-guessed; Codable ignores JSON keys with no
//  matching property.

import Foundation

struct NowPlayingResponse: Codable {
    var nowPlaying: Track?
    var dj: DJSummary?
    var listeners: ListenerCount?
    var streamOnline: Bool?
    var stream: StreamDescriptor?
    /// IANA zone, e.g. "Europe/Stockholm" — drives the Clock panel so it
    /// shows the station's own time, not the viewer's.
    var timezone: String?
}

struct ListenerCount: Codable {
    var current: Int?
    var peak: Int?
}

struct Track: Codable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var subsonic_id: String?
    var genre: String?
    var bpm: Double?
    var musicalKey: String?
    var moods: [String]?

    /// `/cover/:id` proxies Subsonic art for this id, when present.
    var coverID: String? { subsonic_id }
}

struct DJSummary: Codable {
    var name: String?
    var tagline: String?
    var station: String?
}

struct StreamDescriptor: Codable {
    var mount: String?
    var format: String?
    var bitrate: Int?
    var opusEnabled: Bool?
    var flacEnabled: Bool?
    var aacEnabled: Bool?
}

/// GET /dj — the fuller persona read (now-playing's `dj` is a lighter echo of this).
struct DJPersona: Codable {
    var name: String?
    var tagline: String?
    var soul: String?
    var frequency: String?
    var djMode: Bool?
    var station: String?
    var location: String?
}
