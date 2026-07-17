import Foundation

// 订阅额度（5 小时窗 + 每周窗）数据模型，以及四家平台配额接口的纯解析函数。
// 解析函数只依赖输入的响应 Data，便于单元测试。

enum QuotaProvider: String, CaseIterable, Codable, Hashable {
    case kimi
    case codex
    case claude
    case glm

    var displayName: String {
        switch self {
        case .kimi: return "Kimi"
        case .codex: return "GPT"
        case .claude: return "Claude"
        case .glm: return "GLM"
        }
    }

    var planName: String {
        switch self {
        case .kimi: return "Kimi For Coding"
        case .codex: return "Codex 订阅"
        case .claude: return "Claude 订阅"
        case .glm: return "智谱 Coding Plan"
        }
    }

    var iconAssetName: String {
        switch self {
        case .kimi: return "ProviderKimi"
        case .codex: return "ProviderGPT"
        case .claude: return "ProviderClaude"
        case .glm: return "ProviderGLM"
        }
    }
}

struct QuotaWindow: Equatable {
    var usedPercent: Double // 已用百分比，0~100
    var used: Int64?
    var limit: Int64?
    var resetsAt: Date?
}

enum QuotaRemainingLevel: Equatable {
    case empty
    case critical
    case low
    case medium
    case high
}

func quotaRemainingLevel(for percent: Double) -> QuotaRemainingLevel {
    switch min(max(percent, 0), 100) {
    case 0:
        return .empty
    case ..<25:
        return .critical
    case ..<50:
        return .low
    case ..<75:
        return .medium
    default:
        return .high
    }
}

struct ProviderQuota: Equatable {
    var fiveHour: QuotaWindow?
    var weekly: QuotaWindow?
    var errorMessage: String?
    var updatedAt: Date

    init(
        fiveHour: QuotaWindow? = nil,
        weekly: QuotaWindow? = nil,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }

    static func failure(_ message: String) -> ProviderQuota {
        ProviderQuota(errorMessage: message)
    }
}

enum ProviderQuotaParseError: LocalizedError {
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message): return message
        }
    }
}

enum ProviderQuotaParser {
    // MARK: Claude

    // GET https://api.anthropic.com/api/oauth/usage
    static func parseClaude(_ data: Data) throws -> ProviderQuota {
        let object = try jsonObject(data)
        var quota = ProviderQuota()
        quota.fiveHour = claudeWindow(object["five_hour"])
        quota.weekly = claudeWindow(object["seven_day"])
        guard quota.fiveHour != nil || quota.weekly != nil else {
            throw ProviderQuotaParseError.invalidResponse("Claude 响应缺少额度窗口")
        }
        return quota
    }

    private static func claudeWindow(_ value: Any?) -> QuotaWindow? {
        guard let dict = value as? [String: Any],
              let raw = dict["utilization"] as? NSNumber else { return nil }
        return QuotaWindow(
            usedPercent: raw.doubleValue,
            resetsAt: (dict["resets_at"] as? String).flatMap(parseQuotaTimestamp)
        )
    }

    // MARK: Codex

    // GET https://chatgpt.com/backend-api/wham/usage
    static func parseCodex(_ data: Data) throws -> ProviderQuota {
        let object = try jsonObject(data)
        guard let rateLimit = object["rate_limit"] as? [String: Any] else {
            throw ProviderQuotaParseError.invalidResponse("Codex 响应缺少 rate_limit")
        }
        var quota = ProviderQuota()
        for (key, isPrimary) in [("primary_window", true), ("secondary_window", false)] {
            guard let window = rateLimit[key] as? [String: Any] else { continue }
            let parsed = codexWindow(window)
            switch (window["limit_window_seconds"] as? NSNumber)?.intValue {
            case 18_000: quota.fiveHour = parsed
            case 604_800: quota.weekly = parsed
            default:
                // 窗口时长未识别时按 primary/secondary 角色兜底
                if isPrimary, quota.fiveHour == nil { quota.fiveHour = parsed }
                if !isPrimary, quota.weekly == nil { quota.weekly = parsed }
            }
        }
        guard quota.fiveHour != nil || quota.weekly != nil else {
            throw ProviderQuotaParseError.invalidResponse("Codex 响应缺少额度窗口")
        }
        return quota
    }

