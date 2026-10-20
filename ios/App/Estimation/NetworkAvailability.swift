import Foundation
import Network
import Observation

@MainActor @Observable final class NetworkAvailability {
    private(set) var isOnline = false
    private let monitor = NWPathMonitor()
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-offline") { return }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "com.boji.network-status"))
    }
    deinit { monitor.cancel() }
}
