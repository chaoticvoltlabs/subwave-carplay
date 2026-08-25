//
//  StationStore.swift
//  subwave-carplay
//

import Foundation
import Observation

@Observable
final class StationStore {
    private static let defaultsKey = "subwave.stations"

    private(set) var stations: [Station] = []
    var selectedStationID: UUID?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func addStation(name: String, address: String) {
        let station = Station(name: name, address: address)
        stations.append(station)
        selectedStationID = station.id
        save()
    }

    func updateStation(_ station: Station, name: String, address: String) {
        guard let index = stations.firstIndex(where: { $0.id == station.id }) else { return }
        stations[index].name = name
        stations[index].address = address
        save()
    }

    func removeStation(_ station: Station) {
        stations.removeAll { $0.id == station.id }
        if selectedStationID == station.id {
            selectedStationID = stations.first?.id
        }
        save()
    }

    var selectedStation: Station? {
        stations.first { $0.id == selectedStationID }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([Station].self, from: data)
        else { return }
        stations = decoded
        selectedStationID = stations.first?.id
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stations) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
