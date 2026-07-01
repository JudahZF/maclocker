# MacLocker

MacLocker is a proximity locker. On macOS 14+ it is a menu bar app that watches a selected nearby Bluetooth device, calibrates a near and away RSSI threshold, and locks the Mac after sustained away evidence.

On Linux/Niri it is a small CLI, `maclocker-niri`, that samples Bluetooth RSSI through BlueZ `bluetoothctl` and runs a session lock command after repeated away samples.

## Install

### GitHub Release for macOS

Download `MacLocker-1.0.zip` from the [MacLocker 1.0 release](https://github.com/JudahZF/maclocker/releases/tag/v1.0), unzip it, and move `MacLocker.app` to `/Applications`.

### Nix for macOS

```sh
nix profile install github:JudahZF/maclocker/v1.0#maclocker
```

Or run without installing:

```sh
nix run github:JudahZF/maclocker/v1.0
```

### NixOS and Niri

From a checkout:

```sh
nix run .#maclocker-niri -- --list-devices
nix run .#maclocker-niri -- --device AA:BB:CC:DD:EE:FF --threshold -80 --dry-run
```

From GitHub after this branch is published:

```sh
nix run github:JudahZF/maclocker#maclocker-niri -- --device AA:BB:CC:DD:EE:FF --threshold -80
```

The Linux flake package includes the runtime tools it directly needs: BlueZ `bluetoothctl`, `loginctl` from systemd, and coreutils `timeout`. Custom locker commands such as `swaylock`, `gtklock`, or `hyprlock` are used from your session `PATH`.

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

Linux checks that do not require Nix:

```sh
make linux-check
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

## Niri and NixOS Usage

Enable Bluetooth on NixOS and make sure your user session can talk to BlueZ. A typical NixOS system has:

```nix
{
  hardware.bluetooth.enable = true;
  services.blueman.enable = true; # optional, useful for pairing and trust management
}
```

Pair or trust the device first if needed, then find the address:

```sh
maclocker-niri --list-devices
```

Run a dry test:

```sh
maclocker-niri \
  --device AA:BB:CC:DD:EE:FF \
  --threshold -80 \
  --away-samples 3 \
  --dry-run
```

Run with an explicit Wayland locker:

```sh
maclocker-niri \
  --device AA:BB:CC:DD:EE:FF \
  --threshold -80 \
  --lock-command "swaylock -f"
```

By default, `maclocker-niri` tries `loginctl lock-session $XDG_SESSION_ID` when `XDG_SESSION_ID` is set, otherwise `loginctl lock-session`. If that command fails, it tries installed common Wayland lockers in this order: `swaylock -f`, `gtklock`, then `hyprlock`. A successful `loginctl lock-session` only requests that the session lock itself; under Niri you still need a session component that reacts to the logind lock signal, or pass an explicit locker with `--lock-command`.

A NixOS user service can run it for your graphical session:

```nix
{ inputs, pkgs, ... }:
let
  maclockerNiri = inputs.maclocker.packages.${pkgs.system}.maclocker;
in
{
  environment.systemPackages = [
    maclockerNiri
    pkgs.swaylock
  ];

  systemd.user.services.maclocker-niri = {
    description = "MacLocker Niri Bluetooth proximity lock";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${maclockerNiri}/bin/maclocker-niri --device AA:BB:CC:DD:EE:FF --threshold -80 --lock-command \"swaylock -f\"";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
```

RSSI behavior:

- Each sample starts a short `bluetoothctl scan on` window and uses the strongest RSSI seen for the selected device.
- Device names can work, but a stable Bluetooth address is more reliable because many devices reuse or hide names.
- RSSI below `--threshold` counts as away. Missing RSSI also counts as away unless `--ignore-missing` is set.
- Locking happens after `--away-samples` consecutive away samples, then waits `--cooldown` seconds before arming again.

## Known Limitation

Direct Apple Watch Bluetooth visibility is not guaranteed. Apple devices may hide or rotate Bluetooth identifiers, and a watch may never appear as a stable macOS Bluetooth scan candidate. Version 1 does not include a watchOS companion app or iPhone proxy; if no stable candidate appears, keep auto-lock disabled.

The same Bluetooth limitation applies on Linux. `maclocker-niri` can only act on RSSI values that BlueZ exposes for a visible, stable device. It does not need root for normal operation, but it does need a working user Bluetooth session and a locker that can lock your Niri session.
