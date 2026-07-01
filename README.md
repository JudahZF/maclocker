# MacLocker

MacLocker is a local macOS 14+ menu bar app that watches a selected nearby Bluetooth device, calibrates a near and away RSSI threshold, and locks the Mac after sustained away evidence.

## Install

### GitHub Release

Download `MacLocker-1.0.zip` from the [MacLocker 1.0 release](https://github.com/JudahZF/maclocker/releases/tag/v1.0), unzip it, and move `MacLocker.app` to `/Applications`.

### Nix

```sh
nix profile install github:JudahZF/maclocker/v1.0#maclocker
```

Or run without installing:

```sh
nix run github:JudahZF/maclocker/v1.0
```

### Homebrew

```sh
brew tap JudahZF/maclocker
brew install --cask maclocker
```

## Signing and Gatekeeper

The default release package produced by this repository is Apple Development/ad-hoc signed, not Developer ID signed and notarized. Internet-downloaded ZIPs may trigger Gatekeeper warnings. If macOS blocks the app, use System Settings > Privacy & Security to allow it, or Control-click `MacLocker.app` and choose Open.

For a smoother public distribution, build a Developer ID signed, hardened-runtime enabled, notarized, and stapled app in Xcode Organizer, then pass the exported `MacLocker.app` to `scripts/package-release.sh /path/to/MacLocker.app`.

## Build and Run

Open `MacLocker.xcodeproj` in Xcode, select the `MacLocker` scheme, and run the app. The app is menu-bar only, so it appears as a `MacLocker` item in the menu bar instead of the Dock.

From the command line:

```sh
make build
make test
make verify
make release
```

## Bluetooth Permission

MacLocker needs Bluetooth access to scan for nearby peripherals. If macOS prompts for Bluetooth permission, allow it. If permission has already been denied, grant it from System Settings > Privacy & Security > Bluetooth, then restart the app.

## Accessibility Permission

Immediate locking uses the macOS Lock Screen shortcut, Control + Command + Q, posted through Accessibility APIs. Open MacLocker Settings > Safety and choose Accessibility to grant permission in System Settings > Privacy & Security > Accessibility.

Without Accessibility permission, MacLocker falls back to:

```sh
/usr/bin/pmset displaysleepnow
```

Display sleep can obey your password-after-sleep delay. If that delay is greater than zero, fallback locking is not immediate.

## Select and Calibrate

1. Open MacLocker Settings.
2. Choose a visible Bluetooth candidate in Device.
3. In Calibration, record a 10-second near sample while the watch is close to the Mac.
4. Record a 10-second away sample while the watch is away from the Mac.
5. If the samples are separated and stable enough, MacLocker stores the midpoint threshold and enables auto-lock.

Auto-lock does not arm until Bluetooth is authorized, a device is selected, calibration succeeds, auto-lock is enabled, and the app is not paused.

## Known Limitation

Direct Apple Watch Bluetooth visibility is not guaranteed. Apple devices may hide or rotate Bluetooth identifiers, and a watch may never appear as a stable macOS Bluetooth scan candidate. Version 1 does not include a watchOS companion app or iPhone proxy; if no stable candidate appears, keep auto-lock disabled.
