//
//  AppModel.swift
//  subwave-carplay
//
//  The phone UI and the CarPlay scene are separate UIScenes in the same
//  process, both controlling one audio session — they need to share the
//  exact same StationStore/PlayerService instances, not independent copies.
//  CPTemplateApplicationSceneDelegate is instantiated by UIKit from
//  Info.plist (no initializer we control), so there's no SwiftUI
//  environment to inject into it; a shared singleton is the standard way
//  around that for CarPlay apps.
//
//  Station selection, playback, and now-playing polling all live HERE,
//  not in a View's `.task` — confirmed live in the CarPlay Simulator that
//  driving selection entirely from a `NowPlayingView`-owned poll loop
//  breaks the hard design rule ("pick a station, phone away, it just
//  plays"): CPNowPlayingTemplate showed no metadata and the wrong
//  play/pause state, because nothing was polling /now-playing when the
//  phone UI never appeared on screen.

import Foundation
import UIKit

@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    let stationStore = StationStore()
    let player = PlayerService()

    private(set) var nowPlaying: NowPlayingResponse?
    private(set) var coverImage: UIImage?
    private(set) var loadError: String?

    private var pollTask: Task<Void, Never>?

    /// The public API is poll-based, no websocket/SSE (docs/api.md).
    private static let pollInterval: Duration = .seconds(15)

    private init() {
        // A relaunch with a station already selected (persisted from last
        // time) needs the same treatment as a fresh pick — otherwise the
        // stored selection points at a station nothing is actually playing
        // or polling for.
        if let station = stationStore.selectedStation {
            selectStation(station)
        }
    }

    /// The one entry point for "the driver/listener picked this station" —
    /// phone tap and CarPlay list-select both call this, so both surfaces
    /// get playback and now-playing metadata identically.
    func selectStation(_ station: Station) {
        stationStore.selectedStationID = station.id
        nowPlaying = nil
        coverImage = nil
        loadError = nil
        player.configure(station: station)
        player.play()
        startPolling(for: station)
    }

    func deselectStation() {
        pollTask?.cancel()
        stationStore.selectedStationID = nil
        player.stop()
        nowPlaying = nil
        coverImage = nil
    }

    private func startPolling(for station: Station) {
        pollTask?.cancel()
        guard let client = SubwaveClient(station: station) else {
            loadError = "Invalid station address."
            return
        }
        pollTask = Task {
            while !Task.isCancelled {
                await refresh(using: client, stationName: station.name)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func refresh(using client: SubwaveClient, stationName: String) async {
        do {
            let latest = try await client.fetchNowPlaying()
            let trackChanged = latest.nowPlaying?.coverID != nowPlaying?.nowPlaying?.coverID
            nowPlaying = latest
            loadError = nil

            if trackChanged {
                coverImage = nil
                if let coverID = latest.nowPlaying?.coverID,
                   let data = try? await client.fetchCoverImageData(id: coverID) {
                    coverImage = UIImage(data: data)
                }
            }
            player.updateNowPlayingInfo(track: latest.nowPlaying, coverImage: coverImage)
        } catch {
            loadError = "Couldn't reach \(stationName)."
        }
    }
}
