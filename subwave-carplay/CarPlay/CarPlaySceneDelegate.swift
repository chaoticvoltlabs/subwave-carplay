//
//  CarPlaySceneDelegate.swift
//  subwave-carplay
//
//  The entire CarPlay surface, deliberately: a list of stations, and
//  CPNowPlayingTemplate for playback. No Booth, no Guide, no Clock, no
//  station editing — a driver never needs any of that, and CarPlay's own
//  Human Interface Guidelines wouldn't let a free-text "Request a Song"
//  entry point exist here anyway (that stays phone-only).
//
//  CPNowPlayingTemplate mirrors MPNowPlayingInfoCenter and
//  MPRemoteCommandCenter automatically, so PlayerService's existing
//  play/pause command targets drive this screen's transport controls with
//  no CarPlay-specific plumbing.

import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(makeStationListTemplate(), animated: true, completion: nil)

        // A station picked from the phone before ever connecting to CarPlay
        // (the common case: start the radio at home, then get in the car)
        // should land the driver straight on Now Playing, not make them
        // reselect from the list to see what's already playing.
        if AppModel.shared.stationStore.selectedStation != nil {
            interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: false, completion: nil)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func makeStationListTemplate() -> CPListTemplate {
        let stations = AppModel.shared.stationStore.stations
        let items = stations.map { station -> CPListItem in
            let item = CPListItem(text: station.name, detailText: station.address)
            item.handler = { [weak self] _, completion in
                self?.select(station)
                completion()
            }
            return item
        }
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Stations", sections: [section])
        return template
    }

    private func select(_ station: Station) {
        AppModel.shared.selectStation(station)
        interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }
}
