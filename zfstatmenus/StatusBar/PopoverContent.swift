import AppKit
import SwiftUI

private struct PopoverPage<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let content: Content

    init(
        width: CGFloat = AppTheme.tokenPopoverWidth,
        height: CGFloat = AppTheme.tokenPopoverHeight,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.height = height
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(width: width - 40, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
        }
        .appPopoverScrolling()
        .frame(width: width, height: height)
        .background(AppTheme.canvas)
    }
}

// MARK: - CPU

struct CPUDetailView: View {
    @ObservedObject var holder: MonitorHolder

    init(monitorManager: MonitorManager) {
        self.holder = MonitorHolder(monitorManager: monitorManager)
    }

    var body: some View {
        PopoverPage(width: AppTheme.detailPopoverWidth, height: AppTheme.detailPopoverHeight) {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeader(
                    title: "CPU",
                    subtitle: "\(holder.cpu.perCoreUsage.count) 个逻辑核心",
                    systemImage: "cpu"
                )

                HStack(spacing: 12) {
                    DetailHeroMetric(
                        label: "总使用率",
                        value: String(format: "%.1f%%", holder.cpu.overallUsage * 100),
                        systemImage: "waveform.path.ecg"
                    )
                    DetailHeroMetric(
                        label: "用户",
                        value: String(format: "%.1f%%", holder.cpu.userUsage * 100),
                        systemImage: "person.fill"
                    )
                    DetailHeroMetric(
                        label: "系统",
                        value: String(format: "%.1f%%", holder.cpu.systemUsage * 100),
                        systemImage: "gearshape.2.fill"
                    )
                }

                if !holder.cpuHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(title: "最近一分钟", trailing: "总体使用率")
                        BarChartView(values: holder.cpuHistory, color: AppTheme.accent)
                            .frame(height: 68)
                    }
                    .appPanel(padding: 13)
                }

                if !holder.cpu.perCoreUsage.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(title: "核心活动", trailing: "\(holder.cpu.perCoreUsage.count) 核")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(Array(holder.cpu.perCoreUsage.enumerated()), id: \.offset) { index, usage in
                                CoreActivityCell(index: index, usage: usage)
                            }
                        }
                    }
                    .appPanel(padding: 13)
                }

                if !holder.topCPU.isEmpty {
                    ProcessListPanel(title: "占用最高", processes: holder.topCPU) { process in
                        String(format: "%.1f%%", process.cpuUsage * 100)
                    }
                }
            }
        }
        .onAppear { holder.start(.cpu) }
        .onDisappear { holder.stop() }
    }
}

// MARK: - Memory

struct MemoryDetailView: View {
    @ObservedObject var holder: MonitorHolder

    init(monitorManager: MonitorManager) {
        self.holder = MonitorHolder(monitorManager: monitorManager)
    }

    var body: some View {
        PopoverPage(width: AppTheme.detailPopoverWidth, height: AppTheme.detailPopoverHeight) {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeader(title: "内存", subtitle: "物理内存与交换空间", systemImage: "memorychip")

                if holder.memory.total == 0 {
                    AppEmptyState(systemName: "memorychip", title: "正在读取内存", detail: "首次采样完成后将在这里显示使用情况。")
                        .appPanel()
                } else {
                    HStack(spacing: 18) {
                        MemoryUsageRing(
                            ratio: Double(holder.memory.used) / Double(holder.memory.total),
                            value: formatBytes(holder.memory.used)
                        )
                        VStack(spacing: 8) {
                            CompactMetric(label: "可用", value: formatBytes(holder.memory.free))
                            CompactMetric(label: "总计", value: formatBytes(holder.memory.total))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appPanel(padding: 14)

                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(title: "内存构成")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            MemoryBreakdownCell(label: "App 内存", value: formatBytes(holder.memory.appMemory))
                            MemoryBreakdownCell(label: "Wired", value: formatBytes(holder.memory.wired))
                            MemoryBreakdownCell(label: "压缩", value: formatBytes(holder.memory.compressed))
                            MemoryBreakdownCell(label: "缓存文件", value: formatBytes(holder.memory.cachedFiles))
                            if holder.memory.swapUsed > 0 {
                                MemoryBreakdownCell(label: "Swap", value: formatBytes(holder.memory.swapUsed))
                            }
                        }
                    }
                    .appPanel(padding: 13)

                    if !holder.topMemory.isEmpty {
                        ProcessListPanel(title: "占用最高", processes: holder.topMemory) {
                            formatBytes($0.memoryBytes)
                        }
                    }
                }
            }
        }
        .onAppear { holder.start(.memory) }
        .onDisappear { holder.stop() }
    }
}

// MARK: - Network

struct NetworkDetailView: View {
    @ObservedObject var holder: MonitorHolder

    init(monitorManager: MonitorManager) {
        self.holder = MonitorHolder(monitorManager: monitorManager)
    }

    var body: some View {
        PopoverPage(width: AppTheme.detailPopoverWidth, height: AppTheme.detailPopoverHeight) {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeader(title: "网络", subtitle: "实时吞吐与进程带宽", systemImage: "arrow.up.arrow.down")

                HStack(spacing: 10) {
                    NetworkHeroMetric(
                        title: "下载",
                        value: formatSpeed(holder.network.downloadBytesPerSec),
                        total: formatBytes(holder.network.totalDownload),
                        systemImage: "arrow.down"
                    )
                    NetworkHeroMetric(
                        title: "上传",
                        value: formatSpeed(holder.network.uploadBytesPerSec),
                        total: formatBytes(holder.network.totalUpload),
                        systemImage: "arrow.up"
                    )
                }

                if !holder.netDownHistory.isEmpty || !holder.netUpHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(title: "最近一分钟", trailing: "实时速率")
                        if !holder.netDownHistory.isEmpty {
                            TrendRow(label: "下载", values: holder.netDownHistory, color: AppTheme.accent)
                        }
                        if !holder.netUpHistory.isEmpty {
                            TrendRow(label: "上传", values: holder.netUpHistory, color: AppTheme.accent.opacity(0.48))
                        }
                    }
                    .appPanel(padding: 13)
                }

                if !holder.topNetwork.isEmpty {
                    NetworkProcessListPanel(processes: holder.topNetwork)
                }
            }
        }
        .onAppear { holder.start(.network) }
        .onDisappear { holder.stop() }
    }
}

private struct DetailHeroMetric: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.accent)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .tracking(-0.7)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .appPanel(padding: 13)
    }
}

