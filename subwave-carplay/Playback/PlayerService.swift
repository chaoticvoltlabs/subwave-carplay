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

import AVFoundation
import MediaPlayer
import Observation
import UIKit

@Observable
final class PlayerService {
    private(set) var isPlaying = false
    private(set) var playerError: String?

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var stationName: String = "SUB/WAVE"

    func configure(station: Station) {
        stop()
        playerError = nil
        activateAudioSession()

        guard let resolved = station.resolvedAddress else {
            playerError = "Invalid station address."
            return
        }
        stationName = station.name

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
        let player = AVPlayer(playerItem: item)
        self.player = player

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .failed:
                    self?.playerError = item.error?.localizedDescription ?? "Stream unreachable."
                    self?.isPlaying = false
                default:
                    break
                }
            }
        }

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
    }

    /// Called by the now-playing poller so the lock screen, Control Center,
    /// and CarPlay's now-playing screen all reflect the current track.
    func updateNowPlayingInfo(track: Track?, coverImage: UIImage?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track?.title ?? stationName,
            MPMediaItemPropertyArtist: track?.artist ?? "",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            // CPNowPlayingTemplate (and Control Center) derive their
            // play/pause icon from this, not from asking the app directly —
            // omitting it left CarPlay showing "Play" while audio was
            // already playing.
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let album = track?.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let coverImage {
            let artwork = MPMediaItemArtwork(boundsSize: coverImage.size) { _ in coverImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
