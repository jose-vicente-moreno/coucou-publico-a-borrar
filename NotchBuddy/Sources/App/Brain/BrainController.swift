#if !APPSTORE
import Foundation
import Combine

// MARK: - Brain Controller

/// The counters and local services the brain's `.coucou/brain.json` declares. Read
/// every 60 s and on demand, only while the Brain pill is on: no timer, no disk and
/// no network otherwise. The config is read again each time, so an edit shows up
/// without a restart. The folder scan and the probes run off the main actor.
@MainActor
final class BrainController: ObservableObject {
    static let shared = BrainController()
    nonisolated static let pillId = "integration_brain"

    private nonisolated static let logFile = "brain.log"
    private nonisolated static let pollInterval: TimeInterval = 60
    private nonisolated static let probeTimeout: TimeInterval = 2

    /// Local services only, never through a proxy, never waiting for a network.
    private nonisolated static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = probeTimeout
        config.timeoutIntervalForResource = probeTimeout
        config.waitsForConnectivity = false
        config.connectionProxyDictionary = [:]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    @Published private(set) var status = BrainStatus()
    /// The config problem logged last: a broken file is logged once, not every read.
    private var loggedConfigError: BrainConfigError?

    private var timer: Timer?
    private var reading = false
    /// pollNow() came while a read was running: read again right after.
    private var readAgain = false
    private var cancellables = Set<AnyCancellable>()

    private var isPillActive: Bool {
        AppState.shared.activeIntegrations.contains(Self.pillId)
    }

    /// The brain folder from Settings → Chat, when it is set and exists.
    var vaultURL: URL? { BrainVault.url(path: AppState.shared.brainVaultPath) }

    private init() {
        AppState.shared.$activeIntegrations
            .map { $0.contains(Self.pillId) }
            .removeDuplicates()
            .sink { [weak self] _ in
                // The sink runs before the property changes: decide on the next turn.
                DispatchQueue.main.async { self?.updatePolling() }
            }
            .store(in: &cancellables)
        AppState.shared.$brainVaultPath
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.pollNow() }
            }
            .store(in: &cancellables)
    }

    func start() { updatePolling() }

    private func updatePolling() {
        if isPillActive {
            if timer == nil {
                let t = Timer(timeInterval: Self.pollInterval, repeats: true) { _ in
                    MainActor.assumeIsolated { BrainController.shared.pollNow() }
                }
                t.tolerance = 10
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
            pollNow()
        } else {
            timer?.invalidate()
            timer = nil
            status = BrainStatus()
        }
    }

    func refreshIfStale(minAge: TimeInterval = 20) {
        guard Date().timeIntervalSince(status.lastUpdated ?? .distantPast) > minAge else { return }
        pollNow()
    }

    /// Reads the vault and probes the services now (pill on only).
    func pollNow() {
        guard isPillActive else { return }
        guard !reading else { readAgain = true; return }
        reading = true
        let vault = vaultURL
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task {
            let fresh = await Self.read(vault: vault, home: home)
            reading = false
            logConfigError(fresh.configError)
            if isPillActive, fresh.status != status { status = fresh.status }
            if readAgain {
                readAgain = false
                pollNow()
            }
        }
    }

    private func logConfigError(_ error: BrainConfigError?) {
        guard error != loggedConfigError else { return }
        loggedConfigError = error
        if let error { appendAppLog(Self.logFile, error.localizedDescription) }
    }

    private nonisolated static func read(vault: URL?, home: URL) async
        -> (status: BrainStatus, configError: BrainConfigError?) {
        let scanned = await Task.detached(priority: .utility) { () -> (BrainStatus, BrainConfigError?) in
            guard let vault else { return (BrainStatusScanner.scan(vault: nil, config: .default, home: home), nil) }
            switch BrainConfig.read(vault: vault) {
            case .success(let config):
                return (BrainStatusScanner.scan(vault: vault, config: config, home: home), nil)
            case .failure(let error):
                return (BrainStatusScanner.scan(vault: vault, config: .default, home: home), error)
            }
        }.value
        var status = scanned.0
        status.services = await probe(status.services)
        return (status, scanned.1)
    }

    /// Every service with a health URL, probed at once.
    private nonisolated static func probe(_ services: [BrainStatus.Service]) async -> [BrainStatus.Service] {
        await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, service) in services.enumerated() {
                guard let health = service.health else { continue }
                group.addTask { (index, await isUp(health)) }
            }
            var probed = services
            for await (index, up) in group { probed[index].up = up }
            return probed
        }
    }

    private nonisolated static func isUp(_ url: URL) async -> Bool {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: probeTimeout)
        guard let (_, response) = try? await probeSession.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
#endif