private struct CompactMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CoreActivityCell: View {
    let index: Int
    let usage: Double

    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2).fill(AppTheme.subtleFill)
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.accent.opacity(0.35 + min(max(usage, 0), 1) * 0.65))
                    .frame(height: max(2, 28 * CGFloat(usage)))
            }
            .frame(width: 7, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("C\(index + 1)").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", usage * 100))
                    .font(.system(size: 9, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(AppTheme.subtleFill.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct MemoryUsageRing: View {
    let ratio: Double
    let value: String

    var body: some View {
        ZStack {
            Circle().stroke(AppTheme.subtleFill, lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(max(ratio, 0), 1))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(String(format: "%.0f%%", ratio * 100))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(value).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityLabel("内存使用率 \(String(format: "%.0f%%", ratio * 100))")
    }
}

private struct MemoryBreakdownCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct NetworkHeroMetric: View {
    let title: String
    let value: String
    let total: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("累计 \(total)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(padding: 12)
    }
}

private struct TrendRow: View {
    let label: String
    let values: [Double]
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            BarChartView(values: values, color: color)
                .frame(height: 34)
        }
    }
}

private struct ProcessListPanel: View {
    let title: String
    let processes: [TopProcess]
    let value: (TopProcess) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSectionHeader(title: title, trailing: "Top \(processes.count)")
            VStack(spacing: 7) {
                ForEach(processes) { process in
                    ProcessRow(icon: process.icon, name: process.name, value: value(process), valueColor: AppTheme.accent)
                }
            }
        }
        .appPanel(padding: 12)
    }
}

private struct NetworkProcessListPanel: View {
    let processes: [NetworkProcess]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSectionHeader(title: "带宽占用最高", trailing: "Top \(processes.count)")
            VStack(spacing: 8) {
                ForEach(processes) { process in
                    HStack(spacing: 8) {
                        ProcessIcon(icon: process.icon)
                        Text(process.name).lineLimit(1).font(.system(size: 12, weight: .medium))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("↓ \(formatSpeed(Double(process.bytesIn)))")
                            Text("↑ \(formatSpeed(Double(process.bytesOut)))")
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .appPanel(padding: 12)
    }
}

// MARK: - Token

struct TokenDetailView: View {
    @ObservedObject var monitor: TokenUsageMonitor
    @ObservedObject private var syncService = TokenSyncService.shared
    @ObservedObject private var quotaMonitor = ProviderQuotaMonitor.shared
    @AppStorage("tokenDisplayCurrency") private var currency = "both"
    @AppStorage("tokenUSDToCNYRate") private var usdToCNYRate = 7.2
    @AppStorage("tokenShowDeviceBreakdown") private var showsDeviceBreakdown = true
    @State private var didCopyShareImage = false

    var body: some View {
        PopoverPage {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image("TokenGlyph")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Token 活动")
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.2)
                        Text("本机与已同步设备的综合统计")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        TokenSyncStatusSymbol(status: syncService.status)
                        Text(syncService.status.message)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .help(syncStatusHelp)
                    if monitor.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    AppIconButton(systemName: "arrow.clockwise", help: "刷新 Token 数据") {
                        monitor.refresh()
                        quotaMonitor.refresh()
                    }
                    AppIconButton(
                        systemName: "desktopcomputer",
                        help: showsDeviceBreakdown ? "隐藏各设备 Token 消耗" : "显示各设备 Token 消耗",
                        isActive: showsDeviceBreakdown
                    ) {
                        showsDeviceBreakdown.toggle()
                    }
                    AppIconButton(systemName: "gearshape", help: "打开设置") {
                        AppWindowActions.openSettings()
                    }
                    AppIconButton(
                        systemName: didCopyShareImage ? "checkmark" : "square.and.arrow.up",
                        help: didCopyShareImage ? "已复制手机竖版统计图片" : "复制手机竖版 Token 统计图片"
                    ) {
                        copyTokenOverview()
                    }
                    AppIconButton(systemName: "power", help: "退出 ZFStatMenus") {
                        AppWindowActions.quit()
                    }
                }

                HStack(spacing: 10) {
                    TokenSummaryCard(
                        title: "今日",
                        value: monitor.snapshot.todayTokens,
                        cost: costText(last: 1),
                        dayCount: 1,
                        devices: monitor.deviceUsages,
                        showsDevices: showsDeviceBreakdown
                    )
                    TokenSummaryCard(
                        title: "过去 7 天",
                        value: monitor.snapshot.last7DaysTokens,
                        cost: costText(last: 7),
                        dayCount: 7,
                        devices: monitor.deviceUsages,
                        showsDevices: showsDeviceBreakdown
                    )
                    TokenSummaryCard(
                        title: "过去 30 天",
                        value: monitor.snapshot.last30DaysTokens,
                        cost: costText(last: 30),
                        dayCount: 30,
                        devices: monitor.deviceUsages,
                        showsDevices: showsDeviceBreakdown
                    )
                }

                if !quotaMonitor.quotas.isEmpty {
                    ProviderQuotaPanel(quotas: quotaMonitor.quotas)
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppSectionHeader(title: "消耗热力图", subtitle: "悬停任意日期查看当天模型明细", trailing: "近一年")
                    TokenCalendarHeatmap(
                        days: monitor.snapshot.days,
                        currency: currency,
                        usdToCNYRate: usdToCNYRate
                    )
                }
                .appPanel(padding: 13)

                HStack(alignment: .top, spacing: 12) {
                    TokenSourceSection(
                        title: "今日来源",
                        dayCount: 1,
                        snapshot: monitor.snapshot,
                        currency: currency,
                        usdToCNYRate: usdToCNYRate
                    )
                    TokenSourceSection(
                        title: "过去 30 天来源",
                        dayCount: 30,
                        snapshot: monitor.snapshot,
                        currency: currency,
                        usdToCNYRate: usdToCNYRate
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    AppSectionHeader(
                        title: "模型费用估算",
                        subtitle: "过去 30 天，按第一方公开 API 单价计算",
                        trailing: "已定价优先"
                    )

                    if recentModels.isEmpty {
                        AppEmptyState(
                            systemName: "chart.bar.xaxis",
                            title: "暂无可展示模型",
                            detail: "完成首次扫描后，这里会显示 Token 不少于 1K 的模型。"
                        )
                    } else {
                        VStack(spacing: 0) {
                            TokenCostColumnHeader(leftTitle: "模型", currency: currency)
                            Divider().overlay(AppTheme.border)
                            ForEach(Array(recentModels.enumerated()), id: \.element.id) { index, usage in
                                ModelTokenCostRow(
                                    usage: usage,
                                    currency: currency,
                                    usdToCNYRate: usdToCNYRate
                                )
                                if index < recentModels.count - 1 {
                                    Divider().padding(.leading, 12).overlay(AppTheme.border)
                                }
                            }
                        }
                        .background(AppTheme.subtleFill.opacity(0.55), in: RoundedRectangle(cornerRadius: AppTheme.innerRadius))
                    }

                    let estimate = estimateAPICost(for: displayedModelsLast30Days.flatMap(\.usages))
                    if !estimate.unpricedModels.isEmpty {
                        Label(
                            "未定价模型：\(estimate.unpricedModels.sorted().joined(separator: "、"))",
                            systemImage: "questionmark.circle"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("估算使用公开标准 API 单价与设置中的汇率；不含订阅费、长上下文阶梯、Batch/Priority、工具调用及地区差异。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appPanel(padding: 13)

                if let error = monitor.snapshot.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { quotaMonitor.refreshIfStale() }
    }

    private var syncStatusHelp: String {
        var values = [syncService.status.message]
        if syncService.status.pendingDays > 0 {
            values.append("待同步 \(syncService.status.pendingDays) 天")
        }
        if let date = syncService.status.lastSuccessAt {
            values.append("上次成功：\(date.formatted(date: .abbreviated, time: .shortened))")
        }
        return values.joined(separator: " · ")
    }

    private func costText(last dayCount: Int) -> String {
        formatTokenCost(
            monitor.snapshot.apiCost(last: dayCount),
            currency: currency,
            usdToCNY: usdToCNYRate
        )
    }

    private var displayedModelsLast30Days: [ModelUsageDisplaySummary] {
        sortedModelUsagesForDisplay(
            monitor.snapshot.modelUsages(last: 30),
            usdToCNYRate: usdToCNYRate
        )
    }

    private var recentModels: [ModelUsageDisplaySummary] {
        Array(displayedModelsLast30Days.prefix(20))
    }

    private func copyTokenOverview() {
        let copied = TokenShareSnapshotRenderer.copyToPasteboard(
            snapshot: monitor.snapshot,
            quotas: quotaMonitor.quotas,
            currency: currency,
            usdToCNYRate: usdToCNYRate
        )
        guard copied else {
            NSSound.beep()
            return
        }

        didCopyShareImage = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            didCopyShareImage = false
        }
    }
}

// MARK: - 订阅额度面板

private struct ProviderQuotaPanel: View {
    let quotas: [QuotaProvider: ProviderQuota]

    // 展示顺序：GPT、GLM、Kimi、Claude（只有单窗口的卡片优先排在同一行）
    private static let displayOrder: [QuotaProvider] = [.codex, .glm, .kimi, .claude]

    private var providers: [QuotaProvider] {
        Self.displayOrder.filter { quotas[$0] != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionHeader(title: "订阅额度", subtitle: "各平台 5 小时与每周额度", trailing: updatedText)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(providers, id: \.self) { provider in
                    if let quota = quotas[provider] {
                        ProviderQuotaCard(provider: provider, quota: quota)
                    }
                }
            }
        }
        .appPanel(padding: 13)
    }

    private var updatedText: String {
        guard let latest = quotas.values.map(\.updatedAt).max() else { return "" }
        return "更新于 \(Self.clockFormatter.string(from: latest))"
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct ProviderQuotaCard: View {
    let provider: QuotaProvider
    let quota: ProviderQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(provider.iconAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(AppTheme.accent)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Text(provider.planName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            if let error = quota.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // 部分套餐没有 5 小时窗（如 Codex Pro Lite 只有每周额度），不存在的窗口不渲染
                if let fiveHour = quota.fiveHour {
                    QuotaWindowRow(title: "5小时", window: fiveHour, resetStyle: .clock)
                }
                if let weekly = quota.weekly {
                    QuotaWindowRow(title: "本周", window: weekly, resetStyle: .weekday)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            AppTheme.subtleFill.opacity(0.65),
            in: RoundedRectangle(cornerRadius: AppTheme.innerRadius, style: .continuous)
        )
    }
}

private struct QuotaWindowRow: View {
    enum ResetStyle {
        case clock    // 5 小时窗：显示当天时刻
        case weekday  // 每周窗：一周内显示星期+时刻，否则显示月日
    }

    let title: String
    let window: QuotaWindow
    let resetStyle: ResetStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(usageText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            progressBar
            Text(detailText)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    // 只展示剩余：进度条同样表示剩余占比
    private var progressBar: some View {
        GeometryReader { geometry in
            let fraction = CGFloat(min(max(remainingPercent / 100, 0), 1))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(remainingLevel == .empty ? Color.white : AppTheme.subtleFill)
                    .overlay {
                        if remainingLevel == .empty {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        }
                    }
                if fraction > 0 {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(remainingColor)
                        .frame(width: max(3, geometry.size.width * fraction))
                }
            }
        }
        .frame(height: 5)
    }

    private var remainingPercent: Double { max(0, 100 - window.usedPercent) }

    private var remainingLevel: QuotaRemainingLevel {
        quotaRemainingLevel(for: remainingPercent)
    }

    private var remainingColor: Color {
        switch remainingLevel {
        case .empty:
            return .white
        case .critical:
            return AppTheme.danger
        case .low:
            return AppTheme.warning
        case .medium:
            return AppTheme.caution
        case .high:
            return AppTheme.success
        }
    }

    private var usageText: String {
        if let used = window.used, let limit = window.limit, limit > 0 {
            return "剩余 \(max(0, limit - used))/\(limit)"
        }
        return String(format: "剩余 %.0f%%", remainingPercent)
    }

    private var detailText: String {
        guard let resetsAt = window.resetsAt else { return "重置时间未知" }
        switch resetStyle {
        case .clock:
            return "\(Self.clockFormatter.string(from: resetsAt)) 重置"
        case .weekday:
            let formatter = resetsAt.timeIntervalSinceNow < 7 * 86_400
                ? Self.weekdayFormatter
                : Self.monthDayFormatter
            return "\(formatter.string(from: resetsAt)) 重置"
        }
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

private struct TokenSourceSection: View {
    let title: String
    let dayCount: Int
    let snapshot: TokenUsageSnapshot
    let currency: String
    let usdToCNYRate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionHeader(title: title, trailing: "≥ 1K")

            VStack(spacing: 0) {
                TokenCostColumnHeader(leftTitle: "来源", currency: currency)
                Divider().overlay(AppTheme.border)
                let sources = sortedTokenSourcesForDisplay(
                    snapshot,
                    last: dayCount,
                    usdToCNYRate: usdToCNYRate
                )
                if sources.isEmpty {
                    Text("暂无达到 1K Token 的来源")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    ForEach(Array(sources.enumerated()), id: \.element) { index, source in
                        SourceTokenCostRow(
                            source: source,
                            color: AppTheme.accent,
                            tokens: snapshot.totalTokens(for: source, last: dayCount),
                            estimate: snapshot.apiCost(for: source, last: dayCount),
                            currency: currency,
                            usdToCNYRate: usdToCNYRate
                        )
                        if index < sources.count - 1 {
                            Divider().padding(.leading, 12).overlay(AppTheme.border)
                        }
                    }
                }
            }
            .background(AppTheme.subtleFill.opacity(0.55), in: RoundedRectangle(cornerRadius: AppTheme.innerRadius))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .appPanel(padding: 12)
    }
}

private struct TokenShareSnapshotView: View {
    let snapshot: TokenUsageSnapshot
    let quotas: [QuotaProvider: ProviderQuota]
    let currency: String
    let usdToCNYRate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShareMetricCard(
                title: "今日 Token 消耗",
                value: snapshot.todayTokens,
                cost: shareCost(last: 1)
            )

            if !quotas.isEmpty {
                ShareQuotaSection(quotas: quotas)
            }

            VStack(alignment: .leading, spacing: 8) {
                AppSectionHeader(title: "消耗热力图", subtitle: "每天的 Token 活跃度", trailing: "近 90 天")
                ShareTokenHeatmap(days: Array(snapshot.days.suffix(90)))
            }
            .appPanel(padding: 12)

            ShareModelSection(
                snapshot: snapshot,
                currency: currency,
                usdToCNYRate: usdToCNYRate
            )

            ShareSourceSection(
                snapshot: snapshot,
                currency: currency,
                usdToCNYRate: usdToCNYRate
            )
        }
        .frame(width: 324, alignment: .leading)
        .padding(18)
        .background {
            ShareSnapshotBackground()
        }
    }

    private func shareCost(last dayCount: Int) -> String {
        formatTokenCost(
            snapshot.apiCost(last: dayCount),
            currency: currency,
            usdToCNY: usdToCNYRate
        )
    }
}

private struct ShareSnapshotBackground: View {
    private let charcoal = Color(red: 0.055, green: 0.047, blue: 0.085)
    private let plumBlack = Color(red: 0.105, green: 0.055, blue: 0.125)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [plumBlack, charcoal, Color(red: 0.075, green: 0.045, blue: 0.105)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Canvas { context, size in
                    ShareBackgroundArtwork.draw(in: &context, size: size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }
}

private enum ShareBackgroundArtwork {
    private static let orange = Color(red: 1.0, green: 0.49, blue: 0.06)
    private static let coral = Color(red: 1.0, green: 0.20, blue: 0.29)
    private static let magenta = Color(red: 0.82, green: 0.08, blue: 0.35)
    private static let plum = Color(red: 0.36, green: 0.07, blue: 0.32)
    private static let cream = Color(red: 1.0, green: 0.91, blue: 0.72)

    static func draw(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        drawTopLeft(in: &context)
        drawTopRight(in: &context, width: size.width)
        drawSideRhythm(in: &context, size: size)
        drawBottomLeft(in: &context, height: size.height)
        drawBottomRight(in: &context, size: size)
    }

    private static func drawTopLeft(in context: inout GraphicsContext) {
        fillRoundedRect(CGRect(x: -5, y: 0, width: 20, height: 11), radius: 2, color: magenta, in: &context)
        fillCircle(center: CGPoint(x: 8, y: 16), diameter: 3.2, color: coral, in: &context)
        fillCircle(center: CGPoint(x: 14, y: 16), diameter: 3.2, color: orange, in: &context)
        fillCircle(center: CGPoint(x: 8, y: 22), diameter: 3.2, color: cream.opacity(0.9), in: &context)
        fillCircle(center: CGPoint(x: 14, y: 22), diameter: 3.2, color: orange, in: &context)
        drawDiagonalBars(origin: CGPoint(x: 2, y: 31), color: coral, in: &context)
    }

    private static func drawTopRight(in context: inout GraphicsContext, width: CGFloat) {
        fillCircle(center: CGPoint(x: width + 2, y: 4), diameter: 31, color: orange, in: &context)
        fillRoundedRect(CGRect(x: width - 11, y: 16, width: 6, height: 6), radius: 1, color: plum, in: &context)
        fillCircle(center: CGPoint(x: width - 8, y: 29), diameter: 3.2, color: magenta, in: &context)
        fillCircle(center: CGPoint(x: width - 8, y: 35), diameter: 3.2, color: coral, in: &context)
        fillRoundedRect(CGRect(x: width - 9, y: 44, width: 8, height: 8), radius: 1.5, color: plum, in: &context)
    }

    private static func drawSideRhythm(in context: inout GraphicsContext, size: CGSize) {
        let leftFractions: [(CGFloat, Color)] = [
            (0.18, orange), (0.31, plum), (0.48, coral), (0.72, magenta), (0.88, coral),
        ]
        let rightFractions: [(CGFloat, Color)] = [
            (0.12, magenta), (0.25, coral), (0.39, plum), (0.58, orange), (0.76, magenta),
        ]

        for (index, item) in leftFractions.enumerated() {
            let y = size.height * item.0
            fillRoundedRect(
                CGRect(x: index.isMultiple(of: 2) ? 4 : 8, y: y, width: 5, height: 5),
                radius: 1,
                color: item.1,
                in: &context
            )
            fillCircle(center: CGPoint(x: 10, y: y + 10), diameter: 2.6, color: item.1.opacity(0.8), in: &context)
            fillCircle(center: CGPoint(x: 10, y: y + 15), diameter: 2.6, color: item.1.opacity(0.55), in: &context)
        }

        for (index, item) in rightFractions.enumerated() {
            let y = size.height * item.0
            fillRoundedRect(
                CGRect(x: size.width - (index.isMultiple(of: 2) ? 10 : 14), y: y, width: 6, height: 6),
                radius: 1,
                color: item.1,
                in: &context
            )
            fillCircle(
                center: CGPoint(x: size.width - 8, y: y + 11),
                diameter: 2.8,
                color: index.isMultiple(of: 2) ? orange : magenta,
                in: &context
            )
        }

        drawDiagonalBars(
            origin: CGPoint(x: size.width - 15, y: size.height * 0.205),
            color: magenta,
            in: &context
        )
        drawDiagonalBars(
            origin: CGPoint(x: 3, y: size.height * 0.62),
            color: orange.opacity(0.9),
            in: &context
        )
    }

    private static func drawBottomLeft(in context: inout GraphicsContext, height: CGFloat) {
        fillCircle(center: CGPoint(x: -2, y: height - 25), diameter: 31, color: coral, in: &context)
        fillRoundedRect(CGRect(x: 5, y: height - 19, width: 8, height: 8), radius: 1, color: magenta, in: &context)

        let colors = [coral, magenta, orange, cream]
        for row in 0..<3 {
            for column in 0..<3 where (row + column).isMultiple(of: 2) {
                let color = colors[(row + column) % colors.count]
                fillRoundedRect(
                    CGRect(x: CGFloat(column) * 4.5, y: height - 9 + CGFloat(row) * 4.5, width: 3.5, height: 3.5),
                    radius: 0.5,
                    color: color,
                    in: &context
                )
            }
        }
    }

    private static func drawBottomRight(in context: inout GraphicsContext, size: CGSize) {
        fillCircle(
            center: CGPoint(x: size.width + 1, y: size.height - 6),
            diameter: 32,
            color: magenta,
            in: &context
        )
        fillRoundedRect(
            CGRect(x: size.width - 15, y: size.height - 19, width: 9, height: 9),
            radius: 1.5,
            color: orange,
            in: &context
        )
        fillRoundedRect(
            CGRect(x: size.width - 8, y: size.height - 30, width: 5, height: 5),
            radius: 1,
            color: coral,
            in: &context
        )
        drawDiagonalBars(
            origin: CGPoint(x: size.width - 37, y: size.height - 11),
            color: coral.opacity(0.75),
            in: &context
        )
    }

    private static func fillRoundedRect(
        _ rect: CGRect,
        radius: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
    }

    private static func fillCircle(
        center: CGPoint,
        diameter: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )),
            with: .color(color)
        )
    }

    private static func drawDiagonalBars(
        origin: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        for offset in stride(from: CGFloat.zero, through: 8, by: 4) {
            var path = Path()
            path.move(to: CGPoint(x: origin.x + offset, y: origin.y + 7))
            path.addLine(to: CGPoint(x: origin.x + offset + 7, y: origin.y))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
        }
    }
}

private struct ShareMetricCard: View {
    let title: String
    let value: Int64
    let cost: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(cost)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(formatTokenCount(value))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .monospacedDigit()
            Text("TOKEN")
                .font(.system(size: 8, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(AppTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(padding: 14)
    }
}

private struct ShareQuotaSection: View {
    let quotas: [QuotaProvider: ProviderQuota]

    private static let displayOrder: [QuotaProvider] = [.codex, .glm, .kimi, .claude]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionHeader(title: "订阅额度", trailing: "剩余")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(Self.displayOrder.filter { quotas[$0] != nil }, id: \.self) { provider in
                    if let quota = quotas[provider] {
                        ShareQuotaCard(provider: provider, quota: quota)
                    }
                }
            }
        }
        .appPanel(padding: 12)
    }
}

private struct ShareQuotaCard: View {
    let provider: QuotaProvider
    let quota: ProviderQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(provider.iconAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(AppTheme.accent)
                Text(provider.displayName)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }

            if quota.errorMessage != nil {
                Text("暂不可用")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.warning)
            } else {
                if let window = quota.fiveHour {
                    quotaLine(title: "5h", window: window)
                }
                if let window = quota.weekly {
                    quotaLine(title: "周", window: window)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(AppTheme.subtleFill.opacity(0.65), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func quotaLine(title: String, window: QuotaWindow) -> some View {
        let remaining = max(0, 100 - window.usedPercent)
        return VStack(spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.0f%%", remaining))
                    .monospacedDigit()
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                Capsule()
                    .fill(AppTheme.border)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(quotaColor(remaining))
                            .frame(width: max(2, geometry.size.width * remaining / 100))
                    }
            }
            .frame(height: 4)
        }
    }

    private func quotaColor(_ remaining: Double) -> Color {
        switch quotaRemainingLevel(for: remaining) {
        case .empty: return .secondary.opacity(0.35)
        case .critical: return AppTheme.danger
        case .low: return AppTheme.warning
        case .medium: return AppTheme.caution
        case .high: return AppTheme.success
        }
    }
}

private struct ShareTokenHeatmap: View {
    let days: [DailyTokenUsage]

    private var weeks: [[DailyTokenUsage?]] {
        guard let first = days.first else { return [] }
        let leadingEmpty = Calendar.current.component(.weekday, from: first.date) - 1
        var cells = Array(repeating: Optional<DailyTokenUsage>.none, count: leadingEmpty)
        cells.append(contentsOf: days.map(Optional.some))
        while !cells.count.isMultiple(of: 7) { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(weeks.indices, id: \.self) { weekIndex in
                    VStack(spacing: 3) {
                        ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                            heatmapCell(weeks[weekIndex][dayIndex])
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 4) {
                Text("少")
                ForEach(0..<4) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(level: level))
                        .overlay {
                            if level == 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.gray.opacity(0.28), lineWidth: 0.7)
                            }
                        }
                        .frame(width: 9, height: 9)
                }
                Text("多")
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func heatmapCell(_ day: DailyTokenUsage?) -> some View {
        if let day {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(heatColor(level: tokenHeatLevel(day.totalTokens)))
                .overlay {
                    if day.totalTokens == 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.gray.opacity(0.28), lineWidth: 0.7)
                    }
                }
                .frame(width: 18, height: 18)
        } else {
            Color.clear.frame(width: 18, height: 18)
        }
    }

    private func heatColor(level: Int) -> Color {
        switch level {
        case 1: return AppTheme.accent.opacity(0.28)
        case 2: return AppTheme.accent.opacity(0.62)
        case 3: return AppTheme.accent
        default: return AppTheme.elevatedSurface
        }
    }
}

private struct ShareModelSection: View {
    let snapshot: TokenUsageSnapshot
    let currency: String
    let usdToCNYRate: Double

    private var allModels: [ModelUsageDisplaySummary] {
        sortedModelUsagesForDisplay(
            snapshot.modelUsages(last: 1),
            usdToCNYRate: usdToCNYRate,
            minimumTokens: 1
        )
    }

    private var models: [ModelUsageDisplaySummary] { Array(allModels.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionHeader(title: "今日模型", trailing: allModels.count > 5 ? "Top 5" : nil)
            if models.isEmpty {
                ShareEmptyRow(text: "今日暂无模型消耗")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(models.enumerated()), id: \.element.id) { index, usage in
                        ShareUsageRow(
                            title: usage.displayName,
                            tokenCount: usage.tokens.totalTokens,
                            cost: formatTokenCost(
                                usage.estimate,
                                currency: currency,
                                usdToCNY: usdToCNYRate
                            )
                        )
                        if index < models.count - 1 {
                            Divider().overlay(AppTheme.border)
                        }
                    }
                }
            }
        }
        .appPanel(padding: 12)
    }
}

private struct ShareSourceSection: View {
    let snapshot: TokenUsageSnapshot
    let currency: String
    let usdToCNYRate: Double

    private var sources: [TokenSource] {
        Array(sortedTokenSourcesForDisplay(
            snapshot,
            last: 1,
            usdToCNYRate: usdToCNYRate,
            minimumTokens: 1
        ).prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionHeader(title: "今日工具")
            if sources.isEmpty {
                ShareEmptyRow(text: "今日暂无工具消耗")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sources.enumerated()), id: \.element) { index, source in
                        ShareUsageRow(
                            title: source.displayName,
                            tokenCount: snapshot.totalTokens(for: source, last: 1),
                            cost: formatTokenCost(
                                snapshot.apiCost(for: source, last: 1),
                                currency: currency,
                                usdToCNY: usdToCNYRate
                            )
                        )
                        if index < sources.count - 1 {
                            Divider().overlay(AppTheme.border)
                        }
                    }
                }
            }
        }
        .appPanel(padding: 12)
    }
}

