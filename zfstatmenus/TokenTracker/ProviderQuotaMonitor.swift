import Combine
import Foundation
import Security

// 订阅额度采集：后台每 5 分钟刷新一次；Token 弹窗打开时若数据过期（>60 秒）也会触发刷新。
// 凭据读取与网络请求都在后台队列完成，结果回主线程发布。
// 只有「已启用且检测到凭据」的提供方会出现在 quotas 中；查询失败的保留错误文案，不静默消失。
final class ProviderQuotaMonitor: ObservableObject, @unchecked Sendable {
    static let shared = ProviderQuotaMonitor()

    @Published private(set) var quotas: [QuotaProvider: ProviderQuota] = [:]
    @Published private(set) var isRefreshing = false

    private let queue = DispatchQueue(label: "com.zfstat.provider-quota", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var started = false
    private var refreshInFlight = false
    private var refreshQueued = false
    private var lastRefreshAt: Date?

    private static let refreshInterval: TimeInterval = 300 // 后台定时刷新：5 分钟
    private static let staleThreshold: TimeInterval = 60   // 弹窗打开时的过期阈值：60 秒

    func start() {
        guard !started else { return }
        started = true
        refresh()

        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + Self.refreshInterval, repeating: Self.refreshInterval)
        newTimer.setEventHandler { [weak self] in
            self?.collectAll()
        }
        newTimer.resume()
        timer = newTimer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        started = false
    }

    func refresh() {
        queue.async { [weak self] in
            self?.collectAll()
        }
    }

    // Token 弹窗打开时调用，仅在数据过期时重新请求
    func refreshIfStale() {
        queue.async { [weak self] in
            guard let self else { return }
            if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < Self.staleThreshold { return }
            collectAll()
        }
    }

    private func collectAll() {
        // 凭据变更等触发的刷新若撞上在途请求（那轮读的可能是旧凭据），排队重跑而不是丢弃
        guard !refreshInFlight else {
            refreshQueued = true
            return
        }
        refreshInFlight = true
        lastRefreshAt = Date()
        DispatchQueue.main.async { [weak self] in self?.isRefreshing = true }

        let enabled = AppPreferences.shared.enabledQuotaProviders
        Task {
            var results: [QuotaProvider: ProviderQuota] = [:]
            await withTaskGroup(of: (QuotaProvider, ProviderQuota?).self) { group in
                for provider in QuotaProvider.allCases where enabled.contains(provider) {
                    group.addTask {
                        (provider, await ProviderQuotaFetcher.fetch(provider))
                    }
                }
                for await (provider, quota) in group {
                    if let quota {
                        results[provider] = quota
                    }
                }
            }
            self.queue.async { [weak self] in
                guard let self else { return }
                refreshInFlight = false
                if refreshQueued {
                    refreshQueued = false
                    collectAll()
                } else {
                    DispatchQueue.main.async { [weak self] in self?.isRefreshing = false }
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.quotas = results
            }
        }
    }
}

// MARK: - 凭据 Keychain 存取

// GLM API Key 由用户在设置页粘贴，明文只保存于本机 Keychain。
enum ProviderQuotaKeychain {
    private static let service = "com.zfstat.ZFStatMenus.provider-quota"
    private static let glmAccount = "glm-api-key"

    static var hasGLMAPIKey: Bool {
        guard let key = glmAPIKey() else { return false }
        return !key.isEmpty
    }

    static func glmAPIKey() -> String? {
        KeychainStore.loadToken(service: service, account: glmAccount)
    }

    static func saveGLMAPIKey(_ key: String) throws {
        try save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: glmAccount)
    }

    private static func save(_ value: String, account: String) throws {
        if value.isEmpty {
            try KeychainStore.deleteToken(service: service, account: account)
        } else {
            try KeychainStore.saveToken(value, service: service, account: account)
        }
    }
}

// MARK: - Kimi CLI 凭据

