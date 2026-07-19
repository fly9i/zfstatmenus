import Foundation
import AppKit

struct TopProcess: Identifiable {
    let id = UUID()
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryBytes: UInt64
    let icon: NSImage?
}

struct NetworkProcess: Identifiable {
    let id = UUID()
    let pid: Int32
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
    let icon: NSImage?
}

struct NetworkSocketCounter: Equatable {
    let id: String
    let pid: Int32
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
}

final class ProcessMonitor {

    private(set) var cachedTopCPU: [TopProcess] = []
    private(set) var cachedTopMemory: [TopProcess] = []
    private(set) var cachedTopNetwork: [NetworkProcess] = []

    private var cpuMemTimer: DispatchSourceTimer?
    private var netTimer: DispatchSourceTimer?
    // top 与 nettop 都需要约一秒完成采样。分开队列，避免其中一个排行阻塞另一个。
    private let cpuMemQueue = DispatchQueue(label: "com.zfstat.procmon.cpu-memory", qos: .utility)
    private let networkQueue = DispatchQueue(label: "com.zfstat.procmon.network", qos: .utility)
    private var iconCache: [Int32: NSImage] = [:]
    private let iconCacheLock = NSLock()
    private var samplingInterval: TimeInterval = 1.0
    private var activeRanking: StatusItemType?
    private var previousNetworkSockets: [String: NetworkSocketCounter] = [:]
    private var previousNetworkSampleDate: Date?

    func start(interval: TimeInterval = 1.0) {
        // CPU 的 top 与网络累计值都需要相邻快照；低于一秒时保持每秒采样，避免无意义的重叠任务。
        samplingInterval = max(1.0, interval)
        restartActiveSampling()
    }

    func activate(_ type: StatusItemType) {
        guard type == .cpu || type == .memory || type == .network else { return }
        if type == .network, activeRanking != .network {
            previousNetworkSockets = [:]
            previousNetworkSampleDate = nil
        }
        activeRanking = type
        restartActiveSampling()
    }

    func deactivate(_ type: StatusItemType) {
        guard activeRanking == type else { return }
        activeRanking = nil
        cancelTimers()
    }

    func stop() {
        activeRanking = nil
        cancelTimers()
    }

    private func restartActiveSampling() {
        cancelTimers()

        switch activeRanking {
        case .cpu, .memory:
            startCPUMemorySampling()
        case .network:
            startNetworkSampling()
        case .token, nil:
            break
        }
    }

    private func startCPUMemorySampling() {
        let t1 = DispatchSource.makeTimerSource(queue: cpuMemQueue)
        t1.schedule(deadline: .now(), repeating: samplingInterval)
        t1.setEventHandler { [weak self] in self?.sampleCPUMem() }
        t1.resume()
        cpuMemTimer = t1
    }

    private func startNetworkSampling() {
        let t2 = DispatchSource.makeTimerSource(queue: networkQueue)
        t2.schedule(deadline: .now(), repeating: samplingInterval)
        t2.setEventHandler { [weak self] in self?.sampleNetwork() }
        t2.resume()
        netTimer = t2
    }

    private func cancelTimers() {
        cpuMemTimer?.cancel()
        cpuMemTimer = nil
        netTimer?.cancel()
        netTimer = nil
    }

    func topCPU() -> [TopProcess] { cachedTopCPU }
    func topMemory() -> [TopProcess] { cachedTopMemory }
    func topNetwork() -> [NetworkProcess] { cachedTopNetwork }

    // MARK: - CPU + Memory via top

    private func sampleCPUMem() {
        guard let output = runCommand("/usr/bin/top",
                                      args: ["-l", "2", "-n", "20", "-o", "cpu", "-stats", "pid,command,cpu,mem"]) else { return }

        // top -l 2 输出两轮，第二轮是 1 秒内的 delta
        // 找到第二轮的进程列表
        let lines = output.components(separatedBy: "\n")
        var pidHeaderCount = 0
        var processStart = -1

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("PID") {
                pidHeaderCount += 1
                if pidHeaderCount == 2 {
                    processStart = i + 1
                    break
                }
            }
        }

