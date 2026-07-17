import XCTest
@testable import ZFStatMenus

final class ProviderQuotaTests: XCTestCase {
    func testQuotaRemainingLevelUsesExpectedColorThresholds() {
        XCTAssertEqual(quotaRemainingLevel(for: -10), .empty)
        XCTAssertEqual(quotaRemainingLevel(for: 0), .empty)
        XCTAssertEqual(quotaRemainingLevel(for: 0.1), .critical)
        XCTAssertEqual(quotaRemainingLevel(for: 24.99), .critical)
        XCTAssertEqual(quotaRemainingLevel(for: 25), .low)
        XCTAssertEqual(quotaRemainingLevel(for: 49.99), .low)
        XCTAssertEqual(quotaRemainingLevel(for: 50), .medium)
        XCTAssertEqual(quotaRemainingLevel(for: 74.99), .medium)
        XCTAssertEqual(quotaRemainingLevel(for: 75), .high)
        XCTAssertEqual(quotaRemainingLevel(for: 100), .high)
        XCTAssertEqual(quotaRemainingLevel(for: 120), .high)
    }

    // MARK: - Claude

    func testClaudeParsesFractionalPercentageUtilization() throws {
        let json = """
        {"five_hour": {"utilization": 0.42, "resets_at": "2026-07-17T13:00:00.000Z"},
         "seven_day": {"utilization": 0.12, "resets_at": "2026-07-24T00:00:00.000Z"}}
        """
        let quota = try ProviderQuotaParser.parseClaude(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 0.42, accuracy: 0.001)
        XCTAssertEqual(quota.weekly?.usedPercent ?? -1, 0.12, accuracy: 0.001)
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
        let json = """
        {"five_hour": {"utilization": 42, "resets_at": "2026-07-17T13:00:00Z"},
         "seven_day": {"utilization": 1, "resets_at": "2026-07-24T00:00:00Z"}}
        """
        let quota = try ProviderQuotaParser.parseClaude(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 42, accuracy: 0.001)
        XCTAssertEqual(quota.weekly?.usedPercent ?? -1, 1, accuracy: 0.001)
    }

    func testClaudeToleratesMissingResetsAt() throws {
        let json = #"{"five_hour": {"utilization": 0.5}}"#
        let quota = try ProviderQuotaParser.parseClaude(Data(json.utf8))

        XCTAssertEqual(quota.fiveHour?.usedPercent ?? -1, 0.5, accuracy: 0.001)
        XCTAssertNil(quota.fiveHour?.resetsAt)
        XCTAssertNil(quota.weekly)
    }

    func testClaudeThrowsWhenNoWindowPresent() {
        XCTAssertThrowsError(try ProviderQuotaParser.parseClaude(Data("{}".utf8)))
    }

    func testClaudeOAuthCredentialParsesMillisExpiryAndRefreshToken() {
        let json = """
        {"claudeAiOauth": {
          "accessToken": "access-old", "refreshToken": "refresh-old",
          "expiresAt": 1893456000000,
          "scopes": ["user:inference"], "subscriptionType": "max"
        }}
        """
        let credential = parseClaudeOAuthCredential(Data(json.utf8))

        XCTAssertEqual(credential?.accessToken, "access-old")
        XCTAssertEqual(credential?.refreshToken, "refresh-old")
        XCTAssertEqual(credential?.expiresAt, Date(timeIntervalSince1970: 1_893_456_000))
        XCTAssertEqual(
            credential?.isExpired(at: Date(timeIntervalSince1970: 1_893_455_980), leeway: 30),
            true
        )
    }

    func testClaudeOAuthCredentialAcceptsSecondsAndMissingExpiry() {
        let seconds = parseClaudeOAuthCredential(Data(
            #"{"claudeAiOauth":{"accessToken":"access","expiresAt":"1893456000"}}"#.utf8
        ))
        let missing = parseClaudeOAuthCredential(Data(
            #"{"claudeAiOauth":{"accessToken":"access"}}"#.utf8
        ))

        XCTAssertEqual(seconds?.expiresAt, Date(timeIntervalSince1970: 1_893_456_000))
        XCTAssertNil(missing?.expiresAt)
        XCTAssertEqual(missing?.isExpired(at: Date()), false)
    }

