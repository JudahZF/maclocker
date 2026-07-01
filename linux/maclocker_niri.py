#!/usr/bin/env python3
from __future__ import annotations

import argparse
import dataclasses
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from collections.abc import Iterable, Sequence


ADDRESS_PATTERN = r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}"
ADDRESS_RE = re.compile(rf"\b(?P<address>{ADDRESS_PATTERN})\b")
DEVICE_RE = re.compile(rf"\bDevice\s+(?P<address>{ADDRESS_PATTERN})(?:\s+(?P<detail>.*))?")
RSSI_RE = re.compile(r"\bRSSI:\s*(?P<rssi>-?\d+)\b")
PROPERTY_RE = re.compile(r"^(?:RSSI|TxPower|ManufacturerData|ServiceData|UUIDs|Connected|Paired|Trusted|Blocked):", re.I)


class BluetoothctlError(RuntimeError):
    pass


@dataclasses.dataclass(frozen=True)
class DeviceInfo:
    address: str
    name: str


@dataclasses.dataclass(frozen=True)
class RssiReading:
    address: str
    rssi: int
    line: str


@dataclasses.dataclass(frozen=True)
class RssiSample:
    rssi: int | None
    address: str | None
    readings: tuple[RssiReading, ...]
    matched_addresses: frozenset[str]


@dataclasses.dataclass
class AwayTracker:
    threshold: int
    required_samples: int
    missing_is_away: bool = True
    consecutive_away: int = 0

    def update(self, sample: RssiSample) -> tuple[bool, bool]:
        away = sample.rssi is None if self.missing_is_away else False
        if sample.rssi is not None:
            away = sample.rssi < self.threshold

        if away:
            self.consecutive_away += 1
        else:
            self.consecutive_away = 0

        return away, self.consecutive_away >= self.required_samples

    def reset(self) -> None:
        self.consecutive_away = 0


def normalize_address(value: str | None) -> str | None:
    if not value:
        return None
    match = ADDRESS_RE.search(value)
    if not match:
        return None
    return match.group("address").upper()


def parse_device_name_line(line: str) -> DeviceInfo | None:
    match = DEVICE_RE.search(line)
    if not match:
        return None

    detail = (match.group("detail") or "").strip()
    if not detail:
        return None

    if detail.lower().startswith(("name:", "alias:")):
        detail = detail.split(":", 1)[1].strip()
    elif PROPERTY_RE.match(detail):
        return None
    elif detail.startswith("(") and detail.endswith(")"):
        return None

    if not detail:
        return None

    return DeviceInfo(address=normalize_address(match.group("address")) or match.group("address").upper(), name=detail)


def parse_devices(text: str) -> list[DeviceInfo]:
    devices: dict[str, DeviceInfo] = {}
    for line in text.splitlines():
        device = parse_device_name_line(line)
        if device:
            devices[device.address] = device
    return list(devices.values())


def parse_rssi_reading(line: str) -> RssiReading | None:
    device_match = DEVICE_RE.search(line)
    rssi_match = RSSI_RE.search(line)
    if not device_match or not rssi_match:
        return None
    address = normalize_address(device_match.group("address"))
    if not address:
        return None
    return RssiReading(address=address, rssi=int(rssi_match.group("rssi")), line=line.strip())


def parse_rssi_readings(text: str) -> list[RssiReading]:
    readings: list[RssiReading] = []
    current_address: str | None = None
    for line in text.splitlines():
        device_match = DEVICE_RE.search(line)
        if device_match:
            current_address = normalize_address(device_match.group("address"))

        reading = parse_rssi_reading(line)
        if reading:
            readings.append(reading)
            continue

        rssi_match = RSSI_RE.search(line)
        if current_address and rssi_match:
            readings.append(RssiReading(address=current_address, rssi=int(rssi_match.group("rssi")), line=line.strip()))
    return readings


def resolve_target_addresses(target: str, devices: Iterable[DeviceInfo]) -> set[str]:
    target_address = normalize_address(target)
    if target_address:
        return {target_address}

    target_name = target.casefold()
    device_list = list(devices)

    exact = {device.address for device in device_list if device.name.casefold() == target_name}
    if exact:
        return exact

    return {device.address for device in device_list if target_name in device.name.casefold()}


def collect_target_sample(text: str, target: str, known_addresses: Iterable[str] = ()) -> RssiSample:
    devices = parse_devices(text)
    matched_addresses = {normalize_address(address) or address.upper() for address in known_addresses}
    matched_addresses |= resolve_target_addresses(target, devices)

    readings = tuple(reading for reading in parse_rssi_readings(text) if reading.address in matched_addresses)
    if not readings:
        return RssiSample(
            rssi=None,
            address=None,
            readings=(),
            matched_addresses=frozenset(matched_addresses),
        )

    strongest = max(readings, key=lambda reading: reading.rssi)
    return RssiSample(
        rssi=strongest.rssi,
        address=strongest.address,
        readings=readings,
        matched_addresses=frozenset(matched_addresses),
    )