        guard processStart >= 0 else { return }

        struct ParsedProc {
            let pid: Int32
            let name: String
            let cpu: Double
            let memBytes: UInt64
        }

        var procs: [ParsedProc] = []

        for i in processStart..<lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }

            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 4,
                  let pid = Int32(cols[0]) else { continue }

            // 从右往左：最后是 MEM，倒数第二是 CPU，中间是 command
            let memStr = String(cols[cols.count - 1])
            let cpuStr = String(cols[cols.count - 2])
            let name = cols[1..<(cols.count - 2)].joined(separator: " ")

            let cpu = Double(cpuStr) ?? 0.0
            let memBytes = parseMemString(memStr)

            procs.append(ParsedProc(pid: pid, name: name, cpu: cpu, memBytes: memBytes))
        }

        guard !procs.isEmpty else { return }

        let cpuTop = procs
            .filter { $0.cpu > 0 }
            .sorted { $0.cpu > $1.cpu }
            .prefix(5)
            .map { TopProcess(pid: $0.pid, name: $0.name, cpuUsage: $0.cpu / 100.0, memoryBytes: $0.memBytes, icon: appIcon(for: $0.pid)) }

        let memTop = procs
            .sorted { $0.memBytes > $1.memBytes }
            .prefix(5)
            .map { TopProcess(pid: $0.pid, name: $0.name, cpuUsage: 0, memoryBytes: $0.memBytes, icon: appIcon(for: $0.pid)) }

        DispatchQueue.main.async { [weak self] in
            self?.cachedTopCPU = cpuTop
            self?.cachedTopMemory = memTop
        }
    }

    // top 输出内存格式: "1133M+", "4688K+", "2G-", "360M"
    private func parseMemString(_ s: String) -> UInt64 {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        let numStr = String(String.UnicodeScalarView(digits))
        guard let num = Double(numStr) else { return 0 }

        if trimmed.contains("G") {
            return UInt64(num * 1024 * 1024 * 1024)
        } else if trimmed.contains("M") {
            return UInt64(num * 1024 * 1024)
        } else if trimmed.contains("K") {
            return UInt64(num * 1024)
        }
        return UInt64(num)
    }

    // MARK: - Network via netstat

    private func sampleNetwork() {
        let protocols = ["tcp", "udp"]
        let counters = protocols.flatMap { proto -> [NetworkSocketCounter] in
            guard let output = runCommand("/usr/sbin/netstat", args: ["-anv", "-p", proto]) else { return [] }
            return parseNetstatNetworkSockets(output)
        }
        guard !counters.isEmpty else { return }

        let now = Date()
        let currentSockets = Dictionary(counters.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        guard let previousDate = previousNetworkSampleDate else {
            previousNetworkSockets = currentSockets
            previousNetworkSampleDate = now
            return
        }

        struct ProcessDelta {
            var name: String
            var bytesIn: UInt64 = 0
            var bytesOut: UInt64 = 0
        }

        var deltas: [Int32: ProcessDelta] = [:]
        for counter in counters {
            let previous = previousNetworkSockets[counter.id]
            let bytesIn = previous.map { counter.bytesIn >= $0.bytesIn ? counter.bytesIn - $0.bytesIn : counter.bytesIn } ?? counter.bytesIn
            let bytesOut = previous.map { counter.bytesOut >= $0.bytesOut ? counter.bytesOut - $0.bytesOut : counter.bytesOut } ?? counter.bytesOut
            guard bytesIn > 0 || bytesOut > 0 else { continue }

            var delta = deltas[counter.pid] ?? ProcessDelta(name: counter.name)
            delta.bytesIn += bytesIn
            delta.bytesOut += bytesOut
            deltas[counter.pid] = delta
        }

        previousNetworkSockets = currentSockets
        previousNetworkSampleDate = now

        let elapsed = max(0.1, now.timeIntervalSince(previousDate))
        let netTop = deltas.map { pid, delta in
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? delta.name
            return NetworkProcess(
                pid: pid,
                name: name,
                bytesIn: UInt64(Double(delta.bytesIn) / elapsed),
                bytesOut: UInt64(Double(delta.bytesOut) / elapsed),
                icon: appIcon(for: pid)
            )
        }
            .sorted { ($0.bytesIn + $0.bytesOut) > ($1.bytesIn + $1.bytesOut) }
            .prefix(5)
            .map { $0 }

        DispatchQueue.main.async { [weak self] in
            self?.cachedTopNetwork = netTop
        }
    }

    // MARK: - Helpers

    private func runCommand(_ path: String, args: [String]) -> String? {
        guard let result = try? ProcessOutputRunner.run(path: path, arguments: args),
              result.terminationStatus == 0 else { return nil }
        return String(data: result.standardOutput, encoding: .utf8)
    }

    private func appIcon(for pid: Int32) -> NSImage? {
        iconCacheLock.lock()
        let cached = iconCache[pid]
        iconCacheLock.unlock()
        if let cached { return cached }

        let app = NSRunningApplication(processIdentifier: pid)
        let icon = app?.icon
        if let icon = icon {
            iconCacheLock.lock()
            iconCache[pid] = icon
            iconCacheLock.unlock()
        }
        return icon
    }
}