private struct ShareUsageRow: View {
    let title: String
    let tokenCount: Int64
    let cost: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatTokenCount(tokenCount))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
                .layoutPriority(1)
            Text(cost)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(width: 116, alignment: .trailing)
                .layoutPriority(2)
        }
        .padding(.vertical, 7)
    }
}

private struct ShareEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 34)
    }
}

@MainActor
enum TokenShareSnapshotRenderer {
    static func copyToPasteboard(
        snapshot: TokenUsageSnapshot,
        quotas: [QuotaProvider: ProviderQuota],
        currency: String,
        usdToCNYRate: Double
    ) -> Bool {
        guard let pngData = renderPNGData(
            snapshot: snapshot,
            quotas: quotas,
            currency: currency,
            usdToCNYRate: usdToCNYRate
        ) else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(pngData, forType: .png)
    }

    static func renderPNGData(
        snapshot: TokenUsageSnapshot,
        quotas: [QuotaProvider: ProviderQuota],
        currency: String,
        usdToCNYRate: Double
    ) -> Data? {
        let content = TokenShareSnapshotView(
            snapshot: snapshot,
            quotas: quotas,
            currency: currency,
            usdToCNYRate: usdToCNYRate
        )
        .environment(\.colorScheme, currentColorScheme)

        let renderer = ImageRenderer(content: content)
        // 360pt × 3 导出 1080px 宽，适合手机竖屏和常见社交平台分享。
        renderer.scale = 3
        // 强制标准动态范围与不透明输出，避免 HDR 屏幕上透明位图边缘出现彩色噪点。
        renderer.isOpaque = true
        renderer.colorMode = .nonLinear
        if #available(macOS 26.0, *) {
            renderer.allowedDynamicRange = .standard
        }
        guard let image = renderer.cgImage,
              let pngData = standardSRGBPNGData(from: image) else { return nil }
        return pngData
    }

    private static func standardSRGBPNGData(from source: CGImage) -> Data? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: source.width,
                  height: source.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }

        // 先铺底再绘制到无 Alpha 的 sRGB 位图，彻底消除透明区域中的未定义 RGB 数据。
        context.setFillColor(CGColor(gray: currentColorScheme == .dark ? 0 : 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let normalizedImage = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: normalizedImage).representation(using: .png, properties: [:])
    }

    private static var currentColorScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

