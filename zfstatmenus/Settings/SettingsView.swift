import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case statusBar
    case token
    case sync
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .statusBar: return "状态栏"
        case .token: return "Token"
        case .sync: return "同步"
        case .about: return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "采样与应用行为"
        case .statusBar: return "栏目与显示方式"
        case .token: return "来源、费用与刷新"
        case .sync: return "多设备数据汇总"
        case .about: return "版本与数据边界"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .statusBar: return "menubar.rectangle"
        case .token: return "dollarsign.circle.fill"
        case .sync: return "arrow.triangle.2.circlepath.icloud"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @AppStorage("monitorInterval") private var monitorInterval = 0.5
    @AppStorage("showSparkline") private var showSparkline = true
    @AppStorage("showValueText") private var showValueText = true
    @State private var selection: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ZFStatMenus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("系统与 Token 监控")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 12)

                VStack(spacing: 4) {
                    ForEach(SettingsPane.allCases) { pane in
                        Button {
                            selection = pane
                        } label: {
                            HStack(spacing: 10) {
                                Group {
                                    if pane == .token {
                                        Image("TokenGlyph")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: pane.systemImage)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                }
                                    .foregroundStyle(selection == pane ? AppTheme.accent : .primary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(pane.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(pane.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 45)
                            .contentShape(Rectangle())
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selection == pane ? AppTheme.accentSoft : Color.clear)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == pane ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)

                Spacer(minLength: 8)

                Divider()
                Text("版本 0.1.0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(AppTheme.sidebar)
            .frame(width: 210)

            Divider().overlay(AppTheme.border)

            Group {
                switch selection {
                case .general:
                    GeneralSettingsView(monitorInterval: $monitorInterval)
                case .statusBar:
                    StatusBarSettingsView(showSparkline: $showSparkline, showValueText: $showValueText)
                case .token:
                    TokenSettingsView()
                case .sync:
                    TokenSyncSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.canvas)
        }
        .frame(width: 790, height: 550)
        .background(AppTheme.canvas)
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.5)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(AppTheme.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.canvas)
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppSectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
            Divider().overlay(AppTheme.border)
            VStack(spacing: 0) {
                content
            }
        }
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 20)
            control
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 15).overlay(AppTheme.border)
    }
}

struct GeneralSettingsView: View {
    @Binding var monitorInterval: Double