// Kimi CLI 登录后保存在 ~/.kimi-code/credentials/ 下的访问凭据。
struct KimiCLICredential: Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let expiresIn: TimeInterval?
    let scope: String?
    let tokenType: String?

    // 提前少量刷新，避免额度请求期间令牌刚好过期
    func isExpired(at now: Date = Date(), leeway: TimeInterval = 0) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(leeway)
    }
}

// 解析 Kimi CLI 凭据文件内容（纯函数，与文件 IO 分离）。
// 缺少非空 access_token 或 JSON 损坏时返回 nil。
func parseKimiCLICredential(_ data: Data) -> KimiCLICredential? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = object["access_token"] as? String,
          !token.isEmpty else { return nil }
    return KimiCLICredential(
        accessToken: token,
        refreshToken: nonEmptyString(object["refresh_token"]),
        expiresAt: kimiCLIExpiryDate(object["expires_at"]),
        expiresIn: positiveNumber(object["expires_in"]),
        scope: nonEmptyString(object["scope"]),
        tokenType: nonEmptyString(object["token_type"])
    )
}

// 解析 Kimi OAuth 刷新响应，并以本机时间计算新的 expires_at。
func parseKimiCLIRefreshResponse(
    _ data: Data,
    now: Date = Date()
) -> KimiCLICredential? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let accessToken = nonEmptyString(object["access_token"]),
          let refreshToken = nonEmptyString(object["refresh_token"]),
          let expiresIn = positiveNumber(object["expires_in"]) else { return nil }
    return KimiCLICredential(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: now.addingTimeInterval(expiresIn),
        expiresIn: expiresIn,
        scope: nonEmptyString(object["scope"]),
        tokenType: nonEmptyString(object["token_type"]) ?? "Bearer"
    )
}

private func nonEmptyString(_ value: Any?) -> String? {
    guard let value = value as? String, !value.isEmpty else { return nil }
    return value
}

private func positiveNumber(_ value: Any?) -> Double? {
    let number: Double?
    if let value = value as? NSNumber {
        number = value.doubleValue
    } else if let value = value as? String {
        number = Double(value)
    } else {
        number = nil
    }
    guard let number, number > 0 else { return nil }
    return number
}

// expires_at 单位防御：大于 1e12 视为毫秒，否则视为秒
private func kimiCLIExpiryDate(_ value: Any?) -> Date? {
    let raw: Double?
    if let number = value as? NSNumber {
        raw = number.doubleValue
    } else if let string = value as? String {
        raw = Double(string)
    } else {
        raw = nil
    }
    guard let seconds = raw, seconds > 0 else { return nil }
    return Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1_000 : seconds)
}

// MARK: - 凭据检测与网络请求

enum ProviderQuotaError: LocalizedError {
    case unauthorized
    case http(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "凭据无效或已过期"
        case .http(let code): return "接口返回 HTTP \(code)"
        case .network(let message): return message
        }
    }
}

enum ProviderQuotaFetcher {
    private struct KimiCredentialFile {
        let url: URL
        let credential: KimiCLICredential
    }

    // 返回 nil 表示未配置或检测不到凭据（弹窗不展示该卡片）
    static func fetch(_ provider: QuotaProvider) async -> ProviderQuota? {
        switch provider {
        case .kimi: return await fetchKimi()
        case .codex: return await fetchCodex()
        case .claude: return await fetchClaude()
        case .glm: return await fetchGLM()
        }
    }