func parseNetstatNetworkSockets(_ output: String) -> [NetworkSocketCounter] {
    output.components(separatedBy: .newlines).compactMap { line in
        guard line.hasPrefix("tcp") || line.hasPrefix("udp") else { return nil }
        let columns = line.split(whereSeparator: { $0.isWhitespace })
        // process:pid 后固定还有 state/options/gencnt/flags/flags1/usecnt/rtncnt/fltrs 八列。
        guard columns.count >= 18 else { return nil }
        let processPIDIndex = columns.count - 9

        // UDP 的累计字节从第 6 列开始；TCP 在它前面多一列连接状态。
        let candidateRXIndex = 5
        let rxIndex = UInt64(columns[candidateRXIndex]) == nil ? candidateRXIndex + 1 : candidateRXIndex
        let processNameStart = rxIndex + 4
        guard processNameStart <= processPIDIndex,
              let bytesIn = UInt64(columns[rxIndex]),
              let bytesOut = UInt64(columns[rxIndex + 1]) else { return nil }

        let processField = columns[processNameStart...processPIDIndex].joined(separator: " ")
        guard let colon = processField.lastIndex(of: ":"),
              let pid = Int32(processField[processField.index(after: colon)...]) else { return nil }

        let name = String(processField[..<colon])
        let proto = String(columns[0])
        let generation = String(columns[processPIDIndex + 3])
        guard !name.isEmpty, !generation.isEmpty else { return nil }

        return NetworkSocketCounter(
            id: "\(proto)|\(pid)|\(generation)",
            pid: pid,
            name: name,
            bytesIn: bytesIn,
            bytesOut: bytesOut
        )
    }
}

struct ProcessOutput {
    let standardOutput: Data
    let standardError: Data
    let terminationStatus: Int32
}

enum ProcessOutputRunner {
    static func run(path: String, arguments: [String]) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? errorOutput.fileHandleForReading.close()
            try? errorOutput.fileHandleForWriting.close()
        }

        try process.run()
        try? output.fileHandleForWriting.close()
        try? errorOutput.fileHandleForWriting.close()

        let standardOutput = output.fileHandleForReading.readDataToEndOfFile()
        let standardError = errorOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessOutput(
            standardOutput: standardOutput,
            standardError: standardError,
            terminationStatus: process.terminationStatus
        )
    }
}