    func testClaudeOAuthCredentialRejectsMissingTokenAndGarbage() {
        XCTAssertNil(parseClaudeOAuthCredential(Data(
            #"{"claudeAiOauth":{"refreshToken":"refresh"}}"#.utf8
        )))
        XCTAssertNil(parseClaudeOAuthCredential(Data("not json".utf8)))
    }

    func testClaudeRefreshResponseRotatesTokensAndPreservesMetadata() throws {
        let original = Data("""
        {"installId": "keep-me", "claudeAiOauth": {
          "accessToken": "access-old", "refreshToken": "refresh-old",
          "expiresAt": 1000, "scopes": ["old:scope"],
          "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x"
        }}
        """.utf8)
        let response = Data("""
        {"access_token":"access-new", "refresh_token":"refresh-new",
         "expires_in":900, "scope":"user:inference user:profile", "token_type":"Bearer"}
        """.utf8)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let updatedData = try XCTUnwrap(updateClaudeOAuthCredential(original, with: response, now: now))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: updatedData) as? [String: Any]
        )
        let oauth = try XCTUnwrap(object["claudeAiOauth"] as? [String: Any])

        XCTAssertEqual(object["installId"] as? String, "keep-me")
        XCTAssertEqual(oauth["accessToken"] as? String, "access-new")
        XCTAssertEqual(oauth["refreshToken"] as? String, "refresh-new")
        XCTAssertEqual(oauth["expiresAt"] as? Int64, 1_800_000_900_000)
        XCTAssertEqual(oauth["scopes"] as? [String], ["user:inference", "user:profile"])
        XCTAssertEqual(oauth["subscriptionType"] as? String, "max")
        XCTAssertEqual(oauth["rateLimitTier"] as? String, "default_claude_max_5x")
    }

    func testClaudeRefreshResponseRejectsIncompletePayload() {
        let original = Data(#"{"claudeAiOauth":{"accessToken":"old"}}"#.utf8)

        XCTAssertNil(updateClaudeOAuthCredential(
            original,
            with: Data(#"{"access_token":"new","expires_in":900}"#.utf8)
        ))
        XCTAssertNil(updateClaudeOAuthCredential(
            original,
            with: Data(#"{"access_token":"new","refresh_token":"refresh","expires_in":0}"#.utf8)
        ))
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
        XCTAssertEqual(credential?.refreshToken, "refresh-abc")
        XCTAssertEqual(credential?.expiresAt, Date(timeIntervalSince1970: 1_893_456_000))
        XCTAssertEqual(credential?.expiresIn, 3600)
        XCTAssertEqual(credential?.scope, "all")
        XCTAssertEqual(credential?.tokenType, "Bearer")
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

    func testKimiCLICredentialExpiryLeeway() {
        let credential = parseKimiCLICredential(Data(
            #"{"access_token":"token-abc","expires_at":1893456000}"#.utf8
        ))

        XCTAssertEqual(
            credential?.isExpired(at: Date(timeIntervalSince1970: 1_893_455_980), leeway: 30),
            true
        )
    }

    func testKimiCLIRefreshResponseParsesAndCalculatesExpiry() {
        let data = Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":900,"scope":"kimi-code","token_type":"Bearer"}"#.utf8)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let credential = parseKimiCLIRefreshResponse(data, now: now)

        XCTAssertEqual(credential?.accessToken, "new-access")
        XCTAssertEqual(credential?.refreshToken, "new-refresh")
        XCTAssertEqual(credential?.expiresAt, Date(timeIntervalSince1970: 1_800_000_900))
        XCTAssertEqual(credential?.expiresIn, 900)
        XCTAssertEqual(credential?.scope, "kimi-code")
        XCTAssertEqual(credential?.tokenType, "Bearer")
    }

    func testKimiCLIRefreshResponseRejectsIncompletePayload() {
        XCTAssertNil(parseKimiCLIRefreshResponse(Data(#"{"access_token":"new-access","expires_in":900}"#.utf8)))
        XCTAssertNil(parseKimiCLIRefreshResponse(Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":0}"#.utf8)))
        XCTAssertNil(parseKimiCLIRefreshResponse(Data("not json".utf8)))
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
