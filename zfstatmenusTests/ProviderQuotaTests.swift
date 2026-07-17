import XCTest
@testable import ZFStatMenus

final class ProviderQuotaTests: XCTestCase {
    // MARK: - Claude

    func testClaudeParsesFractionalUtilization() throws {
        let json = """
        {"five_hour": {"utilization": 0.42, "resets_at": "2026-07-17T13:00:00.000Z"},
         "seven_day": {"utilization": 0.12, "resets_at": "2026-07-24T00:00:00.000Z"}}
        """
        let quota = try ProviderQuotaParser.parseClaude(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 42, accuracy: 0.001)
        XCTAssertEqual(quota.weekly?.usedPercent ?? -1, 12, accuracy: 0.001)
        XCTAssertEqual(
            quota.fiveHour?.resetsAt?.timeIntervalSince1970 ?? 0,
            utcDate(2026, 7, 17, 13, 0).timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            quota.weekly?.resetsAt?.timeIntervalSince1970 ?? 0,
            utcDate(2026, 7, 24, 0, 0).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testClaudeParsesPercentFormUtilization() throws {
        // utilization > 1 视为百分数；恰好 1 按 0~1 小数处理（即 100%）
        let json = """
        {"five_hour": {"utilization": 42, "resets_at": "2026-07-17T13:00:00Z"},
         "seven_day": {"utilization": 1, "resets_at": "2026-07-24T00:00:00Z"}}
        """
        let quota = try ProviderQuotaParser.parseClaude(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 42, accuracy: 0.001)
        XCTAssertEqual(quota.weekly?.usedPercent ?? -1, 100, accuracy: 0.001)
    }

    func testClaudeToleratesMissingResetsAt() throws {
        let json = #"{"five_hour": {"utilization": 0.5}}"#
        let quota = try ProviderQuotaParser.parseClaude(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 50, accuracy: 0.001)
        XCTAssertNil(quota.fiveHour?.resetsAt)
        XCTAssertNil(quota.weekly)
    }

    func testClaudeThrowsWhenNoWindowPresent() {
        XCTAssertThrowsError(try ProviderQuotaParser.parseClaude(Data("{}".utf8)))
    }

    // MARK: - Codex

    func testCodexMapsWindowsByDurationSeconds() throws {
        let json = """
        {"rate_limit": {
           "primary_window": {"used_percent": 23, "limit_window_seconds": 18000, "reset_at": 1720000000},
           "secondary_window": {"used_percent": 5, "limit_window_seconds": 604800, "reset_at": 1720600000}},
         "plan_type": "plus"}
        """
        let quota = try ProviderQuotaParser.parseCodex(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 23, accuracy: 0.001)
        XCTAssertEqual(quota.weekly?.usedPercent ?? -1, 5, accuracy: 0.001)
        XCTAssertEqual(quota.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_720_000_000))
        XCTAssertEqual(quota.weekly?.resetsAt, Date(timeIntervalSince1970: 1_720_600_000))
    }

    func testCodexFallsBackToWindowRoleWhenDurationUnknown() throws {
        // 时长字段缺失/无法识别时，primary → 5 小时，secondary → 每周
        let json = """
        {"rate_limit": {
           "primary_window": {"used_percent": 61, "limit_window_seconds": 7200, "reset_at": 1720000000},
           "secondary_window": {"used_percent": 9}}}
        """
        let quota = try ProviderQuotaParser.parseCodex(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 61, accuracy: 0.001)
        XCTAssertEqual(quota.weekly?.usedPercent ?? -1, 9, accuracy: 0.001)
        XCTAssertNil(quota.weekly?.resetsAt)
    }

    func testCodexThrowsWithoutRateLimit() {
        XCTAssertThrowsError(try ProviderQuotaParser.parseCodex(Data(#"{"plan_type": "plus"}"#.utf8)))
    }

    // MARK: - Kimi

    func testKimiParsesWeeklyAndFiveHourWindow() throws {
        // CLI /usage 结构：顶层 usage 为每周，limits 中 300 分钟窗口为 5 小时；数字可能是字符串
        let json = """
        {"usage": {"limit": "2048", "used": "214", "remaining": "1834",
                   "resetTime": "2026-01-09T15:23:13.716839300Z"},
         "limits": [
            {"window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
             "detail": {"limit": "200", "used": "139", "remaining": "61",
                        "resetTime": "2026-01-06T13:33:02.717479433Z"}}],
         "boosterWallet": {"balance": "0"}}
        """
        let quota = try ProviderQuotaParser.parseKimi(Data(json.utf8))

        XCTAssertEqual(quota.weekly?.used, 214)
        XCTAssertEqual(quota.weekly?.limit, 2_048)
        XCTAssertEqual(quota.weekly?.usedPercent ?? -1, 214.0 / 2_048.0 * 100, accuracy: 0.001)
        XCTAssertEqual(
            quota.weekly?.resetsAt?.timeIntervalSince1970 ?? 0,
            utcDate(2026, 1, 9, 15, 23, 13).addingTimeInterval(0.716839).timeIntervalSince1970,
            accuracy: 0.001
        )

        XCTAssertEqual(quota.fiveHour?.used, 139)
        XCTAssertEqual(quota.fiveHour?.limit, 200)
        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 69.5, accuracy: 0.001)
        XCTAssertEqual(
            quota.fiveHour?.resetsAt?.timeIntervalSince1970 ?? 0,
            utcDate(2026, 1, 6, 13, 33, 2).addingTimeInterval(0.717479).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testKimiDerivesUsedFromRemainingAndSnakeCaseReset() throws {
        // used 缺失时用 limit - remaining 补；reset_at snake_case 兼容
        let json = """
        {"usage": {"limit": 1000, "remaining": 640, "reset_at": "2026-01-09T15:23:13Z"}}
        """
        let quota = try ProviderQuotaParser.parseKimi(Data(json.utf8))

        XCTAssertEqual(quota.weekly?.used, 360)
        XCTAssertEqual(quota.weekly?.limit, 1_000)
        XCTAssertEqual(quota.weekly?.usedPercent ?? -1, 36, accuracy: 0.001)
        XCTAssertEqual(
            quota.weekly?.resetsAt?.timeIntervalSince1970 ?? 0,
            utcDate(2026, 1, 9, 15, 23, 13).timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertNil(quota.fiveHour)
    }

    func testKimiPicksFiveHourWindowRegardlessOfOrder() throws {
        // 300 分钟窗口不在第一项时仍能选对；数值直接在条目上（无 detail）也要解析
        let json = """
        {"usage": {"limit": 100, "used": 10},
         "limits": [
            {"window": {"duration": 10080, "timeUnit": "TIME_UNIT_MINUTE"},
             "limit": 500, "used": 50, "reset_time": "2026-01-12T00:00:00Z"},
            {"window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
             "detail": {"limit": 200, "used": 20, "resetAt": "2026-01-06T13:33:02Z"}}]}
        """
        let quota = try ProviderQuotaParser.parseKimi(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.used, 20)
        XCTAssertEqual(quota.fiveHour?.limit, 200)
        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(
            quota.fiveHour?.resetsAt?.timeIntervalSince1970 ?? 0,
            utcDate(2026, 1, 6, 13, 33, 2).timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(quota.weekly?.used, 10)
    }

    func testKimiFallsBackToFirstLimitItemWhenNoFiveHourWindow() throws {
        let json = """
        {"usage": {"limit": 100, "used": 10},
         "limits": [
            {"window": {"duration": 10080, "timeUnit": "TIME_UNIT_MINUTE"},
             "detail": {"limit": 500, "used": 50}}]}
        """
        let quota = try ProviderQuotaParser.parseKimi(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.used, 50)
        XCTAssertEqual(quota.fiveHour?.limit, 500)
    }

    func testKimiThrowsOnMissingUsageAndGarbage() {
        XCTAssertThrowsError(try ProviderQuotaParser.parseKimi(Data(#"{"boosterWallet": {}}"#.utf8)))
        XCTAssertThrowsError(try ProviderQuotaParser.parseKimi(Data(#"{"usage": {}, "limits": []}"#.utf8)))
    }

    // MARK: - GLM

    func testGLMSortsTokenLimitsByResetTime() throws {
        // 乱序输入：每周窗在前、5 小时窗在后，仍要按 nextResetTime 升序映射
        let json = """
        {"code": 200, "msg": "操作成功",
         "data": {"limits": [
            {"type": "TIME_LIMIT", "percentage": 7, "usage": 1000, "currentValue": 72, "remaining": 928},
            {"type": "TOKENS_LIMIT", "percentage": 53, "nextResetTime": 1720600000000},
            {"type": "TOKENS_LIMIT", "percentage": 44, "nextResetTime": 1720000000000}],
          "level": "pro"},
         "success": true}
        """
        let quota = try ProviderQuotaParser.parseGLM(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 44, accuracy: 0.001)
        XCTAssertEqual(quota.weekly?.usedPercent ?? -1, 53, accuracy: 0.001)
        XCTAssertEqual(quota.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_720_000_000))
        XCTAssertEqual(quota.weekly?.resetsAt, Date(timeIntervalSince1970: 1_720_600_000))
    }

    func testGLMTreatsTimeLimitAsIgnoredAndSingleTokenLimitAsFiveHour() throws {
        let json = """
        {"code": 200, "data": {"limits": [
            {"type": "TIME_LIMIT", "percentage": 7, "usage": 1000, "currentValue": 72},
            {"type": "TOKENS_LIMIT", "percentage": 44, "nextResetTime": 1720000000000}]}}
        """
        let quota = try ProviderQuotaParser.parseGLM(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 44, accuracy: 0.001)
        XCTAssertNil(quota.weekly)
    }

    func testGLMThrowsOnErrorCode() {
        let json = #"{"code": 401, "msg": "令牌无效", "success": false}"#
        XCTAssertThrowsError(try ProviderQuotaParser.parseGLM(Data(json.utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("令牌无效"))
        }
    }

    // MARK: - 通用容错

    func testAllParsersThrowOnGarbageData() {
        let garbage = Data("not a json payload".utf8)
        XCTAssertThrowsError(try ProviderQuotaParser.parseClaude(garbage))
        XCTAssertThrowsError(try ProviderQuotaParser.parseCodex(garbage))
        XCTAssertThrowsError(try ProviderQuotaParser.parseKimi(garbage))
        XCTAssertThrowsError(try ProviderQuotaParser.parseGLM(garbage))
    }

    func testParseQuotaTimestampHandlesNanosecondsAndPlainForms() throws {
        let nanosecond = parseQuotaTimestamp("2026-01-09T15:23:13.716839300Z")
        XCTAssertEqual(
            nanosecond?.timeIntervalSince1970 ?? 0,
            utcDate(2026, 1, 9, 15, 23, 13).addingTimeInterval(0.716839).timeIntervalSince1970,
            accuracy: 0.001
        )

        let millisecond = parseQuotaTimestamp("2026-07-17T13:00:00.000Z")
        XCTAssertEqual(
            millisecond?.timeIntervalSince1970 ?? 0,
            utcDate(2026, 7, 17, 13, 0).timeIntervalSince1970,
            accuracy: 0.001
        )

        let plain = parseQuotaTimestamp("2026-07-24T00:00:00Z")
        XCTAssertEqual(
            plain?.timeIntervalSince1970 ?? 0,
            utcDate(2026, 7, 24, 0, 0).timeIntervalSince1970,
            accuracy: 0.001
        )

        XCTAssertNil(parseQuotaTimestamp("not a date"))
    }

    // MARK: - Kimi CLI 凭据

    func testKimiCLICredentialParsesTokenAndSecondsExpiry() {
        let json = """
        {"access_token": "token-abc", "refresh_token": "refresh-abc",
         "expires_at": 1893456000, "expires_in": 3600,
         "scope": "all", "token_type": "Bearer"}
        """
        let credential = parseKimiCLICredential(Data(json.utf8))

        XCTAssertEqual(credential?.accessToken, "token-abc")
        XCTAssertEqual(credential?.expiresAt, Date(timeIntervalSince1970: 1_893_456_000))
        // 1893456000 ≈ 2030-01-01，对更早的时间点未过期，对更晚的时间点已过期
        XCTAssertEqual(credential?.isExpired(at: Date(timeIntervalSince1970: 1_800_000_000)), false)
        XCTAssertEqual(credential?.isExpired(at: Date(timeIntervalSince1970: 1_900_000_000)), true)
    }

    func testKimiCLICredentialParsesMillisExpiry() {
        // 大于 1e12 的 expires_at 按毫秒处理
        let json = #"{"access_token": "token-abc", "expires_at": 1893456000000}"#
        let credential = parseKimiCLICredential(Data(json.utf8))

        XCTAssertEqual(credential?.accessToken, "token-abc")
        XCTAssertEqual(credential?.expiresAt, Date(timeIntervalSince1970: 1_893_456_000))
    }

    func testKimiCLICredentialRejectsMissingTokenAndGarbage() {
        XCTAssertNil(parseKimiCLICredential(Data(#"{"refresh_token": "r", "expires_at": 1893456000}"#.utf8)))
        XCTAssertNil(parseKimiCLICredential(Data(#"{"access_token": ""}"#.utf8)))
        XCTAssertNil(parseKimiCLICredential(Data("not a json payload".utf8)))
    }

    func testKimiCLICredentialWithoutExpiryTreatedAsValid() {
        let credential = parseKimiCLICredential(Data(#"{"access_token": "token-abc"}"#.utf8))

        XCTAssertEqual(credential?.accessToken, "token-abc")
        XCTAssertNil(credential?.expiresAt)
        XCTAssertEqual(credential?.isExpired(at: Date()), false)
    }

    // MARK: - 辅助

    private func utcDate(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int, _ second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date ?? .distantPast
    }
}
