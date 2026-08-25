//
//  StationPickerView.swift
//  subwave-carplay
//

import SwiftUI

struct StationPickerView: View {
    @Bindable var store: StationStore
    @State private var isPresentingAddStation = false
    @State private var editingStation: Station?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.stations) { station in
                    Button {
                        AppModel.shared.selectStation(station)
                    } label: {
                        stationRow(station)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { store.removeStation(station) }
                        Button("Edit") { editingStation = station }.tint(.blue)
                    }
                }

                Button {
                    isPresentingAddStation = true
                } label: {
                    Label("Add Station", systemImage: "plus")
                }
            }
            .navigationTitle("SUB/WAVE Stations")
        }
        .sheet(isPresented: $isPresentingAddStation) {
            AddStationView(store: store)
        }
        .sheet(item: $editingStation) { station in
            AddStationView(store: store, editingStation: station)
        }
    }

    private func stationRow(_ station: Station) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(station.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(station.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if station.id == store.selectedStationID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
    }
}
