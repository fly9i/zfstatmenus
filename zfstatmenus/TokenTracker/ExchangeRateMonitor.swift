import Combine
import Foundation

// 自动获取 USD→CNY 汇率：启动后拉取一次，之后每 6 小时刷新。
// 仅在「自动获取汇率」开启时生效；获取失败保留上次成功值，不会清空。
// 结果直接写入 AppPreferences.tokenUSDToCNYRate，费用显示无需改动即生效。
final class ExchangeRateMonitor: ObservableObject {
    static let shared = ExchangeRateMonitor()

    @Published private(set) var isFetching = false
    @Published private(set) var lastError: String?

    private let queue = DispatchQueue(label: "com.zfstat.exchange-rate", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var started = false
    private var inFlight = false

    private static let refreshInterval: TimeInterval = 6 * 3600

    func start() {
        guard !started else { return }
        started = true
        queue.async { [weak self] in self?.refreshIfStale(force: false) }

        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + Self.refreshInterval, repeating: Self.refreshInterval)
        newTimer.setEventHandler { [weak self] in
            self?.queue.async { self?.refreshIfStale(force: false) }
        }
        newTimer.resume()
        timer = newTimer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        started = false
    }

    // 设置页手动刷新或开启自动获取时调用，忽略过期判断。
    func refresh() {
        queue.async { [weak self] in self?.refreshIfStale(force: true) }
    }

    private func refreshIfStale(force: Bool) {
        guard AppPreferences.shared.tokenRateAutoEnabled else { return }
        let lastUpdatedAt = AppPreferences.shared.tokenRateUpdatedAt
        if !force, lastUpdatedAt > 0,
           Date().timeIntervalSince1970 - lastUpdatedAt < Self.refreshInterval { return }
        guard !inFlight else { return }
        inFlight = true
        DispatchQueue.main.async { [weak self] in self?.isFetching = true }

        Task {
            let result = await ExchangeRateFetcher.fetchUSDToCNY()
            self.queue.async { [weak self] in
                guard let self else { return }
                inFlight = false
                switch result {
                case .success(let rate):
                    AppPreferences.shared.tokenUSDToCNYRate = rate
                    AppPreferences.shared.tokenRateUpdatedAt = Date().timeIntervalSince1970
                    DispatchQueue.main.async { [weak self] in
                        self?.isFetching = false
                        self?.lastError = nil
                    }
                case .failure(let error):
                    AppLog.general.error("Exchange rate fetch failed: \(error.localizedDescription)")
                    DispatchQueue.main.async { [weak self] in
                        self?.isFetching = false
                        self?.lastError = error.localizedDescription
                    }
                }
            }
        }
    }
}

enum ExchangeRateFetcher {
    private static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!

    static func fetchUSDToCNY() async -> Result<Double, Error> {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("ZFStatMenus/\(appVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                return .failure(ExchangeRateError.unavailable)
            }
            let decoded = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            guard decoded.result == "success",
                  let cny = decoded.rates["CNY"],
                  (1...20).contains(cny) else {
                return .failure(ExchangeRateError.unavailable)
            }
            return .success(cny)
        } catch {
            return .failure(ExchangeRateError.unavailable)
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

private struct ExchangeRateResponse: Decodable {
    let result: String
    let rates: [String: Double]
}

private enum ExchangeRateError: LocalizedError {
    case unavailable

    var errorDescription: String? { "无法获取汇率" }
}