    var body: some View {
        SettingsPage(
            title: "通用",
            subtitle: "控制系统指标采样频率与基础运行信息。"
        ) {
            SettingsGroup(title: "实时监控", subtitle: "默认每 0.5 秒刷新；进程排行约每秒生成一次有效采样。") {
                SettingsRow(title: "采样间隔", detail: "CPU、内存与网络刷新频率") {
                    Picker("", selection: $monitorInterval) {
                        Text("实时").tag(0.5)
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                        Text("5 秒").tag(5.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            SettingsGroup(title: "应用信息") {
                SettingsRow(title: "版本", detail: "当前安装的 ZFStatMenus 版本") {
                    Text("0.1.0")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingsRow(title: "运行方式", detail: "常驻菜单栏，不显示 Dock 图标") {
                    AppStatusBadge(title: "菜单栏应用", systemName: "menubar.rectangle")
                }
            }
        }
    }
}

struct StatusBarSettingsView: View {
    @Binding var showSparkline: Bool
    @Binding var showValueText: Bool
    @State private var enabledCPU = true
    @State private var enabledMemory = true
    @State private var enabledNetwork = true
    @State private var enabledToken = false

    var body: some View {
        SettingsPage(
            title: "状态栏",
            subtitle: "选择常驻项目，并控制紧凑指标的显示方式。"
        ) {
            SettingsGroup(title: "显示项目", subtitle: "关闭的项目不会占用菜单栏空间。") {
                StatusItemToggle(title: "CPU", detail: "总使用率与核心活动", icon: .system("cpu"), isOn: $enabledCPU)
                SettingsDivider()
                StatusItemToggle(title: "内存", detail: "已用容量与占用比例", icon: .system("memorychip"), isOn: $enabledMemory)
                SettingsDivider()
                StatusItemToggle(title: "网络", detail: "实时上传与下载速率", icon: .system("arrow.up.arrow.down"), isOn: $enabledNetwork)
                SettingsDivider()
                StatusItemToggle(title: "Token", detail: "今日 AI 编程 Token 消耗", icon: .asset("TokenGlyph"), isOn: $enabledToken)
            }

            SettingsGroup(title: "显示细节") {
                SettingsRow(title: "迷你图表", detail: "在支持的状态项中显示实时走势") {
                    Toggle("", isOn: $showSparkline).labelsHidden().toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsRow(title: "数值文字", detail: "显示当前容量、速率或 Token 数") {
                    Toggle("", isOn: $showValueText).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .onAppear { loadPrefs() }
        .onChange(of: enabledCPU) { _ in savePrefs() }
        .onChange(of: enabledMemory) { _ in savePrefs() }
        .onChange(of: enabledNetwork) { _ in savePrefs() }
        .onChange(of: enabledToken) { _ in savePrefs() }
    }

    private func loadPrefs() {
        let items = AppPreferences.shared.enabledStatusItems
        enabledCPU = items.contains(.cpu)
        enabledMemory = items.contains(.memory)
        enabledNetwork = items.contains(.network)
        enabledToken = items.contains(.token)
    }

    private func savePrefs() {
        var items: Set<StatusItemType> = []
        if enabledCPU { items.insert(.cpu) }
        if enabledMemory { items.insert(.memory) }
        if enabledNetwork { items.insert(.network) }
        if enabledToken { items.insert(.token) }
        AppPreferences.shared.enabledStatusItems = items
    }
}

private enum StatusItemIcon {
    case system(String)
    case asset(String)
}

private struct StatusItemToggle: View {
    let title: String
    let detail: String
    let icon: StatusItemIcon
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            HStack(spacing: 12) {
                Group {
                    switch icon {
                    case let .system(name):
                        Image(systemName: name)
                    case let .asset(name):
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                }
                .foregroundStyle(isOn ? AppTheme.accent : .secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}

struct TokenSettingsView: View {
    @ObservedObject private var tokenUsageMonitor = TokenUsageMonitor.shared
    @ObservedObject private var exchangeRateMonitor = ExchangeRateMonitor.shared
    @AppStorage("tokenRefreshInterval") private var tokenRefreshInterval = 60.0
    @AppStorage("tokenDisplayCurrency") private var currency = "both"
    @AppStorage("tokenUSDToCNYRate") private var usdToCNYRate = 7.2
    @AppStorage("tokenRateAutoEnabled") private var rateAutoEnabled = true
    @State private var openCodeEnabled = true
    @State private var zcodeEnabled = true
    @State private var codexEnabled = true
    @State private var claudeEnabled = true
    @State private var kimiEnabled = true
    @State private var showRecalculateConfirmation = false
    @State private var recalculationFeedback: String?
    @State private var recalculationHasError = false
    // 订阅额度
    @State private var kimiQuotaEnabled = true
    @State private var codexQuotaEnabled = true
    @State private var claudeQuotaEnabled = true
    @State private var glmQuotaEnabled = true
    @State private var glmAPIKeyInput = ""
    @State private var hasGLMAPIKey = false
    @State private var glmRegion = "cn"
    @State private var claudeCredentialStatus = "正在检测…"
    @State private var codexCredentialStatus = "正在检测…"
    @State private var kimiCredentialStatus = "正在检测…"
    @State private var quotaRefreshTask: Task<Void, Never>?

    var body: some View {
        SettingsPage(
            title: "Token",
            subtitle: "管理本地数据来源、刷新节奏和 API 等价费用显示。"
        ) {
            SettingsGroup(title: "统计来源", subtitle: "只读取各工具保存在本机的统计数据。") {
                SourceToggle(title: "OpenCode", path: "~/.local/share/opencode/opencode.db", isOn: $openCodeEnabled)
                SettingsDivider()
                SourceToggle(title: "ZCode", path: "~/.zcode/cli/db/db.sqlite", isOn: $zcodeEnabled)
                SettingsDivider()
                SourceToggle(title: "Codex CLI", path: "~/.codex/sessions/", isOn: $codexEnabled)
                SettingsDivider()
                SourceToggle(title: "Claude Code", path: "~/.claude/projects/", isOn: $claudeEnabled)
                SettingsDivider()
                SourceToggle(title: "Kimi CLI", path: "~/.kimi-code/sessions/", isOn: $kimiEnabled)
            }

            SettingsGroup(
                title: "订阅额度",
                subtitle: "在 Token 弹窗显示各平台 5 小时与每周额度；手动填写的凭据仅保存于本机 Keychain。"
            ) {
                SettingsRow(title: "Kimi", detail: kimiCredentialStatus) {
                    Toggle("", isOn: $kimiQuotaEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsRow(title: "GPT（Codex）", detail: codexCredentialStatus) {
                    Toggle("", isOn: $codexQuotaEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsRow(title: "Claude", detail: claudeCredentialStatus) {
                    Toggle("", isOn: $claudeQuotaEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsRow(title: "GLM", detail: "智谱 Coding Plan") {
                    Toggle("", isOn: $glmQuotaEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsRow(title: "GLM API Key", detail: "在智谱开放平台创建 API Key") {
                    SecureField(hasGLMAPIKey ? "已安全保存，输入以更新" : "粘贴 API Key", text: $glmAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                SettingsDivider()
                SettingsRow(title: "GLM 接口分区", detail: "国内账号 open.bigmodel.cn，国际账号 api.z.ai") {
                    Picker("", selection: $glmRegion) {
                        Text("国内").tag("cn")
                        Text("国际").tag("global")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }

            SettingsGroup(title: "刷新与费用") {
                SettingsRow(title: "Token 刷新", detail: "扫描新增和变更的本地记录") {
                    Picker("", selection: $tokenRefreshInterval) {
                        Text("30 秒").tag(30.0)
                        Text("1 分钟").tag(60.0)
                        Text("5 分钟").tag(300.0)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsDivider()
                SettingsRow(title: "显示币种", detail: "模型费用按照第一方公开 API 单价估算") {
                    Picker("", selection: $currency) {
                        Text("USD + CNY").tag("both")
                        Text("仅 USD").tag("usd")
                        Text("仅 CNY").tag("cny")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsDivider()
                SettingsRow(title: "自动获取汇率", detail: rateAutoDetail) {
                    Toggle("", isOn: $rateAutoEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsRow(title: "USD/CNY 汇率", detail: rateAutoEnabled ? "由自动获取维护，可手动刷新" : "仅用于把美元价格换算为人民币") {
                    HStack(spacing: 8) {
                        if rateAutoEnabled {
                            if exchangeRateMonitor.isFetching {
                                ProgressView().controlSize(.small)
                            } else {
                                Button {
                                    exchangeRateMonitor.refresh()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("立即刷新汇率")
                            }
                        }
                        TextField("7.20", value: $usdToCNYRate, format: .number.precision(.fractionLength(2...4)))
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .disabled(rateAutoEnabled)
                    }
                }
            }

            SettingsGroup(
                title: "数据维护",
                subtitle: "清除解析缓存并重新扫描近一年本地记录；启用同步时会用新 revision 覆盖本设备的远程快照。"
            ) {
                SettingsRow(title: "重新计算 Token 用量", detail: "用于修复解析规则更新或本地缓存异常") {
                    HStack(spacing: 8) {
                        if tokenUsageMonitor.isRecalculating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button(tokenUsageMonitor.isRecalculating ? "正在重算" : "重新计算") {
                            showRecalculateConfirmation = true
                        }
                        .disabled(tokenUsageMonitor.isRecalculating)
                    }
                }
            }

            if let recalculationFeedback {
                Label(
                    recalculationFeedback,
                    systemImage: recalculationHasError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(recalculationHasError ? AppTheme.danger : AppTheme.success)
                .padding(.horizontal, 2)
            }

            Label("费用是标准 API 等价估算，不代表订阅服务的实际扣费。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
        .onAppear {
            loadSources()
            loadQuotaSettings()
        }
        .onChange(of: openCodeEnabled) { _ in saveSources() }
        .onChange(of: zcodeEnabled) { _ in saveSources() }
        .onChange(of: codexEnabled) { _ in saveSources() }
        .onChange(of: claudeEnabled) { _ in saveSources() }
        .onChange(of: kimiEnabled) { _ in saveSources() }
        .onChange(of: kimiQuotaEnabled) { _ in saveQuotaProviders() }
        .onChange(of: codexQuotaEnabled) { _ in saveQuotaProviders() }
        .onChange(of: claudeQuotaEnabled) { _ in saveQuotaProviders() }
        .onChange(of: glmQuotaEnabled) { _ in saveQuotaProviders() }
        .onChange(of: glmAPIKeyInput) { saveGLMAPIKey($0) }
        .onChange(of: glmRegion) { region in
            AppPreferences.shared.glmAPIRegion = region
            ProviderQuotaMonitor.shared.refresh()
        }
        .onChange(of: rateAutoEnabled) { enabled in
            if enabled { exchangeRateMonitor.refresh() }
        }
        .alert("重新计算 Token 用量？", isPresented: $showRecalculateConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重新计算") { recalculateTokenUsage() }
        } message: {
            Text("将清除统计解析缓存并重新扫描近一年记录。远程同步已启用时，重算结果会自动覆盖本设备原有快照。")
        }
    }

    private func loadSources() {
        let sources = AppPreferences.shared.enabledTokenSources
        openCodeEnabled = sources.contains(.opencode)
        zcodeEnabled = sources.contains(.zcode)
        codexEnabled = sources.contains(.codex)
        claudeEnabled = sources.contains(.claude)
        kimiEnabled = sources.contains(.kimi)
    }

    private func saveSources() {
        var sources: Set<TokenSource> = []
        if openCodeEnabled { sources.insert(.opencode) }
        if zcodeEnabled { sources.insert(.zcode) }
        if codexEnabled { sources.insert(.codex) }
        if claudeEnabled { sources.insert(.claude) }
        if kimiEnabled { sources.insert(.kimi) }
        AppPreferences.shared.enabledTokenSources = sources
    }

    private func loadQuotaSettings() {
        let providers = AppPreferences.shared.enabledQuotaProviders
        kimiQuotaEnabled = providers.contains(.kimi)
        codexQuotaEnabled = providers.contains(.codex)
        claudeQuotaEnabled = providers.contains(.claude)
        glmQuotaEnabled = providers.contains(.glm)
        glmRegion = AppPreferences.shared.glmAPIRegion
        hasGLMAPIKey = ProviderQuotaKeychain.hasGLMAPIKey

        // 凭据存在性检测放后台，避免阻塞设置页打开
        DispatchQueue.global(qos: .utility).async {
            let claude = ProviderQuotaFetcher.credentialStatus(for: .claude)
            let codex = ProviderQuotaFetcher.credentialStatus(for: .codex)
            let kimi = ProviderQuotaFetcher.credentialStatus(for: .kimi)
            DispatchQueue.main.async {
                self.claudeCredentialStatus = claude
                self.codexCredentialStatus = codex
                self.kimiCredentialStatus = kimi
            }
        }
    }

    private func saveQuotaProviders() {
        var providers: Set<QuotaProvider> = []
        if kimiQuotaEnabled { providers.insert(.kimi) }
        if codexQuotaEnabled { providers.insert(.codex) }
        if claudeQuotaEnabled { providers.insert(.claude) }
        if glmQuotaEnabled { providers.insert(.glm) }
        AppPreferences.shared.enabledQuotaProviders = providers
        ProviderQuotaMonitor.shared.refresh()
    }

    private func saveGLMAPIKey(_ value: String) {
        do {
            try ProviderQuotaKeychain.saveGLMAPIKey(value)
            hasGLMAPIKey = ProviderQuotaKeychain.hasGLMAPIKey
            scheduleQuotaRefresh()
        } catch {
            AppLog.general.error("保存 GLM API Key 失败：\(error.localizedDescription)")
        }
    }

    // 连续输入时合并刷新，避免每个字符都触发一次网络请求
    private func scheduleQuotaRefresh() {
        quotaRefreshTask?.cancel()
        quotaRefreshTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            ProviderQuotaMonitor.shared.refresh()
        }
    }

    private func recalculateTokenUsage() {
        recalculationFeedback = nil
        tokenUsageMonitor.recalculate { errors in
            if errors.isEmpty {
                recalculationHasError = false
                recalculationFeedback = AppPreferences.shared.tokenSyncEnabled
                    ? "本地重算完成，正在同步纠正远程快照。"
                    : "本地重算完成。"
            } else {
                recalculationHasError = true
                recalculationFeedback = "重算未应用，部分来源读取失败：\(errors.joined(separator: "；"))"
            }
        }
    }

    private var rateAutoDetail: String {
        if !rateAutoEnabled { return "关闭后可手动设置汇率" }
        if exchangeRateMonitor.isFetching { return "正在获取最新汇率…" }
        let updatedAt = AppPreferences.shared.tokenRateUpdatedAt
        if updatedAt > 0 {
            let date = Date(timeIntervalSince1970: updatedAt)
            return "上次更新 \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        if exchangeRateMonitor.lastError != nil { return "获取失败，暂用上次汇率" }
        return "启动后自动获取并定期刷新"
    }
}

private struct SourceToggle: View {
    let title: String
    let path: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: path) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct TokenSyncSettingsView: View {
    @ObservedObject private var syncService = TokenSyncService.shared
    @State private var enabled = false
    @State private var serverURL = ""
    @State private var deviceName = ""
    @State private var token = ""
    @State private var feedback: String?
    @State private var feedbackIsError = false

    var body: some View {
        SettingsPage(
            title: "多设备同步",
            subtitle: "汇总多台 Mac 的 Token 统计；网络不可用时继续保存在本地。"
        ) {
            syncStatusPanel

            SettingsGroup(title: "连接配置", subtitle: "Token 由服务管理员提供，并安全保存在本机 Keychain。") {
                SettingsRow(title: "启用同步", detail: "刷新本地统计后自动上传并拉取其他设备") {
                    Toggle("", isOn: $enabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsRow(title: "服务器地址") {
                    TextField("https://sync.example.com", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 310)
                }
                SettingsDivider()
                SettingsRow(title: "访问 Token") {
                    SecureField(syncService.hasStoredToken ? "已安全保存，留空保持不变" : "zfsm_…", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 310)
                }
                SettingsDivider()
                SettingsRow(title: "本设备名称", detail: "用于区分不同设备上传的数据") {
                    TextField("MacBook Pro", text: $deviceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                }
            }

            if let feedback {
                Label(feedback, systemImage: feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(feedbackIsError ? AppTheme.danger : AppTheme.success)
                    .padding(.horizontal, 2)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("保存") { saveConfiguration(verifyAfterSave: false) }
                    .keyboardShortcut("s", modifiers: [.command])
                Button("保存并测试") { saveConfiguration(verifyAfterSave: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
            }
        }
        .onAppear { loadConfiguration() }
    }

    private var syncStatusPanel: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(syncStatusColor.opacity(0.12))
                TokenSyncStatusSymbol(status: syncService.status)
                    .scaleEffect(1.2)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(syncService.status.message)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 8) {
                    if syncService.status.pendingDays > 0 {
                        Text("待同步 \(syncService.status.pendingDays) 天")
                    }
                    if let date = syncService.status.lastSuccessAt {
                        Text("上次成功 \(date.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text(enabled ? "尚未完成首次同步" : "本地统计不受影响")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            AppStatusBadge(title: enabled ? "已启用" : "未启用", systemName: enabled ? "icloud.fill" : "icloud.slash", color: syncStatusColor)
        }
        .appPanel(padding: 15)
    }

    private var syncStatusColor: Color {
        switch syncService.status.phase {
        case .disabled: return .secondary
        case .syncing, .pending: return AppTheme.accent
        case .synced: return AppTheme.success
        case .failed: return AppTheme.danger
        }
    }

    private func loadConfiguration() {
        let prefs = AppPreferences.shared
        enabled = prefs.tokenSyncEnabled
        serverURL = prefs.tokenSyncServerURL
        deviceName = prefs.tokenSyncDeviceName
    }

    private func saveConfiguration(verifyAfterSave: Bool) {
        do {
            try syncService.saveConfiguration(
                enabled: enabled,
                serverURL: serverURL,
                deviceName: deviceName,
                newToken: token.isEmpty ? nil : token
            )
            token = ""
            feedback = verifyAfterSave ? "配置已保存，正在验证连接…" : "配置已保存"
            feedbackIsError = false
            guard verifyAfterSave, enabled else { return }
            syncService.verifyConnection { result in
                switch result {
                case .success(let user):
                    feedback = "认证成功：\(user)"
                    feedbackIsError = false
                case .failure(let error):
                    feedback = error.localizedDescription
                    feedbackIsError = true
                }
            }
        } catch {
            feedback = error.localizedDescription
            feedbackIsError = true
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        SettingsPage(
            title: "关于",
            subtitle: "ZFStatMenus 在菜单栏集中展示系统状态与 AI 编程 Token 消耗。"
        ) {
            HStack(alignment: .top, spacing: 20) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .accessibilityLabel("ZFStatMenus 应用图标")

                VStack(alignment: .leading, spacing: 7) {
                    Text("ZFStatMenus")
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.4)
                    Text("版本 0.1.0（1）")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("原生 macOS 菜单栏监控工具")
                        .font(.system(size: 13, weight: .medium))
                    Text("系统指标始终在本机处理。只有主动启用自托管同步后，应用才会上传按日期和模型汇总的 Token 数量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 370, alignment: .leading)
                }
                Spacer()
            }
            .appPanel(padding: 18)

            SettingsGroup(title: "数据边界") {
                SettingsRow(title: "系统监控", detail: "CPU、内存、网络数据仅保留在当前进程") {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.success)
                }
                SettingsDivider()
                SettingsRow(title: "Token 统计", detail: "不读取或上传 Prompt、会话正文和项目内容") {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.success)
                }
                SettingsDivider()
                SettingsRow(title: "同步服务", detail: "可选、自托管，并使用独立访问 Token") {
                    Image(systemName: "lock.fill").foregroundStyle(AppTheme.accent)
                }
            }

            Text("© 2026 ZFStatMenus")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct TokenSyncStatusSymbol: View {
    let status: TokenSyncStatus

    var body: some View {
        Group {
            if status.phase == .syncing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(color)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel(status.message)
    }

    private var iconName: String {
        switch status.phase {
        case .disabled: return "icloud.slash"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.icloud.fill"
        case .pending: return "icloud.and.arrow.up"
        case .failed: return "exclamationmark.icloud.fill"
        }
    }

    private var color: Color {
        switch status.phase {
        case .disabled: return .secondary
        case .syncing, .pending: return AppTheme.accent
        case .synced: return AppTheme.success
        case .failed: return AppTheme.danger
        }
    }
}