    // 设置页展示的本机凭据检测状态；只做存在性检查，不读取凭据内容
    static func credentialStatus(for provider: QuotaProvider) -> String {
        switch provider {
        case .kimi:
            if let credential = loadKimiCLICredential() {
                if credential.isExpired(), credential.refreshToken != nil {
                    return "已检测到 Kimi CLI 凭据（过期时自动刷新）"
                }
                return credential.isExpired() ? "Kimi CLI 凭据已过期" : "已检测到 Kimi CLI 凭据"
            }
            return "未检测到 Kimi CLI 凭据，请先在终端登录 Kimi CLI"
        case .glm:
            return ProviderQuotaKeychain.hasGLMAPIKey ? "已在 Keychain 保存 API Key" : "未配置 API Key"
        case .claude:
            if claudeKeychainItemExists() {
                return "已检测到 Keychain 凭据（Claude Code-credentials）"
            }
            if FileManager.default.fileExists(atPath: claudeCredentialsFileURL.path) {
                return "已检测到 ~/.claude/.credentials.json"
            }
            return "未检测到凭据，请先在终端登录 Claude Code"
        case .codex:
            if FileManager.default.fileExists(atPath: codexAuthFileURL.path) {
                return "已检测到 ~/.codex/auth.json"
            }
            return "未检测到 ~/.codex/auth.json"
        }
    }

    // MARK: Kimi