private enum TokenListLayout {
    static let tokenWidth: CGFloat = 70
    static let breakdownWidth: CGFloat = 60
    static let usdWidth: CGFloat = 68
    static let cnyWidth: CGFloat = 78
    static let columnSpacing: CGFloat = 8
    static let currencySpacing: CGFloat = 8
    static let panelBackground = AppTheme.subtleFill

    static func costWidth(for currency: String) -> CGFloat {
        switch currency {
        case "usd": return usdWidth
        case "cny": return cnyWidth
        default: return usdWidth + currencySpacing + cnyWidth
        }
    }
}

let minimumDisplayedTokenCount: Int64 = 1_000

struct ModelUsageDisplaySummary: Identifiable {
    let model: String
    let usages: [ModelTokenUsage]

    var id: String { normalizedModelName(model) }
    var displayName: String { model.isEmpty ? "未知模型" : model }
    var tokens: TokenBreakdown { usages.reduce(into: TokenBreakdown()) { $0 += $1.tokens } }
    var estimate: TokenCostEstimate { estimateAPICost(for: usages) }

    var channelCount: Int {
        Set(usages.map { "\($0.source.rawValue)|\($0.provider.lowercased())" }).count
    }

    var channelSummary: String {
        if channelCount == 1, let usage = usages.first {
            return "\(usage.source.displayName) · \(usage.provider)"
        }
        let sources = Set(usages.map(\.source))
        let sourceNames = TokenSource.allCases
            .filter { sources.contains($0) }
            .map(\.displayName)
            .joined(separator: "、")
        return "\(sourceNames) · \(channelCount) 个渠道"
    }