def format_command(command: Sequence[str]) -> str:
    return " ".join(shlex.quote(part) for part in command)


def log(message: str) -> None:
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"{stamp} {message}", file=sys.stderr, flush=True)


class BluetoothctlScanner:
    def __init__(self, bluetoothctl: str = "bluetoothctl", timeout_command: str = "timeout") -> None:
        self.bluetoothctl = bluetoothctl
        self.timeout_command = timeout_command

    def run_bluetoothctl(self, args: Sequence[str], timeout: float = 10) -> str:
        executable = shutil.which(self.bluetoothctl) or self.bluetoothctl
        try:
            result = subprocess.run(
                [executable, *args],
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
        except FileNotFoundError as error:
            raise BluetoothctlError("bluetoothctl is not installed or is not in PATH") from error
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or "") + "\n" + (error.stderr or "")
            raise BluetoothctlError(f"bluetoothctl {' '.join(args)} timed out\n{output.strip()}") from error

        output = result.stdout + result.stderr
        if result.returncode != 0:
            raise BluetoothctlError(f"bluetoothctl {' '.join(args)} failed with exit {result.returncode}\n{output.strip()}")
        return output

    def list_devices(self) -> list[DeviceInfo]:
        return parse_devices(self.run_bluetoothctl(["devices"], timeout=8))

    def scan_output(self, seconds: float) -> str:
        scan_seconds = max(1, int(round(seconds)))
        executable = shutil.which(self.bluetoothctl) or self.bluetoothctl
        try:
            result = subprocess.run(
                [executable, "--timeout", str(scan_seconds), "scan", "on"],
                capture_output=True,
                text=True,
                timeout=scan_seconds + 5,
                check=False,
            )
        except FileNotFoundError as error:
            raise BluetoothctlError("bluetoothctl is not installed or is not in PATH") from error
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or "") + "\n" + (error.stderr or "")
            self.scan_off()
            return output

        output = result.stdout + result.stderr
        if result.returncode != 0 and self._looks_like_unsupported_timeout(output):
            output = self.scan_output_with_coreutils_timeout(scan_seconds)
        elif result.returncode != 0 and "No default controller" in output:
            raise BluetoothctlError(output.strip())

        self.scan_off()
        return output

    def scan_output_with_coreutils_timeout(self, seconds: int) -> str:
        timeout_executable = shutil.which(self.timeout_command)
        bluetoothctl_executable = shutil.which(self.bluetoothctl) or self.bluetoothctl
        if not timeout_executable:
            raise BluetoothctlError("bluetoothctl does not support --timeout and coreutils timeout is not in PATH")

        result = subprocess.run(
            [timeout_executable, f"{seconds}s", bluetoothctl_executable, "scan", "on"],
            capture_output=True,
            text=True,
            timeout=seconds + 5,
            check=False,
        )
        return result.stdout + result.stderr

    def scan_off(self) -> None:
        try:
            subprocess.run(
                [shutil.which(self.bluetoothctl) or self.bluetoothctl, "scan", "off"],
                capture_output=True,
                text=True,
                timeout=4,
                check=False,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return

    def info_output(self, address: str) -> str:
        try:
            return self.run_bluetoothctl(["info", address], timeout=8)
        except BluetoothctlError:
            return ""

    @staticmethod
    def _looks_like_unsupported_timeout(output: str) -> bool:
        lowered = output.casefold()
        return "--timeout" in lowered and any(term in lowered for term in ("unknown", "unrecognized", "invalid option"))


def sample_device(scanner: BluetoothctlScanner, target: str, scan_seconds: float, known_addresses: set[str]) -> RssiSample:
    if not known_addresses:
        try:
            known_addresses.update(resolve_target_addresses(target, scanner.list_devices()))
        except BluetoothctlError as error:
            log(f"device list unavailable: {error}")

    output = scanner.scan_output(scan_seconds)
    sample = collect_target_sample(output, target, known_addresses)
    known_addresses.update(sample.matched_addresses)

    info_parts = []
    for address in sorted(known_addresses):
        info = scanner.info_output(address)
        if info:
            info_parts.append(info)

    if info_parts:
        info_sample = collect_target_sample("\n".join(info_parts), target, known_addresses)
        if info_sample.rssi is not None:
            known_addresses.update(info_sample.matched_addresses)
            combined = tuple([*sample.readings, *info_sample.readings])
            strongest = max(combined, key=lambda reading: reading.rssi)
            return RssiSample(
                rssi=strongest.rssi,
                address=strongest.address,
                readings=combined,
                matched_addresses=frozenset(known_addresses),
            )

    return sample


def default_lock_commands(env: dict[str, str] | None = None) -> list[list[str]]:
    env = dict(os.environ) if env is None else env
    commands: list[list[str]] = []

    loginctl = shutil.which("loginctl")
    if loginctl:
        session_id = env.get("XDG_SESSION_ID")
        if session_id:
            commands.append([loginctl, "lock-session", session_id])
        else:
            commands.append([loginctl, "lock-session"])

    for name, args in (("swaylock", ["-f"]), ("gtklock", []), ("hyprlock", [])):
        executable = shutil.which(name)
        if executable:
            commands.append([executable, *args])

    return commands


def parse_lock_commands(values: Sequence[str] | None) -> list[list[str]]:
    if not values:
        return default_lock_commands()

    commands = []
    for value in values:
        command = shlex.split(value)
        if not command:
            raise ValueError("--lock-command cannot be empty")
        commands.append(command)
    return commands


def run_lock_commands(commands: Sequence[Sequence[str]], dry_run: bool) -> bool:
    if not commands:
        log("no lock command is available; install loginctl or pass --lock-command")
        return False

    for command in commands:
        if dry_run:
            log(f"dry-run: would run {format_command(command)}")
            return True

        log(f"locking with {format_command(command)}")
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=False)
        except FileNotFoundError:
            log(f"lock command not found: {command[0]}")
            continue
        except subprocess.TimeoutExpired:
            log(f"lock command timed out: {format_command(command)}")
            continue

        if result.returncode == 0:
            return True

        detail = (result.stderr or result.stdout).strip()
        suffix = f": {detail}" if detail else ""
        log(f"lock command failed with exit {result.returncode}{suffix}")

    return False


