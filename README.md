# subwave-carplay

A CarPlay-first [SUB/WAVE](https://github.com/perminder-klair/subwave) listener
client — an internet radio platform where an AI DJ hosts the show, picks
music, and takes listener song requests live.

## Hard design rule

The driver never has to touch this app's own UI to keep the broadcast going.
Pick a station — from the phone or from CarPlay's own list — and it just
plays, phone screen off or away, until paused. Everything else is a bonus,
not a requirement for a drive.

## Scope

CarPlay's Human Interface Guidelines rule out free-text entry and dense
browsing while driving, so the CarPlay surface is deliberately small:

- Station list
- Now Playing — playback, transport controls, track metadata

Adding or editing stations and song requests live on the phone-only side, for
setup before a drive, not during one.

## Features

- CarPlay station list and Now Playing screen, with full transport control
  and Control Center / lock screen integration
- Station picker on the phone (add, edit, remove stations)
- Song requests from the phone
- Private-station support via HTTP Basic Auth
- Stream resilience: on a poor connection, the app mutes and shows a clear
  "Buffering" / "Poor Signal" / "Disconnected" state and retries with
  backoff, instead of looping stale audio

## Requirements

- iOS 26 or later
- Xcode 26 or later, to build
- An Apple Developer account with the CarPlay Audio App entitlement
  approved, to run on a physical CarPlay head unit (not required for the
  CarPlay Simulator)

## Getting started

1. Clone the repo and open `subwave-carplay.xcodeproj` in Xcode.
2. Build and run on an iPhone Simulator or a physical iPhone, then add a
   station by its address.
3. To preview the CarPlay screen without a car: boot the app, then
   **Simulator → I/O → External Displays → CarPlay** (menu wording varies by
   Xcode version). The app's icon appears in the CarPlay home screen dock.

## Private stations

To add a station with the stream/private-player password on, type the
address as `username:password@host` — the username can be anything (e.g.
`dj:`), only the password after the colon is actually checked. Easy to miss:
typing just the password with no `user:` prefix isn't a valid address and
won't authenticate.

## Copyright & license

PolyForm Noncommercial License 1.0.0 with Commercial Use by Explicit
Permission Only. See [LICENSE.txt](LICENSE.txt).

Copyright (c) 2026 Robin Kluit / Chaoticvolt.