    var channelDetails: String {
        var labelsByKey: [String: String] = [:]
        for usage in usages {
            let key = "\(usage.source.rawValue)|\(usage.provider.lowercased())"
            labelsByKey[key] = "\(usage.source.displayName) · \(usage.provider)"
        }
        return labelsByKey.sorted { $0.key < $1.key }.map(\.value).joined(separator: "、")
    }
}

private func normalizedModelName(_ model: String) -> String {
    model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func preferredModelName(in usages: [ModelTokenUsage]) -> String {
    let names = Set(usages.map { $0.model.trimmingCharacters(in: .whitespacesAndNewlines) })
    return names.sorted { lhs, rhs in
        let lhsIsLowercase = lhs == lhs.lowercased()
        let rhsIsLowercase = rhs == rhs.lowercased()
        if lhsIsLowercase != rhsIsLowercase {
            return lhsIsLowercase
        }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }.first ?? ""
}

func sortedModelUsagesForDisplay(
    _ usages: [ModelTokenUsage],
    usdToCNYRate: Double,
    minimumTokens: Int64 = minimumDisplayedTokenCount
) -> [ModelUsageDisplaySummary] {
    let grouped = Dictionary(grouping: usages) { normalizedModelName($0.model) }
        .values
        .map { ModelUsageDisplaySummary(model: preferredModelName(in: $0), usages: $0) }

    return grouped.filter { $0.tokens.totalTokens >= minimumTokens }.sorted { lhs, rhs in
        let lhsEstimate = lhs.estimate
        let rhsEstimate = rhs.estimate
        let lhsIsPriced = lhsEstimate.pricedTokens > 0
        let rhsIsPriced = rhsEstimate.pricedTokens > 0

        if lhsIsPriced != rhsIsPriced {
            return lhsIsPriced
        }
        let lhsCost = lhsEstimate.totalCNY(usdToCNY: usdToCNYRate)
        let rhsCost = rhsEstimate.totalCNY(usdToCNY: usdToCNYRate)
        if lhsCost != rhsCost {
            return lhsCost > rhsCost
        }
        if lhs.tokens.totalTokens != rhs.tokens.totalTokens {
            return lhs.tokens.totalTokens > rhs.tokens.totalTokens
        }
        return lhs.model.localizedCaseInsensitiveCompare(rhs.model) == .orderedAscending
    }
}

func sortedTokenSourcesForDisplay(
    _ snapshot: TokenUsageSnapshot,
    last dayCount: Int,
    usdToCNYRate: Double,
    minimumTokens: Int64 = minimumDisplayedTokenCount
) -> [TokenSource] {
    TokenSource.allCases.filter {
        snapshot.totalTokens(for: $0, last: dayCount) >= minimumTokens
    }.sorted { lhs, rhs in
        let lhsEstimate = snapshot.apiCost(for: lhs, last: dayCount)
        let rhsEstimate = snapshot.apiCost(for: rhs, last: dayCount)
        let lhsIsPriced = lhsEstimate.pricedTokens > 0
        let rhsIsPriced = rhsEstimate.pricedTokens > 0

        if lhsIsPriced != rhsIsPriced {
            return lhsIsPriced
        }
        let lhsCost = lhsEstimate.totalCNY(usdToCNY: usdToCNYRate)
        let rhsCost = rhsEstimate.totalCNY(usdToCNY: usdToCNYRate)
        if lhsCost != rhsCost {
            return lhsCost > rhsCost
        }
        let lhsTokens = snapshot.totalTokens(for: lhs, last: dayCount)
        let rhsTokens = snapshot.totalTokens(for: rhs, last: dayCount)
        if lhsTokens != rhsTokens {
            return lhsTokens > rhsTokens
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

private struct TokenCostColumnHeader: View {
    let leftTitle: String
    let currency: String

    var body: some View {
        HStack(spacing: TokenListLayout.columnSpacing) {
            Text(leftTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("TOKEN")
                .frame(width: TokenListLayout.tokenWidth, alignment: .trailing)
            TokenCurrencyHeader(currency: currency)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct TokenCurrencyHeader: View {
    let currency: String

    var body: some View {
        HStack(spacing: currency == "both" ? TokenListLayout.currencySpacing : 0) {
            if currency != "cny" {
                Text("USD")
                    .frame(width: TokenListLayout.usdWidth, alignment: .trailing)
            }
            if currency != "usd" {
                Text("CNY")
                    .frame(width: TokenListLayout.cnyWidth, alignment: .trailing)
            }
        }
        .frame(width: TokenListLayout.costWidth(for: currency), alignment: .trailing)
    }
}

private struct TokenCostColumns: View {
    let estimate: TokenCostEstimate
    let currency: String
    let usdToCNYRate: Double
    let showsCurrencySymbols: Bool

    var body: some View {
        Group {
            if estimate.pricedTokens > 0 {
                HStack(spacing: currency == "both" ? TokenListLayout.currencySpacing : 0) {
                    if currency != "cny" {
                        Text(costText(formatTokenCostUSD(estimate, usdToCNY: usdToCNYRate), symbol: "$"))
                            .frame(width: TokenListLayout.usdWidth, alignment: .trailing)
                    }
                    if currency != "usd" {
                        Text(costText(formatTokenCostCNY(estimate, usdToCNY: usdToCNYRate), symbol: "¥"))
                            .frame(width: TokenListLayout.cnyWidth, alignment: .trailing)
                    }
                }
            } else {
                Text("未定价")
                    .frame(width: TokenListLayout.costWidth(for: currency), alignment: .trailing)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .frame(width: TokenListLayout.costWidth(for: currency), alignment: .trailing)
    }

    private func costText(_ amount: String, symbol: String) -> String {
        showsCurrencySymbols ? "\(symbol)\(amount)" : amount
    }
}

private struct SourceTokenCostRow: View {
    let source: TokenSource
    let color: Color
    let tokens: Int64
    let estimate: TokenCostEstimate
    let currency: String
    let usdToCNYRate: Double

    var body: some View {
        HStack(spacing: TokenListLayout.columnSpacing) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(source.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatTokenCount(tokens))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: TokenListLayout.tokenWidth, alignment: .trailing)

            TokenCostColumns(
                estimate: estimate,
                currency: currency,
                usdToCNYRate: usdToCNYRate,
                showsCurrencySymbols: false
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct TokenSummaryCard: View {
    let title: String
    let value: Int64
    let cost: String
    let dayCount: Int
    let devices: [DeviceTokenUsageSummary]
    let showsDevices: Bool

    private var sortedDevices: [DeviceTokenUsageSummary] {
        devices.sorted {
            let lhsTokens = $0.totalTokens(last: dayCount)
            let rhsTokens = $1.totalTokens(last: dayCount)
            if lhsTokens == rhsTokens {
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return lhsTokens > rhsTokens
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.accent)
                    .frame(width: 18, height: 3)
            }
            Text(formatTokenCount(value))
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .tracking(-0.35)
                .monospacedDigit()
            Text(cost)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if showsDevices && !sortedDevices.isEmpty {
                Divider()
                    .overlay(AppTheme.border)
                    .padding(.vertical, 2)
                VStack(spacing: 2) {
                    ForEach(sortedDevices) { device in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(AppTheme.accent.opacity(device.isCurrentDevice ? 1 : 0.45))
                                .frame(width: 4, height: 4)
                            Text(device.displayName)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(formatTokenCount(device.totalTokens(last: dayCount)))
                                .monospacedDigit()
                                .layoutPriority(1)
                        }
                        .help("\(device.displayName)：\(formatTokenCount(device.totalTokens(last: dayCount))) Token")
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel(padding: 12)
    }
}

private struct ModelTokenCostRow: View {
    let usage: ModelUsageDisplaySummary
    let currency: String
    let usdToCNYRate: Double
    @State private var isHovered = false

    private var estimate: TokenCostEstimate {
        usage.estimate
    }

    var body: some View {
        HStack(spacing: TokenListLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                Text(usage.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fontWeight(.medium)
                Text(usage.channelSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Text(formatTokenCount(usage.tokens.totalTokens))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: TokenListLayout.tokenWidth, alignment: .trailing)

            TokenCostColumns(
                estimate: estimate,
                currency: currency,
                usdToCNYRate: usdToCNYRate,
                showsCurrencySymbols: false
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isHovered ? AppTheme.accentSoft.opacity(0.55) : Color.clear)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .help("\(usage.channelDetails)\n输入 \(formatTokenCount(usage.tokens.input)) · 缓存读取 \(formatTokenCount(usage.tokens.cachedInput)) · 缓存写入 \(formatTokenCount(usage.tokens.cacheWrite)) · 输出/推理 \(formatTokenCount(usage.tokens.output + usage.tokens.reasoning))")
    }
}

private struct TokenCalendarHeatmap: View {
    let days: [DailyTokenUsage]
    let currency: String
    let usdToCNYRate: Double
    @State private var hoverState = TokenHeatmapHoverState()

    private var weeks: [[DailyTokenUsage?]] {
        guard let first = days.first else { return [] }
        let leadingEmpty = Calendar.current.component(.weekday, from: first.date) - 1
        var cells = Array(repeating: Optional<DailyTokenUsage>.none, count: leadingEmpty)
        cells.append(contentsOf: days.map(Optional.some))
        while !cells.count.isMultiple(of: 7) { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let spacing: CGFloat = 3
                let cellSize = heatmapCellSize(
                    availableWidth: geometry.size.width,
                    weekCount: weeks.count,
                    spacing: spacing
                )

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        VStack(spacing: spacing) {
                            ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                                heatmapCell(weeks[weekIndex][dayIndex], size: cellSize)
                            }
                        }
                    }
                }
            }
            .frame(height: 98)

            HStack(spacing: 4) {
                Spacer()
                Text("少").foregroundColor(.secondary)
                ForEach(0..<4) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(level: level))
                        .overlay {
                            if level == 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.gray.opacity(0.32), lineWidth: 0.7)
                            }
                        }
                        .frame(width: 11, height: 11)
                }
                Text("多").foregroundColor(.secondary)
            }
            .font(.caption2)

            Group {
                if let selectedDay = hoverState.day ?? days.last {
                    HeatmapHoverDetail(
                        day: selectedDay,
                        currency: currency,
                        usdToCNYRate: usdToCNYRate
                    )
                } else {
                Text("暂无 Token 数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private func heatmapCell(_ day: DailyTokenUsage?, size: CGFloat) -> some View {
        if let day {
            RoundedRectangle(cornerRadius: max(2, size * 0.22))
                .fill(heatColor(for: day.totalTokens))
                .overlay {
                    if day.totalTokens == 0 {
                        RoundedRectangle(cornerRadius: max(2, size * 0.22))
                            .stroke(Color.gray.opacity(0.32), lineWidth: 0.7)
                    }
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .onHover { isHovered in
                    hoverState.update(day: day, isHovered: isHovered)
                }
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    private func heatmapCellSize(
        availableWidth: CGFloat,
        weekCount: Int,
        spacing: CGFloat
    ) -> CGFloat {
        guard weekCount > 0 else { return 0 }
        let totalSpacing = CGFloat(max(weekCount - 1, 0)) * spacing
        return max(8, (availableWidth - totalSpacing) / CGFloat(weekCount))
    }

    private func heatColor(for tokenCount: Int64) -> Color {
        heatColor(level: tokenHeatLevel(tokenCount))
    }

    private func heatColor(level: Int) -> Color {
        switch level {
        case 1: return AppTheme.accent.opacity(0.28)
        case 2: return AppTheme.accent.opacity(0.62)
        case 3: return AppTheme.accent
        default: return AppTheme.elevatedSurface
        }
    }

}

struct TokenHeatmapHoverState: Equatable {
    private(set) var day: DailyTokenUsage?

    mutating func update(day candidate: DailyTokenUsage, isHovered: Bool) {
        if isHovered {
            day = candidate
        } else if day?.id == candidate.id {
            day = nil
        }
    }
}

private struct HeatmapHoverDetail: View {
    let day: DailyTokenUsage
    let currency: String
    let usdToCNYRate: Double

    private var modelUsages: [ModelUsageDisplaySummary] {
        sortedModelUsagesForDisplay(
            day.modelUsages,
            usdToCNYRate: usdToCNYRate
        )
    }

    private var totalEstimate: TokenCostEstimate {
        estimateAPICost(for: day.modelUsages)
    }

    private var dayTokens: TokenBreakdown {
        day.modelUsages.reduce(into: TokenBreakdown()) { $0 += $1.tokens }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(formattedDate(day.date))
                        .fontWeight(.semibold)
                    Text("悬停日期查看当日模型")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HeatmapBreakdownCell(text: formatTokenCount(dayTokens.input))
                HeatmapBreakdownCell(text: formatTokenCount(dayTokens.cachedInput))
                HeatmapBreakdownCell(text: formatTokenCount(dayTokens.output + dayTokens.reasoning))

                Text(formatTokenCount(day.totalTokens))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: TokenListLayout.tokenWidth, alignment: .trailing)

                TokenCostColumns(
                    estimate: totalEstimate,
                    currency: currency,
                    usdToCNYRate: usdToCNYRate,
                    showsCurrencySymbols: true
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if modelUsages.isEmpty {
                Text("当日无模型消耗")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            } else {
                HeatmapColumnHeader(currency: currency)

                ForEach(Array(modelUsages.prefix(5))) { usage in
                    HeatmapModelCostRow(
                        usage: usage,
                        currency: currency,
                        usdToCNYRate: usdToCNYRate
                    )
                }

                if modelUsages.count > 5 {
                    Text("另有 \(modelUsages.count - 5) 个模型")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day())
    }
}

private struct HeatmapModelCostRow: View {
    let usage: ModelUsageDisplaySummary
    let currency: String
    let usdToCNYRate: Double

    private var tokens: TokenBreakdown { usage.tokens }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(sourceColor)
                    .frame(width: 6, height: 6)
                Text(usage.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(usage.channelCount == 1 ? (usage.usages.first?.source.displayName ?? "") : "\(usage.channelCount) 个渠道")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HeatmapBreakdownCell(text: formatTokenCount(tokens.input))
            HeatmapBreakdownCell(text: formatTokenCount(tokens.cachedInput))
            HeatmapBreakdownCell(text: formatTokenCount(tokens.output + tokens.reasoning))

            Text(formatTokenCount(usage.tokens.totalTokens))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: TokenListLayout.tokenWidth, alignment: .trailing)

            TokenCostColumns(
                estimate: usage.estimate,
                currency: currency,
                usdToCNYRate: usdToCNYRate,
                showsCurrencySymbols: true
            )
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .help("\(usage.channelDetails)\n输入 \(formatTokenCount(tokens.input)) · 缓存读取 \(formatTokenCount(tokens.cachedInput)) · 缓存写入 \(formatTokenCount(tokens.cacheWrite)) · 输出/推理 \(formatTokenCount(tokens.output + tokens.reasoning))")
    }

    private var sourceColor: Color {
        AppTheme.accent
    }
}

private struct HeatmapBreakdownCell: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(width: TokenListLayout.breakdownWidth, alignment: .trailing)
    }
}

private struct HeatmapColumnHeader: View {
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            Text("模型")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("输入")
                .frame(width: TokenListLayout.breakdownWidth, alignment: .trailing)
            Text("缓存")
                .frame(width: TokenListLayout.breakdownWidth, alignment: .trailing)
            Text("输出")
                .frame(width: TokenListLayout.breakdownWidth, alignment: .trailing)
            Text("总量")
                .frame(width: TokenListLayout.tokenWidth, alignment: .trailing)
            TokenCurrencyHeader(currency: currency)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

// MARK: - Shared Components

struct DetailHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AppIconButton(systemName: "gearshape", help: "打开设置") {
                AppWindowActions.openSettings()
            }
            AppIconButton(systemName: "power", help: "退出 ZFStatMenus") {
                AppWindowActions.quit()
            }
        }
    }
}

struct ProcessRow: View {
    let icon: NSImage?
    let name: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack(spacing: 8) {
            ProcessIcon(icon: icon)
            Text(name)
                .lineLimit(1)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(valueColor)
        }
    }
}

struct ProcessIcon: View {
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AppTheme.subtleFill)
                    .overlay {
                        Image(systemName: "app")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 20, height: 20)
    }
}

struct BarChartView: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if values.isEmpty {
                Text("无数据").foregroundColor(.secondary)
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                let maxVal = max(values.max() ?? 1, 0.001)
                let barWidth = max(1, (geo.size.width - CGFloat(values.count - 1)) / CGFloat(values.count))
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, val in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color.opacity(0.28 + 0.72 * (val / maxVal)))
                            .frame(width: barWidth, height: max(1, geo.size.height * (val / maxVal)))
                    }
                }
            }
        }
    }
}

// MARK: - MonitorHolder

final class MonitorHolder: ObservableObject {
    @Published var cpu: CPUMetric = .zero
    @Published var memory: MemoryMetric = .zero
    @Published var network: NetworkMetric = .zero
    @Published var cpuHistory: [Double] = []
    @Published var memHistory: [Double] = []
    @Published var netDownHistory: [Double] = []
    @Published var netUpHistory: [Double] = []
    @Published var topCPU: [TopProcess] = []
    @Published var topMemory: [TopProcess] = []
    @Published var topNetwork: [NetworkProcess] = []

    private let monitorManager: MonitorManager
    private var timer: Timer?
    private var observingType: StatusItemType?

    init(monitorManager: MonitorManager) {
        self.monitorManager = monitorManager
    }

    func start(_ type: StatusItemType) {
        observingType = type
        monitorManager.processMonitor.activate(type)

        switch type {
        case .cpu:
            cpu = monitorManager.latestCPU
            cpuHistory = monitorManager.cpuHistory
            topCPU = monitorManager.processMonitor.topCPU()
        case .memory:
            memory = monitorManager.latestMemory
            memHistory = monitorManager.memUsedHistory
            topMemory = monitorManager.processMonitor.topMemory()
        case .network:
            network = monitorManager.latestNetwork
            netDownHistory = monitorManager.netDownHistory
            netUpHistory = monitorManager.netUpHistory
            topNetwork = monitorManager.processMonitor.topNetwork()
        case .token:
            break
        }

        timer?.invalidate()
        let refreshTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
    }

    func stop() {
        if let observingType {
            monitorManager.processMonitor.deactivate(observingType)
        }
        timer?.invalidate()
        timer = nil
        observingType = nil
    }

    private func refresh() {
        guard let type = observingType else { return }
        switch type {
        case .cpu:
            cpu = monitorManager.latestCPU
            cpuHistory = monitorManager.cpuHistory
            topCPU = monitorManager.processMonitor.topCPU()
        case .memory:
            memory = monitorManager.latestMemory
            memHistory = monitorManager.memUsedHistory
            topMemory = monitorManager.processMonitor.topMemory()
        case .network:
            network = monitorManager.latestNetwork
            netDownHistory = monitorManager.netDownHistory
            netUpHistory = monitorManager.netUpHistory
            topNetwork = monitorManager.processMonitor.topNetwork()
        case .token:
            break
        }
    }
}

// MARK: - Format helpers

func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    return formatter.string(fromByteCount: Int64(bytes))
}

func formatSpeed(_ bytesPerSec: Double) -> String {
    if bytesPerSec >= 1_048_576 {
        return String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
    } else if bytesPerSec >= 1024 {
        return String(format: "%.1f KB/s", bytesPerSec / 1024)
    } else {
        return String(format: "%.0f B/s", bytesPerSec)
    }
}
