//
//  PlayerService.swift
//  subwave-carplay
//
//  Owns the AVPlayer pointed at a station's Icecast MP3 mount, the Now
//  Playing Info Center / remote-command integration, and the audio session
//  that lets playback survive the phone locking or the app backgrounding —
//  the hard rule for this project: pick a station, put the phone away, the
//  broadcast keeps going. CPNowPlayingTemplate mirrors MPNowPlayingInfoCenter
//  and MPRemoteCommandCenter automatically, so this same service drives both
//  the phone UI and CarPlay's now-playing screen with no CarPlay-specific
//  code in here.
//
//  Credentials always ride as an explicit `Authorization: Basic` header
//  rather than `user:pass@` in the stream URL: AVPlayer silently drops
//  userinfo from media URLs (docs/private-station.md in the subwave repo,
//  issue #764), so this is required, not just tidier.
//
//  Connection resilience: a plain progressive-HTTP MP3 stream (no HLS, no
//  jitter buffer) has no graceful story for a degrading mobile connection —
//  the existing SUB/WAVE iOS app is known to loop small chunks of stale
//  buffered audio (or half a spoken line) forever when a connection turns
//  patchy, which is exactly the kind of dead zone a drive through rural
//  DE/SE/DK produces. Rather than let AVPlayer sit stalled indefinitely and
//  risk the same thing, a stall past a short grace period mutes output
//  (silence over a glitch/loop, always) and forces a fresh reconnect with
//  backoff, surfaced as `connectionState` so the UI can show a plain
//  "poor signal" state instead of pretending everything is fine.

import AVFoundation
import MediaPlayer
import Observation
import UIKit

enum ConnectionState {
    /// Playing normally.
    case live
    /// A stall was just detected; still inside the short grace period
    /// before treating it as a real problem (brief network hiccups are
    /// normal and shouldn't flip into "poor signal" for a stutter that
    /// clears itself in a second or two).
    case buffering
    /// Stalled past the grace period; actively reconnecting with backoff.
    case poorSignal
    /// Several reconnect attempts have failed; still retrying, just slower.
    case disconnected
}

@Observable
final class PlayerService {
    private(set) var isPlaying = false
    private(set) var playerError: String?
    private(set) var connectionState: ConnectionState = .live

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var stallTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var currentStation: Station?
    private var stationName: String = "SUB/WAVE"

    private static let stallGrace: Duration = .seconds(8)
    private static let maxBackoff: Double = 30
    private static let attemptsBeforeDisconnected = 3

    func configure(station: Station) {
        stop()
        playerError = nil
        connectionState = .live
        reconnectAttempts = 0
        currentStation = station
        stationName = station.name
        activateAudioSession()
        buildPlayerItem(for: station)
        setUpRemoteCommands()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        activateAudioSession()
        player.play()
        isPlaying = true
        playerError = nil
        updatePlaybackRate()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updatePlaybackRate()
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        statusObservation = nil
        timeControlObservation = nil
        stallTask?.cancel()
        stallTask = nil
        currentStation = nil
    }

