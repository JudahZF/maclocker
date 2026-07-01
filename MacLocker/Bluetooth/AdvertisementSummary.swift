@preconcurrency import CoreBluetooth
import Foundation

struct AdvertisementSummary: Codable, Equatable {
    var localName: String?
    var serviceUUIDs: [String]
    var overflowServiceUUIDs: [String]
    var manufacturerDataHex: String?
    var txPowerLevel: Int?
    var isConnectable: Bool?

    init(
        localName: String? = nil,
        serviceUUIDs: [String] = [],
        overflowServiceUUIDs: [String] = [],
        manufacturerDataHex: String? = nil,
        txPowerLevel: Int? = nil,
        isConnectable: Bool? = nil
    ) {
        self.localName = localName
        self.serviceUUIDs = serviceUUIDs
        self.overflowServiceUUIDs = overflowServiceUUIDs
        self.manufacturerDataHex = manufacturerDataHex
        self.txPowerLevel = txPowerLevel
        self.isConnectable = isConnectable
    }

    init(advertisementData: [String: Any]) {
        localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        overflowServiceUUIDs = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        txPowerLevel = (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue

        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            manufacturerDataHex = manufacturerData.map { String(format: "%02x", $0) }.joined()
        } else {
            manufacturerDataHex = nil
        }
    }

    var displayText: String {
        var parts: [String] = []
        if let localName, !localName.isEmpty {
            parts.append(localName)
        }
        if !serviceUUIDs.isEmpty {
            parts.append("services \(serviceUUIDs.prefix(3).joined(separator: ", "))")
        }
        if let manufacturerDataHex {
            parts.append("mfg \(manufacturerDataHex.prefix(12))")
        }
        if let isConnectable {
            parts.append(isConnectable ? "connectable" : "not connectable")
        }
        return parts.isEmpty ? "No advertisement details" : parts.joined(separator: " • ")
    }
}
