//
//  ContentView.swift
//  subwave-carplay
//

import SwiftUI

struct ContentView: View {
    private var store: StationStore { AppModel.shared.stationStore }

    var body: some View {
        StoreBoundContentView(store: store)
    }
}

/// Split out so `@Bindable` has a concrete, non-computed property to bind to.
private struct StoreBoundContentView: View {
    @Bindable var store: StationStore

    var body: some View {
        if let station = store.selectedStation {
            NowPlayingView(station: station) {
                AppModel.shared.deselectStation()
            }
        } else {
            StationPickerView(store: store)
        }
    }
}

#Preview {
    ContentView()
}