    /// Called by the now-playing poller so the lock screen, Control Center,
    /// and CarPlay's now-playing screen all reflect the current track.
    func updateNowPlayingInfo(track: Track?, coverImage: UIImage?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: displayTitle(track: track),
            MPMediaItemPropertyArtist: connectionState == .live ? (track?.artist ?? "") : "",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            // CPNowPlayingTemplate (and Control Center) derive their
            // play/pause icon from this, not from asking the app directly —
            // omitting it left CarPlay showing "Play" while audio was
            // already playing.
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if connectionState == .live, let album = track?.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if connectionState == .live, let coverImage {
            let artwork = MPMediaItemArtwork(boundsSize: coverImage.size) { _ in coverImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// A stale track title while actually silently stalled is more
    /// misleading than showing nothing — say so plainly instead.
    private func displayTitle(track: Track?) -> String {
        switch connectionState {
        case .live: return track?.title ?? stationName
        case .buffering: return "Buffering…"
        case .poorSignal: return "Poor Signal — Reconnecting…"
        case .disconnected: return "Disconnected — Retrying…"
        }
    }

    // MARK: - Playback item construction

    private func buildPlayerItem(for station: Station) {
        guard let resolved = station.resolvedAddress else {
            playerError = "Invalid station address."
            return
        }

        let streamURL = resolved.baseURL.appendingPathComponent("/stream.mp3")
        var headers: [String: String] = [:]
        if let credentials = resolved.credentials {
            let raw = "\(credentials.username):\(credentials.password)"
            if let token = raw.data(using: .utf8)?.base64EncodedString() {
                headers["Authorization"] = "Basic \(token)"
            }
        }

        // "AVURLAssetHTTPHeaderFieldsKey" — no longer declared in recent
        // SDKs' public AVFoundation headers, but still present in the linked
        // binary and still the documented way native SUB/WAVE clients attach
        // the stream Authorization header (docs/private-station.md).
        let asset = AVURLAsset(url: streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard case .failed = item.status else { return }
                self?.playerError = item.error?.localizedDescription ?? "Stream unreachable."
                self?.isPlaying = false
                // A failed item is a harder failure than a stall, but the
                // same recovery path applies: mute, back off, retry.
                self?.beginStallWatch()
            }
        }

        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            let player = AVPlayer(playerItem: item)
            self.player = player
            timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                Task { @MainActor in
                    self?.handleTimeControlChange(player.timeControlStatus, reason: player.reasonForWaitingToPlay)
                }
            }
        }
    }

    private func handleTimeControlChange(_ status: AVPlayer.TimeControlStatus, reason: AVPlayer.WaitingReason?) {
        switch status {
        case .playing:
            recoverToLive()
        case .waitingToPlayAtSpecifiedRate:
            // `.evaluatingBufferingRate` is normal start-of-playback
            // buffering, not a network problem; `.toMinimizeStalls` is the
            // one that means "playback had started and just stalled".
            guard reason == .toMinimizeStalls else { return }
            beginStallWatch()
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func recoverToLive() {
        stallTask?.cancel()
        stallTask = nil
        reconnectAttempts = 0
        connectionState = .live
        player?.volume = 1
    }

    private func beginStallWatch() {
        guard stallTask == nil else { return }
        connectionState = .buffering
        stallTask = Task { [weak self] in
            await self?.stallLoop()
        }
    }

    /// Waits out the grace period, then — if still not playing — mutes,
    /// rebuilds the connection, and keeps retrying with backoff until
    /// playback resumes (detected via `handleTimeControlChange` cancelling
    /// this task) or the task is cancelled some other way (station
    /// changed, stopped).
    private func stallLoop() async {
        try? await Task.sleep(for: Self.stallGrace)
        guard !Task.isCancelled else { return }

        while !Task.isCancelled {
            guard let player, player.timeControlStatus != .playing else { return }
            guard let station = currentStation else { return }

            player.volume = 0
            reconnectAttempts += 1
            connectionState = reconnectAttempts >= Self.attemptsBeforeDisconnected ? .disconnected : .poorSignal

            buildPlayerItem(for: station)
            player.play()

            let backoff = min(Double(reconnectAttempts) * 10, Self.maxBackoff)
            try? await Task.sleep(for: .seconds(backoff))
        }
    }

    /// Nudges just the play/pause icon state immediately on toggle, rather
    /// than waiting for the next /now-playing poll (up to 15s away) to
    /// call `updateNowPlayingInfo` with the full track info again.
    private func updatePlaybackRate() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// `.playback` (not `.ambient`/`.soloAmbient`) is what keeps audio going
    /// with the screen locked or the app backgrounded/CarPlay-only — paired
    /// with the `audio` background mode in Info.plist.
    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
    }
}
