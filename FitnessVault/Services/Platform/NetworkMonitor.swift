import Foundation
import Network
import Observation

@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async { self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }

    deinit { monitor.cancel() }
}
