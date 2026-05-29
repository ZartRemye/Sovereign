import Foundation

/// Manages sync session state with iPhone/Watch.
/// Reserved for future MultipeerConnectivity / iCloud sync integration.
actor SyncSessionManager {
    static let shared = SyncSessionManager()

    enum ConnectionState {
        case disconnected
        case connecting
        case connected(deviceName: String)
        case error(String)
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var connectedDeviceName: String?
    private(set) var lastSuccessfulSync: Date?

    private var syncEnabled = false

    private init() {}

    // MARK: - Connection Management (stubs)

    func startAdvertising() {
        // Future: MultipeerConnectivity advertising
        connectionState = .connecting
    }

    func stopAdvertising() {
        connectionState = .disconnected
    }

    func startBrowsing() {
        // Future: MultipeerConnectivity browsing
        connectionState = .connecting
    }

    func stopBrowsing() {
        connectionState = .disconnected
    }

    // MARK: - Status

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var connectionSummary: String {
        switch connectionState {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "连接中..."
        case .connected(let name):
            return "已连接 \(name)"
        case .error(let msg):
            return "错误: \(msg)"
        }
    }

    func recordSuccessfulSync(deviceName: String) {
        connectedDeviceName = deviceName
        lastSuccessfulSync = Date()
        connectionState = .connected(deviceName: deviceName)
    }

    func setError(_ message: String) {
        connectionState = .error(message)
    }
}
