//
//  NowPlayingView.swift
//  subwave-carplay
//
//  Deliberately minimal: the driving surface is CarPlay, not this screen —
//  station picker, cover art, play/pause, and an optional song request. No
//  Booth log, no programme guide, no clock; a phone UI a driver should never
//  need mid-drive doesn't need any of that.
//
//  Purely a view onto AppModel's state — playback, polling, and now-playing
//  metadata are all owned there so they keep running whether or not this
//  screen is ever on screen (CarPlay-only use is the whole point).

import SwiftUI

struct NowPlayingView: View {
    let station: Station
    let onBack: () -> Void

    private var model: AppModel { AppModel.shared }
    @State private var isPresentingRequest = false

    private var client: SubwaveClient? { SubwaveClient(station: station) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                coverArt

                connectionBanner

                VStack(spacing: 6) {
                    Text(model.nowPlaying?.nowPlaying?.title ?? "—")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(model.nowPlaying?.nowPlaying?.artist ?? station.name)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if let dj = model.nowPlaying?.dj?.name {
                        Text("On air: \(dj)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let listeners = model.nowPlaying?.listeners?.current {
                        Text("\(listeners) listening")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal)

                if let loadError = model.loadError {
                    Text(loadError).foregroundStyle(.red)
                }
                if let playerError = model.player.playerError {
                    Text(playerError).foregroundStyle(.red)
                }

                Button {
                    model.player.togglePlayPause()
                } label: {
                    Label(model.player.isPlaying ? "Pause" : "Play", systemImage: model.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Button {
                    isPresentingRequest = true
                } label: {
                    Label("Request a Song", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle(station.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stations") { onBack() }
                }
            }
        }
        .sheet(isPresented: $isPresentingRequest) {
            if let client {
                RequestSongView(client: client)
            }
        }
    }

    /// Silence during a stall is intentional (see PlayerService) — this is
    /// what tells a listener *why* it's quiet instead of leaving them
    /// wondering if the app just died.
    @ViewBuilder
    private var connectionBanner: some View {
        switch model.player.connectionState {
        case .live:
            EmptyView()
        case .buffering:
            Label("Buffering…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .poorSignal:
            Label("Poor Signal — Reconnecting…", systemImage: "wifi.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        case .disconnected:
            Label("Disconnected — Retrying…", systemImage: "wifi.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var coverArt: some View {
        Group {
            if let coverImage = model.coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "waveform")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(60)
            }
        }
        .frame(width: 240, height: 240)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
