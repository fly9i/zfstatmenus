import AppKit
import Combine

final class AppCoordinator {

    private let monitorManager = MonitorManager()
    private let tokenUsageMonitor = TokenUsageMonitor.shared
    private let providerQuotaMonitor = ProviderQuotaMonitor.shared
    private let exchangeRateMonitor = ExchangeRateMonitor.shared
    private lazy var statusBarController = StatusBarController(
        monitorManager: monitorManager,
        tokenUsageMonitor: tokenUsageMonitor
    )
    private let prefs = AppPreferences.shared
    private var activeMonitorInterval: TimeInterval?

    func start() {
        monitorManager.onCPUUpdate = { [weak self] metric in
            self?.statusBarController.updateCPU(metric)
        }
        monitorManager.onMemoryUpdate = { [weak self] metric in
            self?.statusBarController.updateMemory(metric)
        }
        monitorManager.onNetworkUpdate = { [weak self] metric in
            self?.statusBarController.updateNetwork(metric)
        }
        tokenUsageMonitor.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.statusBarController.updateToken(snapshot)
            }
            .store(in: &subscriptions)
        statusBarController.setup()
        let monitorInterval = prefs.monitorInterval
        activeMonitorInterval = monitorInterval
        monitorManager.start(interval: monitorInterval)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let interval = self.prefs.monitorInterval
                guard interval != self.activeMonitorInterval else { return }
                self.activeMonitorInterval = interval
                self.monitorManager.updateInterval(interval)
            }
            .store(in: &subscriptions)
        tokenUsageMonitor.start(interval: prefs.tokenRefreshInterval)
        providerQuotaMonitor.start()
        exchangeRateMonitor.start()

        AppLog.general.info("AppCoordinator started")
    }

    func stop() {
        monitorManager.stop()
        tokenUsageMonitor.stop()
        providerQuotaMonitor.stop()
        exchangeRateMonitor.stop()
    }

    private var subscriptions: Set<AnyCancellable> = []

}
