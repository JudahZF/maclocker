import Foundation

struct WatchSignalEvent: Equatable {
    var peripheralID: UUID
    var rssi: Int
    var timestamp: Date
}