class Runner:
    def __init__(self) -> None:
        self.stopped = False

    def stop(self, signum: int, _frame: object) -> None:
        self.stopped = True
        log(f"received signal {signum}; stopping")

    def run(self, args: argparse.Namespace) -> int:
        scanner = BluetoothctlScanner(bluetoothctl=args.bluetoothctl)

        if args.list_devices:
            for device in scanner.list_devices():
                print(f"{device.address}\t{device.name}")
            return 0

        if not args.device:
            raise ValueError("--device is required unless --list-devices is used")

        lock_commands = parse_lock_commands(args.lock_command)
        known_addresses = set(resolve_target_addresses(args.device, []))
        tracker = AwayTracker(
            threshold=args.threshold,
            required_samples=args.away_samples,
            missing_is_away=not args.ignore_missing,
        )

        signal.signal(signal.SIGINT, self.stop)
        signal.signal(signal.SIGTERM, self.stop)

        while not self.stopped:
            try:
                sample = sample_device(scanner, args.device, args.sample_seconds, known_addresses)
            except BluetoothctlError as error:
                log(f"Bluetooth scan failed: {error}")
                sample = RssiSample(
                    rssi=None,
                    address=None,
                    readings=(),
                    matched_addresses=frozenset(known_addresses),
                )

            away, should_lock = tracker.update(sample)
            state = "away" if away else "near"
            rssi = "missing" if sample.rssi is None else f"{sample.rssi} dBm"
            address = sample.address or "unresolved"
            log(
                f"{state}: rssi={rssi} address={address} "
                f"away_samples={tracker.consecutive_away}/{tracker.required_samples}"
            )

            if should_lock:
                if run_lock_commands(lock_commands, dry_run=args.dry_run):
                    tracker.reset()
                    if args.once:
                        return 0
                    time.sleep(args.cooldown)
                    continue

            if args.once:
                return 0

            time.sleep(args.interval)

        return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Lock a Niri/Wayland session when a selected Bluetooth device RSSI stays below a threshold.",
    )
    parser.add_argument("--device", help="Bluetooth MAC address or unique device name to monitor")
    parser.add_argument("--threshold", type=int, default=-80, help="away threshold in dBm; lower RSSI is away (default: -80)")
    parser.add_argument("--away-samples", type=int, default=3, help="consecutive away/missing samples before locking")
    parser.add_argument("--sample-seconds", type=float, default=6, help="Bluetooth scan duration per sample")
    parser.add_argument("--interval", type=float, default=15, help="seconds to sleep between samples")
    parser.add_argument("--cooldown", type=float, default=300, help="seconds to wait after a successful lock")
    parser.add_argument("--lock-command", action="append", help="command to run when away; may be passed more than once")
    parser.add_argument("--ignore-missing", action="store_true", help="do not treat missing RSSI as away")
    parser.add_argument("--dry-run", action="store_true", help="log the lock command instead of executing it")
    parser.add_argument("--once", action="store_true", help="take one sample and exit")
    parser.add_argument("--list-devices", action="store_true", help="print known Bluetooth devices and exit")
    parser.add_argument("--bluetoothctl", default="bluetoothctl", help=argparse.SUPPRESS)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.away_samples < 1:
        parser.error("--away-samples must be at least 1")
    if args.sample_seconds <= 0:
        parser.error("--sample-seconds must be greater than 0")
    if args.interval < 0:
        parser.error("--interval must not be negative")
    if args.cooldown < 0:
        parser.error("--cooldown must not be negative")

    try:
        return Runner().run(args)
    except (BluetoothctlError, ValueError) as error:
        parser.exit(2, f"maclocker-niri: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