    private static func codexWindow(_ dict: [String: Any]) -> QuotaWindow {
        let percent = (dict["used_percent"] as? NSNumber)?.doubleValue ?? 0
        let resetsAt = (dict["reset_at"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        return QuotaWindow(usedPercent: percent, resetsAt: resetsAt)
    }

    // MARK: Kimi

    // GET https://api.kimi.com/coding/v1/usages（与 Kimi CLI /usage 同一实现）
    static func parseKimi(_ data: Data) throws -> ProviderQuota {
        let object = try jsonObject(data)
        var quota = ProviderQuota()
        // 顶层 usage 即每周额度
        quota.weekly = (object["usage"] as? [String: Any]).flatMap(kimiWindow)
        if let limits = object["limits"] as? [[String: Any]], !limits.isEmpty {
            // 300 分钟窗口为 5 小时额度；找不到时回退第一项
            let fiveHourItem = limits.first(where: {
                guard let window = $0["window"] as? [String: Any] else { return false }
                return int64Value(window["duration"]) == 300
                    && ((window["timeUnit"] as? String) ?? "").contains("MINUTE")
            }) ?? limits[0]
            quota.fiveHour = kimiWindow(fiveHourItem)
        }
        guard quota.fiveHour != nil || quota.weekly != nil else {
            throw ProviderQuotaParseError.invalidResponse("Kimi 响应缺少额度窗口")
        }
        return quota
    }

    // 额度数值在 detail 子对象里；没有 detail 则直接在条目上。完全无数值时返回 nil（视为缺失而非 0%）
    private static func kimiWindow(_ item: [String: Any]) -> QuotaWindow? {
        let detail = (item["detail"] as? [String: Any]) ?? item
        let limit = int64Value(detail["limit"])
        var used = int64Value(detail["used"])
        if used == nil, let limit, let remaining = int64Value(detail["remaining"]) {
            used = max(0, limit - remaining)
        }
        guard used != nil || limit != nil else { return nil }
        var percent = 0.0
        if let limit, limit > 0, let used {
            percent = Double(used) / Double(limit) * 100
        }
        return QuotaWindow(
            usedPercent: percent,
            used: used,
            limit: limit,
            resetsAt: kimiResetDate(detail)
        )
    }

    // 重置时间字段名兼容：reset_at / resetAt / reset_time / resetTime
    private static func kimiResetDate(_ dict: [String: Any]) -> Date? {
        for key in ["reset_at", "resetAt", "reset_time", "resetTime"] {
            if let raw = dict[key] as? String, let date = parseQuotaTimestamp(raw) {
                return date
            }
        }
        return nil
    }

    // MARK: GLM

    // GET <host>/api/monitor/usage/quota/limit
    static func parseGLM(_ data: Data) throws -> ProviderQuota {
        let object = try jsonObject(data)
        if let code = (object["code"] as? NSNumber)?.intValue, code != 200 {
            let message = object["msg"] as? String ?? "GLM 接口返回错误（code \(code)）"
            throw ProviderQuotaParseError.invalidResponse(message)
        }
        guard let dataObject = object["data"] as? [String: Any],
              let limits = dataObject["limits"] as? [[String: Any]] else {
            throw ProviderQuotaParseError.invalidResponse("GLM 响应缺少 limits")
        }
        // TOKENS_LIMIT 按重置时间升序，最近重置的是 5 小时窗，其次是每周窗；TIME_LIMIT 是 MCP 月额度，不展示。
        let tokenLimits = limits
            .filter { $0["type"] as? String == "TOKENS_LIMIT" }
            .sorted { glmResetMillis($0) < glmResetMillis($1) }
        var quota = ProviderQuota()
        if tokenLimits.count > 0 { quota.fiveHour = glmWindow(tokenLimits[0]) }
        if tokenLimits.count > 1 { quota.weekly = glmWindow(tokenLimits[1]) }
        guard quota.fiveHour != nil || quota.weekly != nil else {
            throw ProviderQuotaParseError.invalidResponse("GLM 响应缺少 TOKENS_LIMIT 额度")
        }
        return quota
    }

    private static func glmWindow(_ dict: [String: Any]) -> QuotaWindow {
        let percent = (dict["percentage"] as? NSNumber)?.doubleValue ?? 0
        let resetsAt = (dict["nextResetTime"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1_000) }
        return QuotaWindow(
            usedPercent: percent,
            used: int64Value(dict["currentValue"]),
            limit: int64Value(dict["usage"]),
            resetsAt: resetsAt
        )
    }

    private static func glmResetMillis(_ dict: [String: Any]) -> Int64 {
        int64Value(dict["nextResetTime"]) ?? Int64.max
    }

    // MARK: 共用辅助

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            throw ProviderQuotaParseError.invalidResponse("无法解析响应 JSON")
        }
        return dict
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}

// 解析 ISO8601 时间串。Kimi 的 resetTime 带 9 位纳秒小数，
// Foundation 的 ISO8601DateFormatter 无法直接解析，先把小数秒截断到 6 位。
func parseQuotaTimestamp(_ raw: String) -> Date? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let dot = text.firstIndex(of: ".") {
        let fractionStart = text.index(after: dot)
        var end = fractionStart
        var keptEnd = fractionStart
        var digitCount = 0
        while end < text.endIndex, text[end].isNumber {
            if digitCount < 6 { keptEnd = text.index(after: end) }
            digitCount += 1
            end = text.index(after: end)
        }
        if digitCount == 0 {
            text.removeSubrange(dot..<fractionStart)
        } else {
            text.removeSubrange(keptEnd..<end)
        }
    }
    return quotaFractionalISO8601Formatter.date(from: text) ?? quotaISO8601Formatter.date(from: text)
}

private let quotaFractionalISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let quotaISO8601Formatter = ISO8601DateFormatter()
