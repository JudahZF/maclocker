import unittest

from linux.maclocker_niri import (
    AwayTracker,
    DeviceInfo,
    RssiSample,
    collect_target_sample,
    normalize_address,
    parse_devices,
    parse_rssi_reading,
    resolve_target_addresses,
)


class ParserTests(unittest.TestCase):
    def test_normalize_address_extracts_uppercase_address(self):
        self.assertEqual(normalize_address("watch aa:bb:cc:dd:ee:ff"), "AA:BB:CC:DD:EE:FF")

    def test_parse_devices_skips_property_changes(self):
        output = "\n".join(
            [
                "Device AA:BB:CC:DD:EE:FF Apple Watch",
                "Device AA:BB:CC:DD:EE:FF (public)",
                "[CHG] Device AA:BB:CC:DD:EE:FF RSSI: -72",
                "[CHG] Device 11:22:33:44:55:66 Name: Keyboard",
            ]
        )

        self.assertEqual(
            parse_devices(output),
            [
                DeviceInfo(address="AA:BB:CC:DD:EE:FF", name="Apple Watch"),
                DeviceInfo(address="11:22:33:44:55:66", name="Keyboard"),
            ],
        )

    def test_parse_rssi_reading(self):
        reading = parse_rssi_reading("[CHG] Device AA:BB:CC:DD:EE:FF RSSI: -67")

        self.assertIsNotNone(reading)
        self.assertEqual(reading.address, "AA:BB:CC:DD:EE:FF")
        self.assertEqual(reading.rssi, -67)

    def test_collect_target_sample_reads_bluetoothctl_info_shape(self):
        output = "\n".join(
            [
                "Device AA:BB:CC:DD:EE:FF (public)",
                "        Name: Apple Watch",
                "        RSSI: -74",
            ]
        )

        sample = collect_target_sample(output, "AA:BB:CC:DD:EE:FF")

        self.assertEqual(sample.rssi, -74)
        self.assertEqual(sample.address, "AA:BB:CC:DD:EE:FF")

    def test_resolve_target_prefers_exact_name(self):
        devices = [
            DeviceInfo(address="AA:AA:AA:AA:AA:AA", name="Watch"),
            DeviceInfo(address="BB:BB:BB:BB:BB:BB", name="Watch Charger"),
        ]

        self.assertEqual(resolve_target_addresses("Watch", devices), {"AA:AA:AA:AA:AA:AA"})

    def test_collect_target_sample_uses_strongest_matching_rssi(self):
        output = "\n".join(
            [
                "[NEW] Device AA:BB:CC:DD:EE:FF Apple Watch",
                "[CHG] Device AA:BB:CC:DD:EE:FF RSSI: -83",
                "[CHG] Device AA:BB:CC:DD:EE:FF RSSI: -69",
                "[CHG] Device 11:22:33:44:55:66 RSSI: -40",
            ]
        )

        sample = collect_target_sample(output, "Apple Watch")

        self.assertEqual(sample.rssi, -69)
        self.assertEqual(sample.address, "AA:BB:CC:DD:EE:FF")
        self.assertEqual(sample.matched_addresses, frozenset({"AA:BB:CC:DD:EE:FF"}))


class AwayTrackerTests(unittest.TestCase):
    def test_requires_consecutive_away_samples(self):
        tracker = AwayTracker(threshold=-80, required_samples=2)

        away, should_lock = tracker.update(RssiSample(-85, "AA", (), frozenset()))
        self.assertTrue(away)
        self.assertFalse(should_lock)

        away, should_lock = tracker.update(RssiSample(-70, "AA", (), frozenset()))
        self.assertFalse(away)
        self.assertFalse(should_lock)

        away, should_lock = tracker.update(RssiSample(None, None, (), frozenset()))
        self.assertTrue(away)
        self.assertFalse(should_lock)

        away, should_lock = tracker.update(RssiSample(-90, "AA", (), frozenset()))
        self.assertTrue(away)
        self.assertTrue(should_lock)

    def test_can_ignore_missing_rssi(self):
        tracker = AwayTracker(threshold=-80, required_samples=1, missing_is_away=False)

        away, should_lock = tracker.update(RssiSample(None, None, (), frozenset()))

        self.assertFalse(away)
        self.assertFalse(should_lock)


if __name__ == "__main__":
    unittest.main()
