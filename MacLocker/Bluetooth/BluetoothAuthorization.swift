@preconcurrency import CoreBluetooth
import Foundation

enum BluetoothAuthorizationStatus: String, Equatable {
    case allowed
    case denied
    case restricted
    case notDetermined
    case unknown

    var displayText: String {
        switch self {
        case .allowed:
            "Bluetooth authorized"
        case .denied:
            "Bluetooth denied"
        case .restricted:
            "Bluetooth restricted"
        case .notDetermined:
            "Bluetooth permission not determined"
        case .unknown:
            "Bluetooth authorization unknown"
        }
    }
}

enum BluetoothAuthorization {
    static var current: BluetoothAuthorizationStatus {
        switch CBManager.authorization {
        case .allowedAlways:
            .allowed
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .unknown
        }
    }
}
