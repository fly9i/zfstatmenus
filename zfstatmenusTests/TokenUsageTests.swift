import XCTest
import SQLite3
import Darwin
@testable import ZFStatMenus

final class TokenUsageTests: XCTestCase {
    func testSnapshotMergesSameModelStoredForDifferentDevices() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let local = ModelTokenUsage(
            source: .codex,
            provider: "openai",
            model: "gpt-5.6-sol",
            tokens: TokenBreakdown(input: 100, cachedInput: 20)
        )
        let remote = ModelTokenUsage(
            source: .codex,
            provider: "openai",
            model: "gpt-5.6-sol",
            tokens: TokenBreakdown(input: 300, output: 40)
        )
        let store = TokenUsageStore(
            daily: [
                today: [
                    "local|\(local.id)": local,
                    "remote|device-b|\(remote.id)": remote,
                ]
            ]
        )

        let usages = store.snapshot(days: 1, errors: []).days[0].modelUsages

        XCTAssertEqual(usages.count, 1)
        XCTAssertEqual(usages[0].model, "gpt-5.6-sol")
        XCTAssertEqual(usages[0].tokens, TokenBreakdown(input: 400, cachedInput: 20, output: 40))
    }

    func testDeviceTokenUsageSummaryReportsPeriodTotals() {
        let days = [
            DailyTokenUsage(date: Date(timeIntervalSince1970: 1_000), sourceTotals: [.codex: 100]),
            DailyTokenUsage(date: Date(timeIntervalSince1970: 2_000), sourceTotals: [.opencode: 250]),
        ]
        let summary = DeviceTokenUsageSummary(
            deviceId: "device-1",
            deviceName: "工作 Mac",
            isCurrentDevice: true,
            snapshot: TokenUsageSnapshot(generatedAt: Date(), days: days, errorMessage: nil)
        )

        XCTAssertEqual(summary.displayName, "工作 Mac · 本机")
        XCTAssertEqual(summary.totalTokens(last: 1), 250)
        XCTAssertEqual(summary.totalTokens(last: 7), 350)
        XCTAssertEqual(summary.totalTokens(last: 30), 350)
    }

    func testSettingsWindowControllerPresentsReusableWindow() async {
        await MainActor.run {
            SettingsWindowController.shared.show()

            let settingsWindows = NSApp.windows.filter {
                $0.identifier?.rawValue == "ZFStatMenus.Settings"
            }
            XCTAssertEqual(settingsWindows.count, 1)
            XCTAssertTrue(settingsWindows[0].isVisible)

            SettingsWindowController.shared.show()
            XCTAssertEqual(
                NSApp.windows.filter { $0.identifier?.rawValue == "ZFStatMenus.Settings" }.count,
                1,
                "重复点击设置按钮不应创建多个窗口"
            )
            settingsWindows[0].orderOut(nil)
        }
    }

    func testPeriodTotalsAndSourceTotals() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date())
        let days = (0..<30).map { offset in
            DailyTokenUsage(
                date: calendar.date(byAdding: .day, value: offset, to: start)!,
                sourceTotals: [.opencode: 100, .zcode: 30, .codex: 20, .claude: 5]
            )
        }
        let snapshot = TokenUsageSnapshot(generatedAt: Date(), days: days, errorMessage: nil)

        XCTAssertEqual(snapshot.todayTokens, 155)
        XCTAssertEqual(snapshot.last7DaysTokens, 1_085)
        XCTAssertEqual(snapshot.last30DaysTokens, 4_650)
        XCTAssertEqual(snapshot.totalTokens(for: .codex, last: 30), 600)
        XCTAssertEqual(snapshot.totalTokens(for: .zcode, last: 30), 900)
    }

    func testTokenCountFormatting() {
        XCTAssertEqual(formatTokenCount(999), "999")
        XCTAssertEqual(formatTokenCount(1_500), "1.5K")
        XCTAssertEqual(formatTokenCount(2_500_000), "2.5M")
        XCTAssertEqual(formatTokenCount(1_200_000_000), "1.2B")
    }

    func testZCodeInputTokensAreSplitWithoutDoubleCountingCache() {
        let tokens = zcodeTokenBreakdown(
            inputIncludingCache: 184_778,
            cacheRead: 183_040,
            cacheWrite: 0,
            output: 486,
            reasoning: 0
        )

        XCTAssertEqual(tokens.input, 1_738)
        XCTAssertEqual(tokens.cachedInput, 183_040)
        XCTAssertEqual(tokens.output, 486)
        XCTAssertEqual(tokens.totalTokens, 185_264)
    }

    func testKimiCurrentUsageRecordPreservesTokenCategories() throws {
        let data = try XCTUnwrap(
            """
            {"type":"usage.record","model":"kimi-code/kimi-for-coding-highspeed","usage":{"inputOther":4133,"output":106,"inputCacheRead":17920,"inputCacheCreation":256},"usageScope":"turn","time":1784109696904}
            """.data(using: .utf8)
        )

        let event = try XCTUnwrap(parseKimiUsageEvent(data))

        XCTAssertEqual(event.provider, "kimi-code")
        XCTAssertEqual(event.model, "kimi-for-coding-highspeed")
        XCTAssertEqual(
            event.tokens,
            TokenBreakdown(input: 4_133, cachedInput: 17_920, cacheWrite: 256, output: 106)
        )
        XCTAssertEqual(event.date.timeIntervalSince1970, 1_784_109_696.904, accuracy: 0.001)
    }

    func testKimiLegacyStatusUpdateIsSupported() throws {
        let data = try XCTUnwrap(
            """
            {"timestamp":1781518069.150505,"message":{"type":"StatusUpdate","payload":{"token_usage":{"input_other":5069,"output":192,"input_cache_read":9216,"input_cache_creation":0},"message_id":"chatcmpl-test"}}}
            """.data(using: .utf8)
        )

        let event = try XCTUnwrap(parseKimiUsageEvent(data))

        XCTAssertEqual(event.id, "legacy|chatcmpl-test")
        XCTAssertEqual(event.model, "kimi-for-coding")
        XCTAssertEqual(
            event.tokens,
            TokenBreakdown(input: 5_069, cachedInput: 9_216, cacheWrite: 0, output: 192)
        )
    }

    func testOpenAICostSeparatesCachedAndOutputTokens() {
        let usage = ModelTokenUsage(
            source: .opencode,
            provider: "openai",
            model: "gpt-5.5",
            tokens: TokenBreakdown(
                input: 1_000_000,
                cachedInput: 1_000_000,
                cacheWrite: 1_000_000,
                output: 1_000_000,
                reasoning: 1_000_000
            )
        )

        let estimate = estimateAPICost(for: [usage])

        XCTAssertEqual(estimate.nativeUSD, 71.75, accuracy: 0.0001)
        XCTAssertEqual(estimate.nativeCNY, 0)
        XCTAssertEqual(estimate.pricedTokens, 5_000_000)
        XCTAssertEqual(estimate.unpricedTokens, 0)
    }

    func testMixedCurrencyConversionAndUnknownModel() {
        let glm = ModelTokenUsage(
            source: .opencode,
            provider: "zhipuai-coding-plan",
            model: "glm-5.2",
            tokens: TokenBreakdown(input: 1_000_000, output: 1_000_000)
        )
        let unknown = ModelTokenUsage(
            source: .codex,
            provider: "openai",
            model: "codex-auto-review",
            tokens: TokenBreakdown(input: 500_000)
        )

        let estimate = estimateAPICost(for: [glm, unknown])

        XCTAssertEqual(estimate.nativeCNY, 36, accuracy: 0.0001)
        XCTAssertEqual(estimate.totalUSD(usdToCNY: 7.2), 5, accuracy: 0.0001)
        XCTAssertEqual(estimate.unpricedTokens, 500_000)
        XCTAssertEqual(estimate.unpricedModels, ["codex-auto-review"])
        XCTAssertEqual(formatTokenCost(estimate, currency: "cny", usdToCNY: 7.2), "CNY 36.00")
        XCTAssertEqual(formatTokenCost(estimate, currency: "usd", usdToCNY: 7.2), "USD 5.00")
        XCTAssertEqual(formatTokenCost(estimate, currency: "both", usdToCNY: 7.2), "USD 5.00 · CNY 36.00")
    }

    func testKnownModelUsesFirstPartyPricingAcrossProviders() {
        let providers = ["zhipuai-coding-plan", "opencode-go", "alibaba-cn"]
        let estimates = providers.map { provider in
            estimateAPICost(for: [
                ModelTokenUsage(
                    source: .opencode,
                    provider: provider,
                    model: "GLM-5.2",
                    tokens: TokenBreakdown(input: 1_000_000, output: 1_000_000)
                )
            ])
        }

        for estimate in estimates {
            XCTAssertEqual(estimate.nativeCNY, 36, accuracy: 0.0001)
            XCTAssertEqual(estimate.pricedTokens, 2_000_000)
            XCTAssertEqual(estimate.unpricedTokens, 0)
        }
    }

    func testKnownModelUsesFirstPartyPricingWithUnrelatedProvider() {
        let usage = ModelTokenUsage(
            source: .opencode,
            provider: "third-party-gateway",
            model: "claude-opus-4-8",
            tokens: TokenBreakdown(input: 1_000_000)
        )

        let estimate = estimateAPICost(for: [usage])

        XCTAssertEqual(estimate.nativeUSD, 5, accuracy: 0.0001)
        XCTAssertEqual(estimate.pricedTokens, 1_000_000)
    }

    func testKimiK3UsesOfficialCNYPricing() {
        let usage = ModelTokenUsage(
            source: .kimi,
            provider: "kimi-code",
            model: "k3",
            tokens: TokenBreakdown(
                input: 1_000_000,
                cachedInput: 1_000_000,
                cacheWrite: 1_000_000,
                output: 1_000_000
            )
        )

        let estimate = estimateAPICost(for: [usage])

        XCTAssertEqual(estimate.nativeCNY, 142, accuracy: 0.0001)
        XCTAssertEqual(estimate.pricedTokens, 4_000_000)
        XCTAssertEqual(estimate.unpricedTokens, 0)
    }

    func testInternalProductModelDoesNotInheritPublicModelPrice() {
        let usage = ModelTokenUsage(
            source: .opencode,
            provider: "openai",
            model: "gpt-5.6-sol-pro",
            tokens: TokenBreakdown(input: 1_000_000)
        )

        let estimate = estimateAPICost(for: [usage])

        XCTAssertEqual(estimate.pricedTokens, 0)
        XCTAssertEqual(estimate.unpricedTokens, 1_000_000)
    }

    func testDisplaySortsModelsByPricedCostThenTokens() {
        let usages = [
            ModelTokenUsage(
                source: .codex,
                provider: "openai",
                model: "codex-auto-review",
                tokens: TokenBreakdown(input: 10_000)
            ),
            ModelTokenUsage(
                source: .codex,
                provider: "openai",
                model: "gpt-5.5",
                tokens: TokenBreakdown(input: 1_000_000)
            ),
            ModelTokenUsage(
                source: .opencode,
                provider: "zhipuai-coding-plan",
                model: "glm-5.2",
                tokens: TokenBreakdown(input: 2_000_000)
            )
        ]

        XCTAssertEqual(
            sortedModelUsagesForDisplay(usages, usdToCNYRate: 7.2).map(\.model),
            ["gpt-5.5", "glm-5.2", "codex-auto-review"]
        )
    }

    func testDisplayHidesModelsBelowOneThousandTokens() {
        let usages = [
            ModelTokenUsage(
                source: .opencode,
                provider: "unknown",
                model: "below-threshold",
                tokens: TokenBreakdown(input: 999)
            ),
            ModelTokenUsage(
                source: .opencode,
                provider: "unknown",
                model: "at-threshold",
                tokens: TokenBreakdown(input: 1_000)
            )
        ]

        XCTAssertEqual(
            sortedModelUsagesForDisplay(usages, usdToCNYRate: 7.2).map(\.model),
            ["at-threshold"]
        )
    }

    func testDisplayMergesSameModelAcrossAllChannelsIgnoringCase() throws {
        let usages = [
            ModelTokenUsage(
                source: .opencode,
                provider: "zhipuai-coding-plan",
                model: "glm-5.2",
                tokens: TokenBreakdown(input: 1_000_000)
            ),
            ModelTokenUsage(
                source: .opencode,
                provider: "opencode-go",
                model: "glm-5.2",
                tokens: TokenBreakdown(cachedInput: 2_000_000)
            ),
            ModelTokenUsage(
                source: .zcode,
                provider: "zhipuai-coding-plan",
                model: "GLM-5.2",
                tokens: TokenBreakdown(output: 3_000_000)
            ),
        ]

        let summary = try XCTUnwrap(
            sortedModelUsagesForDisplay(usages, usdToCNYRate: 7.2).first
        )

        XCTAssertEqual(summary.model, "glm-5.2")
        XCTAssertEqual(summary.usages.count, 3)
        XCTAssertEqual(summary.channelCount, 3)
        XCTAssertEqual(summary.channelSummary, "OpenCode、ZCode · 3 个渠道")
        XCTAssertEqual(
            summary.tokens,
            TokenBreakdown(input: 1_000_000, cachedInput: 2_000_000, output: 3_000_000)
        )
        XCTAssertEqual(summary.estimate.nativeCNY, 96, accuracy: 0.0001)
    }

    func testDisplayAppliesMinimumTokenThresholdAfterModelAggregation() {
        let usages = [
            ModelTokenUsage(
                source: .opencode,
                provider: "provider-a",
                model: "shared-model",
                tokens: TokenBreakdown(input: 600)
            ),
            ModelTokenUsage(
                source: .zcode,
                provider: "provider-b",
                model: "SHARED-MODEL",
                tokens: TokenBreakdown(input: 600)
            ),
        ]

        let summaries = sortedModelUsagesForDisplay(usages, usdToCNYRate: 7.2)

        XCTAssertEqual(summaries.map(\.model), ["shared-model"])
        XCTAssertEqual(summaries[0].tokens.totalTokens, 1_200)
    }

    func testDisplaySortsSourcesByPricedCostThenTokens() {
        let day = DailyTokenUsage(
            date: Date(),
            modelUsages: [
                ModelTokenUsage(
                    source: .opencode,
                    provider: "openai",
                    model: "codex-auto-review",
                    tokens: TokenBreakdown(input: 10_000_000)
                ),
                ModelTokenUsage(
                    source: .codex,
                    provider: "openai",
                    model: "gpt-5.2-codex",
                    tokens: TokenBreakdown(input: 2_000_000)
                ),
                ModelTokenUsage(
                    source: .claude,
                    provider: "anthropic",
                    model: "claude-opus-4-8",
                    tokens: TokenBreakdown(input: 1_000_000)
                ),
                ModelTokenUsage(
                    source: .zcode,
                    provider: "unknown",
                    model: "below-threshold",
                    tokens: TokenBreakdown(input: 999)
                )
            ]
        )
        let snapshot = TokenUsageSnapshot(generatedAt: Date(), days: [day], errorMessage: nil)

        XCTAssertEqual(
            sortedTokenSourcesForDisplay(snapshot, last: 1, usdToCNYRate: 7.2),
            [.claude, .codex, .opencode]
        )
    }

    func testSourceCostOnlyIncludesSelectedTool() {
        let day = DailyTokenUsage(
            date: Date(),
            modelUsages: [
                ModelTokenUsage(
                    source: .codex,
                    provider: "openai",
                    model: "gpt-5.2-codex",
                    tokens: TokenBreakdown(input: 1_000_000)
                ),
                ModelTokenUsage(
                    source: .claude,
                    provider: "anthropic",
                    model: "claude-opus-4-8",
                    tokens: TokenBreakdown(input: 1_000_000)
                )
            ]
        )
        let snapshot = TokenUsageSnapshot(generatedAt: Date(), days: [day], errorMessage: nil)

        XCTAssertEqual(snapshot.apiCost(for: .codex, last: 1).nativeUSD, 1.75, accuracy: 0.0001)
        XCTAssertEqual(snapshot.apiCost(for: .claude, last: 1).nativeUSD, 5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.apiCost(for: .opencode, last: 1).nativeUSD, 0, accuracy: 0.0001)
    }

    func testSQLiteCacheRoundTripPreservesUsageAndCodexCursor() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let databaseURL = folder.appendingPathComponent("cache.sqlite3")
        let usage = ModelTokenUsage(
            source: .codex,
            provider: "openai",
            model: "gpt-5.2-codex",
            tokens: TokenBreakdown(input: 10, cachedInput: 20, output: 30)
        )
        let store = TokenUsageStore(
            daily: ["2026-07-14": [usage.id: usage]],
            codexFiles: [
                "/tmp/session.jsonl": CodexFileCache(
                    byteOffset: 123,
                    modifiedAt: 456,
                    lastModel: usage.model,
                    sessionID: "019f49f9-43c1-7740-a485-f89f66b7c4b4",
                    lastTurnID: "019f4a04-169c-7333-888f-f207a4454196",
                    lastEventKey: "event-key",
                    daily: ["2026-07-14": [usage.id: usage]]
                )
            ]
        )

        store.save(databaseURL: databaseURL)
        let loaded = TokenUsageStore.load(databaseURL: databaseURL, legacyJSONURL: nil)

        XCTAssertEqual(loaded.daily, store.daily)
        XCTAssertEqual(loaded.codexFiles["/tmp/session.jsonl"]?.byteOffset, 123)
        XCTAssertEqual(loaded.codexFiles["/tmp/session.jsonl"]?.lastModel, usage.model)
        XCTAssertEqual(loaded.codexFiles["/tmp/session.jsonl"]?.sessionID, store.codexFiles["/tmp/session.jsonl"]?.sessionID)
        XCTAssertEqual(loaded.codexFiles["/tmp/session.jsonl"]?.lastTurnID, store.codexFiles["/tmp/session.jsonl"]?.lastTurnID)
        XCTAssertEqual(loaded.codexFiles["/tmp/session.jsonl"]?.lastEventKey, "event-key")
        XCTAssertEqual(loaded.codexFiles["/tmp/session.jsonl"]?.daily, store.codexFiles["/tmp/session.jsonl"]?.daily)
    }

    func testSQLiteCacheImportsLegacyJSONOnce() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let databaseURL = folder.appendingPathComponent("cache.sqlite3")
        let legacyURL = folder.appendingPathComponent("cache-v2.json")
        let usage = ModelTokenUsage(
            source: .claude,
            provider: "anthropic",
            model: "claude-opus-4-8",
            tokens: TokenBreakdown(input: 99)
        )
        let legacyStore = TokenUsageStore(daily: ["2026-07-14": [usage.id: usage]])
        try JSONEncoder().encode(legacyStore).write(to: legacyURL)

        let imported = TokenUsageStore.load(databaseURL: databaseURL, legacyJSONURL: legacyURL)
        XCTAssertEqual(imported.daily, legacyStore.daily)

        try JSONEncoder().encode(TokenUsageStore()).write(to: legacyURL)
        let loadedAgain = TokenUsageStore.load(databaseURL: databaseURL, legacyJSONURL: legacyURL)
        XCTAssertEqual(loadedAgain.daily, legacyStore.daily)
    }

    func testSQLiteCacheCreatesSchemaVersionThree() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let databaseURL = folder.appendingPathComponent("cache.sqlite3")

        TokenUsageStore().save(databaseURL: databaseURL)

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqliteScalarInt(database, sql: "PRAGMA user_version"), 3)
        XCTAssertEqual(
            sqliteScalarInt(
                database,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('sync_metadata', 'sync_outbox', 'remote_daily_usage')"
            ),
            3
        )
    }

    func testCodexEventTrackerSkipsForkedParentTurnsAndKeepsChildUsage() {
        var tracker = CodexEventTracker()
        tracker.observeSession("019f4a04-d27c-72e1-849f-d92d3735365a")

        tracker.observeTurn("019f49fa-a554-7601-b406-bd3414be1421")
        XCTAssertFalse(tracker.shouldCount(totalUsage: codexTotalUsage(total: 100)))

        tracker.observeTurn("019f4a04-d3b3-7a72-bd84-700cdd69607b")
        XCTAssertTrue(tracker.shouldCount(totalUsage: codexTotalUsage(total: 200)))
    }

    func testCodexEventTrackerDeduplicatesRepeatedCumulativeUsage() {
        var tracker = CodexEventTracker()
        tracker.observeSession("019f4a04-d27c-72e1-849f-d92d3735365a")
        tracker.observeTurn("019f4a04-d3b3-7a72-bd84-700cdd69607b")
        let usage = codexTotalUsage(total: 200)

        XCTAssertTrue(tracker.shouldCount(totalUsage: usage))
        XCTAssertFalse(tracker.shouldCount(totalUsage: usage))
        XCTAssertTrue(tracker.shouldCount(totalUsage: codexTotalUsage(total: 250)))
    }

    func testCodexLogFileDiscoveryIncludesActiveAndArchivedSessions() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let activeRoot = folder.appendingPathComponent("sessions", isDirectory: true)
        let activeDay = activeRoot.appendingPathComponent("2026/07/16", isDirectory: true)
        let archivedRoot = folder.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: activeDay, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedRoot, withIntermediateDirectories: true)

        let activeFile = activeDay.appendingPathComponent("active.jsonl")
        let archivedFile = archivedRoot.appendingPathComponent("archived.jsonl")
        try Data().write(to: activeFile)
        try Data().write(to: archivedFile)
        try Data().write(to: archivedRoot.appendingPathComponent("ignored.txt"))

        let files = codexLogFileURLs(activeRoot: activeRoot, archivedRoot: archivedRoot)

        XCTAssertEqual(
            Set(files.map { $0.resolvingSymlinksInPath().path }),
            Set([activeFile, archivedFile].map { $0.resolvingSymlinksInPath().path })
        )
    }

    func testSQLiteJSONQueryRunnerDoesNotLeakFileDescriptors() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let databaseURL = folder.appendingPathComponent("probe.sqlite3")
        TokenUsageStore().save(databaseURL: databaseURL)

        let descriptorsBefore = openFileDescriptorCount()
        for _ in 0..<20 {
            let rows: [SQLiteProbeRow] = try SQLiteJSONQueryRunner.run(
                databaseURL: databaseURL,
                query: "SELECT 1 AS value"
            )
            XCTAssertEqual(rows, [SQLiteProbeRow(value: 1)])
        }
        let descriptorsAfter = openFileDescriptorCount()

        XCTAssertLessThanOrEqual(
            descriptorsAfter,
            descriptorsBefore + 2,
            "重复执行 sqlite3 查询不应持续占用 Pipe 文件描述符"
        )
    }

    func testTokenSyncRetryPolicyUsesBoundedBackoff() {
        XCTAssertEqual(TokenSyncRetryPolicy.delay(failureCount: 0), 30)
        XCTAssertEqual(TokenSyncRetryPolicy.delay(failureCount: 1), 30)
        XCTAssertEqual(TokenSyncRetryPolicy.delay(failureCount: 2), 60)
        XCTAssertEqual(TokenSyncRetryPolicy.delay(failureCount: 3), 120)
        XCTAssertEqual(TokenSyncRetryPolicy.delay(failureCount: 4), 300)
        XCTAssertEqual(TokenSyncRetryPolicy.delay(failureCount: 5), 900)
        XCTAssertEqual(TokenSyncRetryPolicy.delay(failureCount: 100), 900)
    }

    func testHeatmapHoverSelectionLifecycle() {
        let first = DailyTokenUsage(
            date: Date(timeIntervalSince1970: 1_000),
            sourceTotals: [.codex: 100]
        )
        let second = DailyTokenUsage(
            date: Date(timeIntervalSince1970: 2_000),
            sourceTotals: [.opencode: 200, .claude: 300]
        )
        var state = TokenHeatmapHoverState()

        state.update(day: first, isHovered: true)
        XCTAssertEqual(state.day, first)

        state.update(day: second, isHovered: true)
        state.update(day: first, isHovered: false)
        XCTAssertEqual(state.day, second, "离开旧格子时不应清除当前格子的明细")

        state.update(day: second, isHovered: false)
        XCTAssertNil(state.day)
    }

    func testHeatmapUsesFixedTokenThresholds() {
        XCTAssertEqual(tokenHeatLevel(0), 0)
        XCTAssertEqual(tokenHeatLevel(4_700_000), 1)
        XCTAssertEqual(tokenHeatLevel(9_999_999), 1)
        XCTAssertEqual(tokenHeatLevel(10_000_000), 2)
        XCTAssertEqual(tokenHeatLevel(80_000_000), 2)
        XCTAssertEqual(tokenHeatLevel(99_999_999), 2)
        XCTAssertEqual(tokenHeatLevel(100_000_000), 3)
    }
}

private struct SQLiteProbeRow: Decodable, Equatable {
    let value: Int
}

private func codexTotalUsage(total: Int64) -> [String: Any] {
    [
        "input_tokens": total - 10,
        "cached_input_tokens": max(0, total - 20),
        "output_tokens": 10,
        "reasoning_output_tokens": 2,
        "total_tokens": total,
    ]
}

private func openFileDescriptorCount() -> Int {
    (0..<Int(getdtablesize())).reduce(into: 0) { count, descriptor in
        if fcntl(Int32(descriptor), F_GETFD) != -1 {
            count += 1
        }
    }
}

private func sqliteScalarInt(_ database: OpaquePointer?, sql: String) -> Int64 {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else { return -1 }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
    return sqlite3_column_int64(statement, 0)
}
