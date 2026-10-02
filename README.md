# Tidebar

A lightweight macOS menu bar app that shows your current Dexcom glucose value and trend, e.g. `112 →`.

> [!WARNING]
> Tidebar is an independent project and is **not affiliated with, endorsed by, or supported by Dexcom**.
> It uses an unofficial, undocumented API that can change or stop working at any time.
> It is **not a medical device**. Do not use it to make treatment decisions. Always confirm with your
> Dexcom receiver or app.

## Features

- Current glucose and trend arrow in the menu bar. Values 6–12 minutes old are dimmed and show their age (`112 → 8m`).
- `--- ?` when data is missing, stale (older than 12 minutes), or can't be fetched, so an old value is never shown as current.
- mg/dL or mmol/L, formatted for your locale.
- Configurable menu bar font, weight, and size.
- Polls on the sensor's 5-minute cadence, and refreshes after the Mac wakes from sleep.
- Lives only in the menu bar: no Dock icon or windows besides Settings. Optional launch at login.

## Requirements

- macOS 14 Sonoma or later.
- A Dexcom CGM with **Share** turned on in the Dexcom app and **at least one follower**. Tidebar was built for the G7.
- The Dexcom account that *shares* the data (not a follower's account).

## Installation

**Homebrew:** coming soon.

**Build from source:**

```sh
git clone <this repository>
cd Tidebar
xcodebuild build -scheme Tidebar -configuration Release
```

Or open `Tidebar.xcodeproj` in Xcode and run the `Tidebar` scheme.

## Setup

1. Open Tidebar's menu in the menu bar and choose **Settings…**
2. Enter your Dexcom username and password, choose your region (United States, Outside United States, or Japan), and click **Save & Connect**.

## Privacy

- Your password is stored in the macOS Keychain. Your username and preferences are stored in UserDefaults.
- Glucose readings are kept in memory only and are never written to disk.
- Tidebar talks only to Dexcom's Share servers for your region. It has no analytics or tracking.
- The app is sandboxed with only outgoing network access.

## How it works

Tidebar uses the Dexcom **Share** API, the same unofficial service that the Dexcom Follow app and
community projects such as Nightscout use:

1. `General/AuthenticatePublisherAccount` exchanges the username and password for an account ID.
2. `General/LoginPublisherAccountById` exchanges the account ID and password for a session ID.
3. `Publisher/ReadPublisherLatestGlucoseValues` returns recent readings for the session.

The session is reused until Dexcom expires it, and then Tidebar signs in again once. To avoid triggering
Dexcom's account lockout, a rejected password stops all sign-in attempts until you update Settings,
and other sign-in failures back off for up to 15 minutes.

### References

The endpoints, region URLs, application IDs, and error codes come from these projects:

- [pydexcom](https://github.com/gagebenne/pydexcom) by Gage Benne (MIT): a Python client for the Share API,
  and the primary reference for Tidebar's implementation. See
  [`const.py`](https://github.com/gagebenne/pydexcom/blob/main/pydexcom/const.py) and
  [`dexcom.py`](https://github.com/gagebenne/pydexcom/blob/main/pydexcom/dexcom.py), or the
  [documentation](https://gagebenne.github.io/pydexcom/).
- [share2nightscout-bridge](https://github.com/nightscout/share2nightscout-bridge): Nightscout's bridge
  from Dexcom Share, one of the original implementations of this protocol.
- [What is Dexcom Follow?](https://www.dexcom.com/faqs/what-is-dexcom-follow): Dexcom's own explanation of Share and Follow.

## Development

Run the unit tests:

```sh
xcodebuild test -scheme Tidebar -destination 'platform=macOS' -only-testing:TidebarTests
```

The code is split into layers so other data sources (e.g. Nightscout) can be added without touching the UI or polling:

| Folder | Contents |
|---|---|
| `Tidebar/Domain` | Provider-agnostic models: `GlucoseReading`, `TrendDirection`, `GlucoseUnit` |
| `Tidebar/Providers` | The `GlucoseProvider` protocol, configuration and factory, and the Dexcom Share provider |
| `Tidebar/Monitoring` | Polling schedule, staleness rules, and display formatting |
| `Tidebar/Persistence` | Keychain, settings keys, launch at login |
| `Tidebar/Views` | Menu bar label, dropdown menu, Settings |
| `Tidebar/Debug` | Debug-build-only error and reading simulation |

### Debug menu

Debug builds add a **Debug** submenu to the dropdown that replaces the real provider with a simulated one.
It can simulate each error (invalid credentials, network unavailable, no readings, account locked, server
error) and reading states (current, aging, stale, rising or falling quickly, no trend) without contacting
Dexcom. Choose **Live Data** to go back. The simulation code is compiled out of Release builds.

## License

Tidebar is released under the [MIT License](LICENSE).
