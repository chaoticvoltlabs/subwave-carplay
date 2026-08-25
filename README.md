# subwave-carplay

A CarPlay-first [SUB/WAVE](https://github.com/perminder-klair/subwave) listener
client. Sibling project to [subwave-tvos](../subwave-tvos), sharing the same
API models/networking approach but a deliberately much smaller surface — see
"Scope" below.

## Hard design rule

The driver never has to touch this app's own UI to keep the broadcast going.
Pick a station — from the phone or from CarPlay's own list — and it just
plays, phone screen off or away, until paused. Playback, polling, and
now-playing metadata are all owned by `AppModel` (a shared singleton), not by
any SwiftUI view's lifecycle — confirmed necessary by testing in the CarPlay
Simulator: a first pass that ran the poll loop from `NowPlayingView.task`
left CarPlay showing no track metadata and the wrong play/pause icon,
because nothing was polling `/now-playing` while the phone UI was never on
screen.

## Scope

CarPlay's own Human Interface Guidelines rule out most of what subwave-tvos
has: no free-text entry while driving, no reading a Booth log or programme
guide off a car display. The whole CarPlay surface here is:

- `CPListTemplate` — station list
- `CPNowPlayingTemplate` — playback, transport controls, track metadata
  (mirrors `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` automatically, so
  `PlayerService`'s existing remote-command wiring drives it with no
  CarPlay-specific plumbing)

Station add/edit, song requests, and everything else live on the phone-only
side (`Views/`), for setup before a drive, not during one.

## CarPlay entitlement

Shipping this (TestFlight or App Store, or running on a car's real head
unit) requires Apple's CarPlay Audio App entitlement
(`com.apple.developer.carplay-audio`), a manual, separate approval — not yet
requested as of this project's creation. The entitlement is already in
`subwave_carplay.entitlements` so local development and testing against the
CarPlay Simulator work regardless; only real-hardware/store distribution is
blocked until Apple approves it.

## Testing without a car

Xcode's iOS Simulator can show a CarPlay display: boot a simulator, then
**Simulator → I/O → External Displays → CarPlay** (menu path/wording varies
by Xcode version). The app's icon appears in the CarPlay home screen dock.

## Architecture note

`AppModel.shared` (in `AppModel.swift`) is the one shared owner of
`StationStore` and `PlayerService`. `CPTemplateApplicationSceneDelegate` is
instantiated by UIKit from Info.plist with no initializer this code
controls, so there's no SwiftUI environment to inject into it — a singleton
is the standard way both the phone UI scene and the CarPlay scene reach the
same playback state.
