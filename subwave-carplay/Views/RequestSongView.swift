//
//  RequestSongView.swift
//  subwave-carplay
//

import SwiftUI

struct RequestSongView: View {
    let client: SubwaveClient
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var name = ""
    @State private var phase: Phase = .composing

    private enum Phase {
        case composing
        case submitting
        case waiting(requestId: String)
        case outcome(RequestOutcome)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch phase {
                case .composing, .submitting:
                    Section("What do you want to hear?") {
                        TextField("something slower than this", text: $text)
                    }
                    Section("Name (optional)") {
                        TextField("alex", text: $name)
                    }
                case .waiting:
                    Section {
                        HStack {
                            ProgressView()
                            Text("Waiting for the booth…")
                        }
                    }
                case .outcome(let outcome):
                    Section {
                        outcomeView(outcome)
                    }
                case .failed(let message):
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Request a Song")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if case .composing = phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { submit() }
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func outcomeView(_ outcome: RequestOutcome) -> some View {
        switch outcome.status {
        case "resolved":
            VStack(alignment: .leading, spacing: 8) {
                if let ack = outcome.ack {
                    Text(ack)
                }
                if let track = outcome.track {
                    Text("\(track.title ?? "—") — \(track.artist ?? "")")
                        .foregroundStyle(.secondary)
                }
            }
        case "rejected", "failed":
            Text(outcome.message ?? outcome.ack ?? "The booth couldn't fit that in.")
                .foregroundStyle(.orange)
        default:
            Text("The booth lost track of that request.")
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        phase = .submitting
        Task {
            do {
                let receipt = try await client.submitRequest(
                    text: text.trimmingCharacters(in: .whitespaces),
                    name: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
                )
                phase = .waiting(requestId: receipt.requestId)
                await poll(requestId: receipt.requestId)
            } catch {
                phase = .failed("Couldn't send that request. Try again in a moment.")
            }
        }
    }

    private func poll(requestId: String) async {
        for _ in 0..<30 {
            guard let outcome = try? await client.fetchRequestOutcome(id: requestId) else {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            if outcome.isTerminal {
                phase = .outcome(outcome)
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        phase = .failed("The booth is taking a while — check back later.")
    }
}