    private static func fetchKimi() async -> ProviderQuota? {
        // 凭据只用 Kimi CLI 本地凭据；检测不到则返回 nil（不展示卡片）
        guard let credentialFile = loadKimiCLICredentialFile() else { return nil }
        var credential = credentialFile.credential
        if credential.isExpired(leeway: 30) {
            guard let refreshToken = credential.refreshToken else {
                return .failure("Kimi CLI 登录已过期且无法自动刷新，请在终端运行一次 kimi")
            }
            do {
                credential = try await refreshKimiCredential(refreshToken: refreshToken)
                try saveKimiCLICredential(credential, to: credentialFile.url)
            } catch {
                return .failure(errorMessage(
                    error,
                    authHint: "Kimi CLI 自动刷新失败，请在终端运行一次 kimi（必要时 /login）"
                ))
            }
        }
        // 与 Kimi CLI /usage 同一实现：GET {base}/usages，base 固定为官方默认值
        guard let url = URL(string: "https://api.kimi.com/coding/v1/usages") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let data = try await send(request)
            return try ProviderQuotaParser.parseKimi(data)
        } catch {
            return .failure(errorMessage(error, authHint: "Kimi CLI 凭据已失效，请在终端运行一次 kimi（必要时 /login）"))
        }
    }

    private static func refreshKimiCredential(refreshToken: String) async throws -> KimiCLICredential {
        let oauthHost = ProcessInfo.processInfo.environment["KIMI_CODE_OAUTH_HOST"]
            ?? ProcessInfo.processInfo.environment["KIMI_OAUTH_HOST"]
            ?? "https://auth.kimi.com"
        guard let url = URL(string: oauthHost.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/oauth/token") else {
            throw ProviderQuotaError.network("Kimi OAuth 地址无效")
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: "17e5f671-d194-4dfb-9706-5516cb48c098"),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        guard let credential = parseKimiCLIRefreshResponse(data) else {
            throw ProviderQuotaError.network("Kimi OAuth 刷新响应异常")
        }
        return credential
    }

    private static func saveKimiCLICredential(_ credential: KimiCLICredential, to url: URL) throws {
        var object: [String: Any] = [
            "access_token": credential.accessToken,
            "expires_at": Int(credential.expiresAt?.timeIntervalSince1970 ?? 0),
            "token_type": credential.tokenType ?? "Bearer",
        ]
        if let refreshToken = credential.refreshToken { object["refresh_token"] = refreshToken }
        if let expiresIn = credential.expiresIn { object["expires_in"] = Int(expiresIn) }
        if let scope = credential.scope { object["scope"] = scope }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // credentials 目录：KIMI_CODE_HOME 存在时以其为根目录，否则 ~/.kimi-code
    private static var kimiCredentialsDirectoryURL: URL {
        if let home = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("credentials")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kimi-code/credentials")
    }

    // 扫描 credentials 目录下的 *.json（目录列举不递归，mcp/ 等子目录天然跳过），
    // 返回第一个含非空 access_token 的凭据
    private static func loadKimiCLICredential() -> KimiCLICredential? {
        loadKimiCLICredentialFile()?.credential
    }

    private static func loadKimiCLICredentialFile() -> KimiCredentialFile? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: kimiCredentialsDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for fileURL in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where fileURL.pathExtension == "json" {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: fileURL),
                  let credential = parseKimiCLICredential(data) else { continue }
            return KimiCredentialFile(url: fileURL, credential: credential)
        }
        return nil
    }

    // MARK: Codex

    private static var codexAuthFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    private static func fetchCodex() async -> ProviderQuota? {
        guard let data = try? Data(contentsOf: codexAuthFileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty else { return nil }

        // access_token 是 JWT；本地先判过期，本版本不做刷新流程
        if let expiry = jwtExpiry(accessToken), expiry <= Date() {
            return .failure("Codex 登录已过期，请在终端运行一次 codex")
        }

        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = tokens["account_id"] as? String, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        do {
            let data = try await send(request)
            return try ProviderQuotaParser.parseCodex(data)
        } catch {
            return .failure(errorMessage(error, authHint: "Codex 登录已过期，请在终端运行一次 codex"))
        }
    }

    private static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !base64.count.isMultiple(of: 4) { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: Claude

    private static var claudeCredentialsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
    }

    private static func fetchClaude() async -> ProviderQuota? {
        guard let accessToken = claudeAccessToken() else { return nil }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            let data = try await send(request)
            return try ProviderQuotaParser.parseClaude(data)
        } catch {
            return .failure(errorMessage(error, authHint: "Claude 凭据已失效，请在终端重新登录 Claude Code"))
        }
    }

    // 凭据优先级：① Keychain（service: Claude Code-credentials）② ~/.claude/.credentials.json
    // 注意：读取 Keychain 数据会触发一次系统授权弹窗，属预期行为。
    private static func claudeAccessToken() -> String? {
        if let json = readClaudeKeychain(),
           let token = parseClaudeAccessToken(json) {
            return token
        }
        if let data = try? Data(contentsOf: claudeCredentialsFileURL) {
            return parseClaudeAccessToken(data)
        }
        return nil
    }

    private static func parseClaudeAccessToken(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }
        return token
    }

    private static func readClaudeKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    // 仅检查存在性（不取回数据），避免设置页检测时触发授权弹窗
    private static func claudeKeychainItemExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: GLM

    private static func fetchGLM() async -> ProviderQuota? {
        guard let key = ProviderQuotaKeychain.glmAPIKey(), !key.isEmpty else { return nil }
        let host = AppPreferences.shared.glmAPIRegion == "global"
            ? "https://api.z.ai"
            : "https://open.bigmodel.cn"
        guard let url = URL(string: "\(host)/api/monitor/usage/quota/limit") else { return nil }
        do {
            let data = try await sendGLM(url: url, apiKey: key)
            return try ProviderQuotaParser.parseGLM(data)
        } catch {
            return .failure(errorMessage(error, authHint: "GLM API Key 无效，请在设置中更新"))
        }
    }

    private static func sendGLM(url: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            return try await send(request)
        } catch ProviderQuotaError.unauthorized {
            // 官方客户端两种 Authorization 形式都存在，Bearer 被拒时用裸 Key 兜底重试
            var plainRequest = URLRequest(url: url)
            plainRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")
            return try await send(plainRequest)
        }
    }

    // MARK: 共用

    private static func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 15
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw ProviderQuotaError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderQuotaError.network("服务器响应无效")
        }
        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw ProviderQuotaError.unauthorized
        default:
            throw ProviderQuotaError.http(httpResponse.statusCode)
        }
    }

    private static func errorMessage(_ error: Error, authHint: String) -> String {
        if let quotaError = error as? ProviderQuotaError {
            switch quotaError {
            case .unauthorized:
                return authHint
            case .http(let code):
                return "查询失败：接口返回 HTTP \(code)"
            case .network(let message):
                return "网络错误：\(message)"
            }
        }
        if let parseError = error as? ProviderQuotaParseError {
            return "响应异常：\(parseError.localizedDescription)"
        }
        return "查询失败：\(error.localizedDescription)"
    }
}
