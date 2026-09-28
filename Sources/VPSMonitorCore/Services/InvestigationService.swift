import Foundation

public struct InvestigationMetric: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case cpu
        case memory
        case disk
        case response
    }

    public enum Severity: Int, Comparable, Sendable {
        case normal
        case elevated
        case high

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let kind: Kind
    public let title: String
    public let currentValueText: String
    public let baselineValueText: String
    public let deltaText: String
    public let summary: String
    public let severity: Severity

    public var id: Kind { kind }
}

public struct InvestigationReport: Sendable {
    public let headline: String
    public let summary: String
    public let metrics: [InvestigationMetric]
    public let stoppedProjects: [DetectedProject]
    public let newProjects: [DetectedProject]
    public let recoveredProjects: [DetectedProject]
    public let suggestedCommands: [String]
    public let needsManualCheck: Bool
    public let shareText: String

    /// Stable identities of the individual actionable problems in this report.
    /// Each stopped project and high-severity metric is acknowledged separately
    /// so an unstable metric cannot invalidate an already reviewed project.
    public var attentionKeys: Set<String> {
        var keys = Set(stoppedProjects.map { "project:\($0.id)" })
        keys.formUnion(metrics
            .filter { $0.severity == .high }
            .map { "metric:\($0.kind.rawValue)" })
        return keys
    }

    /// Backward-compatible aggregate representation of the current problems.
    public var attentionKey: String? {
        guard !attentionKeys.isEmpty else { return nil }
        return attentionKeys.sorted().joined(separator: "|")
    }
}

public enum InvestigationService {
    public static func makeReport(
        snapshot: ServerSnapshot,
        history: [MetricSample],
        lastHealthySnapshot: ServerSnapshot?,
        host: String,
        user: String
    ) -> InvestigationReport {
        let previousSamples = Array(history.dropLast().suffix(8))
        let metrics = [
            buildCPU(snapshot: snapshot, samples: previousSamples),
            buildMemory(snapshot: snapshot, samples: previousSamples),
            buildDisk(snapshot: snapshot, samples: previousSamples),
            buildResponse(snapshot: snapshot, samples: previousSamples)
        ].sorted { $0.severity > $1.severity }

        let stoppedProjects = snapshot.projects.filter { $0.state == .stopped }
        let newProjects = diffProjects(current: snapshot.projects, previous: lastHealthySnapshot?.projects).added
        let recoveredProjects = diffProjects(current: snapshot.projects, previous: lastHealthySnapshot?.projects).recovered

        let highMetrics = metrics.filter { $0.severity == .high }
        let elevatedMetrics = metrics.filter { $0.severity == .elevated }
        let needsManualCheck = !stoppedProjects.isEmpty || !highMetrics.isEmpty

        let headline: String
        if !stoppedProjects.isEmpty {
            headline = L10n.text(
                "Нужно проверить \(stoppedProjects.count) служб(ы)",
                "\(stoppedProjects.count) service(s) need attention",
                es: "\(stoppedProjects.count) servicio(s) requieren atención",
                zh: "\(stoppedProjects.count) 个服务需要关注"
            )
        } else if !highMetrics.isEmpty {
            headline = L10n.text(
                "Есть сильные отклонения",
                "There are major anomalies",
                es: "Hay anomalías importantes",
                zh: "存在明显异常"
            )
        } else if !elevatedMetrics.isEmpty {
            headline = L10n.text(
                "Есть параметры для наблюдения",
                "There are metrics to watch",
                es: "Hay métricas para observar",
                zh: "有需要观察的指标"
            )
        } else {
            headline = L10n.text(
                "Состояние выглядит стабильным",
                "The server looks stable",
                es: "El servidor parece estable",
                zh: "服务器状态看起来稳定"
            )
        }

        let summary = buildSummary(
            stoppedProjects: stoppedProjects,
            highMetrics: highMetrics,
            elevatedMetrics: elevatedMetrics,
            newProjects: newProjects,
            recoveredProjects: recoveredProjects
        )

        let suggestedCommands = buildSuggestedCommands(
            stoppedProjects: stoppedProjects,
            snapshot: snapshot,
            host: host,
            user: user
        )

        let shareText = buildShareText(
            snapshot: snapshot,
            headline: headline,
            summary: summary,
            metrics: metrics,
            stoppedProjects: stoppedProjects,
            suggestedCommands: suggestedCommands
        )

        return InvestigationReport(
            headline: headline,
            summary: summary,
            metrics: metrics,
            stoppedProjects: stoppedProjects,
            newProjects: newProjects,
            recoveredProjects: recoveredProjects,
            suggestedCommands: suggestedCommands,
            needsManualCheck: needsManualCheck,
            shareText: shareText
        )
    }

    private static func buildCPU(snapshot: ServerSnapshot, samples: [MetricSample]) -> InvestigationMetric {
        let current = Double(snapshot.cpuUsagePercent)
        let baseline = average(samples.map(\.cpuPercent), fallback: current)
        let delta = current - baseline
        return InvestigationMetric(
            kind: .cpu,
            title: "CPU",
            currentValueText: percentText(current),
            baselineValueText: percentText(baseline),
            deltaText: signedPercentDelta(delta),
            summary: metricSummary(
                current: current,
                baseline: baseline,
                currentThreshold: 85,
                deltaThreshold: 18,
                labelHigh: L10n.text("процессор заметно выше обычного", "CPU is significantly above baseline", es: "CPU está bastante por encima de lo habitual", zh: "CPU 明显高于基线"),
                labelElevated: L10n.text("процессор выше обычного уровня", "CPU is above its usual level", es: "CPU está por encima de lo habitual", zh: "CPU 高于通常水平"),
                labelNormal: L10n.text("процессор в обычном диапазоне", "CPU is within its usual range", es: "CPU está dentro del rango habitual", zh: "CPU 处于通常范围")
            ),
            severity: metricSeverity(current: current, baseline: baseline, currentThreshold: 85, deltaThreshold: 18)
        )
    }

    private static func buildMemory(snapshot: ServerSnapshot, samples: [MetricSample]) -> InvestigationMetric {
        let current = snapshot.memoryTotalBytes > 0
            ? Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes) * 100
            : 0
        let baseline = average(samples.map(\.memoryPercent), fallback: current)
        let delta = current - baseline
        return InvestigationMetric(
            kind: .memory,
            title: "RAM",
            currentValueText: percentText(current),
            baselineValueText: percentText(baseline),
            deltaText: signedPercentDelta(delta),
            summary: metricSummary(
                current: current,
                baseline: baseline,
                currentThreshold: 85,
                deltaThreshold: 12,
                labelHigh: L10n.text("память близка к насыщению", "memory is close to saturation", es: "la memoria está cerca del límite", zh: "内存接近饱和"),
                labelElevated: L10n.text("память заметно выше обычной", "memory is above its usual level", es: "la memoria está por encima de lo habitual", zh: "内存高于通常水平"),
                labelNormal: L10n.text("память держится в норме", "memory usage is stable", es: "el uso de memoria es estable", zh: "内存使用稳定")
            ),
            severity: metricSeverity(current: current, baseline: baseline, currentThreshold: 85, deltaThreshold: 12)
        )
    }

    private static func buildDisk(snapshot: ServerSnapshot, samples: [MetricSample]) -> InvestigationMetric {
        let current = snapshot.diskTotalBytes > 0
            ? (1 - Double(snapshot.diskFreeBytes) / Double(snapshot.diskTotalBytes)) * 100
            : 0
        let baseline = average(samples.map(\.diskUsedPercent), fallback: current)
        let delta = current - baseline
        return InvestigationMetric(
            kind: .disk,
            title: L10n.text("Диск", "Disk", es: "Disco", zh: "磁盘"),
            currentValueText: percentText(current),
            baselineValueText: percentText(baseline),
            deltaText: signedPercentDelta(delta),
            summary: metricSummary(
                current: current,
                baseline: baseline,
                currentThreshold: 90,
                deltaThreshold: 8,
                labelHigh: L10n.text("диск почти заполнен", "disk usage is approaching capacity", es: "el disco está cerca de llenarse", zh: "磁盘接近满载"),
                labelElevated: L10n.text("диск заполняется быстрее обычного", "disk usage is climbing faster than usual", es: "el disco crece más rápido de lo habitual", zh: "磁盘占用增长快于通常"),
                labelNormal: L10n.text("по диску без тревожного сдвига", "disk usage is steady", es: "el uso del disco es estable", zh: "磁盘使用稳定")
            ),
            severity: metricSeverity(current: current, baseline: baseline, currentThreshold: 90, deltaThreshold: 8)
        )
    }

    private static func buildResponse(snapshot: ServerSnapshot, samples: [MetricSample]) -> InvestigationMetric {
        let current = snapshot.responseTime * 1_000
        let baseline = average(samples.map(\.responseMilliseconds), fallback: current)
        let delta = current - baseline
        return InvestigationMetric(
            kind: .response,
            title: "Latency",
            currentValueText: latencyText(current),
            baselineValueText: latencyText(baseline),
            deltaText: signedLatencyDelta(delta),
            summary: responseSummary(current: current, baseline: baseline),
            severity: responseSeverity(current: current, baseline: baseline)
        )
    }

    private static func buildSummary(
        stoppedProjects: [DetectedProject],
        highMetrics: [InvestigationMetric],
        elevatedMetrics: [InvestigationMetric],
        newProjects: [DetectedProject],
        recoveredProjects: [DetectedProject]
    ) -> String {
        var parts: [String] = []
        if !stoppedProjects.isEmpty {
            parts.append(L10n.text(
                "Остановлены: \(stoppedProjects.prefix(3).map(\.name).joined(separator: ", "))",
                "Stopped: \(stoppedProjects.prefix(3).map(\.name).joined(separator: ", "))",
                es: "Detenidos: \(stoppedProjects.prefix(3).map(\.name).joined(separator: ", "))",
                zh: "已停止：\(stoppedProjects.prefix(3).map(\.name).joined(separator: ", "))"
            ))
        }
        if !highMetrics.isEmpty {
            parts.append(L10n.text(
                "Сильно изменились: \(highMetrics.map(\.title).joined(separator: ", "))",
                "Major changes: \(highMetrics.map(\.title).joined(separator: ", "))",
                es: "Cambios importantes: \(highMetrics.map(\.title).joined(separator: ", "))",
                zh: "明显变化：\(highMetrics.map(\.title).joined(separator: ", "))"
            ))
        } else if !elevatedMetrics.isEmpty {
            parts.append(L10n.text(
                "Стоит наблюдать: \(elevatedMetrics.map(\.title).joined(separator: ", "))",
                "Watch: \(elevatedMetrics.map(\.title).joined(separator: ", "))",
                es: "Observar: \(elevatedMetrics.map(\.title).joined(separator: ", "))",
                zh: "建议观察：\(elevatedMetrics.map(\.title).joined(separator: ", "))"
            ))
        }
        if !newProjects.isEmpty {
            parts.append(L10n.text(
                "После последнего стабильного состояния появились: \(newProjects.prefix(3).map(\.name).joined(separator: ", "))",
                "Appeared since the last stable state: \(newProjects.prefix(3).map(\.name).joined(separator: ", "))",
                es: "Aparecieron desde el último estado estable: \(newProjects.prefix(3).map(\.name).joined(separator: ", "))",
                zh: "自上次稳定状态后出现：\(newProjects.prefix(3).map(\.name).joined(separator: ", "))"
            ))
        }
        if !recoveredProjects.isEmpty {
            parts.append(L10n.text(
                "Восстановились: \(recoveredProjects.prefix(3).map(\.name).joined(separator: ", "))",
                "Recovered: \(recoveredProjects.prefix(3).map(\.name).joined(separator: ", "))",
                es: "Recuperados: \(recoveredProjects.prefix(3).map(\.name).joined(separator: ", "))",
                zh: "已恢复：\(recoveredProjects.prefix(3).map(\.name).joined(separator: ", "))"
            ))
        }
        if parts.isEmpty {
            return L10n.text(
                "Текущие метрики близки к обычным значениям за последние проверки.",
                "Current metrics are close to the usual values from recent checks.",
                es: "Las métricas actuales están cerca de los valores habituales de las últimas comprobaciones.",
                zh: "当前指标接近最近检查中的通常值。"
            )
        }
        return parts.joined(separator: " • ")
    }

    private static func buildSuggestedCommands(
        stoppedProjects: [DetectedProject],
        snapshot: ServerSnapshot,
        host: String,
        user: String
    ) -> [String] {
        var commands = ["ssh \(shellQuoted("\(user)@\(host)"))"]
        if let service = stoppedProjects.first?.services.first?.name {
            commands.append("systemctl status \(shellQuoted(service)) --no-pager")
            commands.append("journalctl -u \(shellQuoted(service)) -n 120 --no-pager")
        } else if let service = snapshot.projects.flatMap(\.services).first(where: isSystemdService)?.name {
            commands.append("systemctl status \(shellQuoted(service)) --no-pager")
            commands.append("journalctl -u \(shellQuoted(service)) -n 120 --no-pager")
        } else if let process = snapshot.projects.flatMap(\.services).first(where: isSyntheticProcess),
                  let pid = processID(from: process.name) {
            commands.append("ps -p \(pid) -o pid,ppid,%cpu,%mem,etime,cmd --no-headers")
            commands.append("readlink -f /proc/\(pid)/cwd")
        }
        if let path = stoppedProjects.first?.path ?? snapshot.projects.first(where: { $0.path != nil })?.path {
            commands.append("du -sh \(shellQuoted(path))")
        }
        return Array(commands.prefix(4))
    }

    private static func buildShareText(
        snapshot: ServerSnapshot,
        headline: String,
        summary: String,
        metrics: [InvestigationMetric],
        stoppedProjects: [DetectedProject],
        suggestedCommands: [String]
    ) -> String {
        let metricsText = metrics.prefix(4).map {
            L10n.text(
                "- \($0.title): сейчас \($0.currentValueText), обычно \($0.baselineValueText) (\($0.deltaText))",
                "- \($0.title): current \($0.currentValueText), usual \($0.baselineValueText) (\($0.deltaText))",
                es: "- \($0.title): actual \($0.currentValueText), habitual \($0.baselineValueText) (\($0.deltaText))",
                zh: "- \($0.title)：当前 \($0.currentValueText)，通常 \($0.baselineValueText)（\($0.deltaText)）"
            )
        }.joined(separator: "\n")
        let stoppedText = stoppedProjects.isEmpty
            ? L10n.text("Нет остановленных служб", "No stopped services", es: "No hay servicios detenidos", zh: "没有停止的服务")
            : stoppedProjects.prefix(5).map { "- \($0.name)" }.joined(separator: "\n")
        let commandsText = suggestedCommands.map { "- \($0)" }.joined(separator: "\n")

        return """
        \(L10n.text("Отчёт VPSMonitor", "VPSMonitor report", es: "Informe VPSMonitor", zh: "VPSMonitor 报告"))
        \(snapshot.hostName)
        \(headline)

        \(summary)

        \(L10n.text("Метрики: сейчас и обычно", "Metrics: current and usual", es: "Métricas: actual y habitual", zh: "指标：当前和通常"))
        \(metricsText)

        \(L10n.text("Проблемные проекты", "Problematic projects", es: "Proyectos problemáticos", zh: "问题项目"))
        \(stoppedText)

        \(L10n.text("Команды для ручной проверки", "Manual check commands", es: "Comandos de comprobación manual", zh: "手动检查命令"))
        \(commandsText)
        """
    }

    private static func diffProjects(current: [DetectedProject], previous: [DetectedProject]?) -> (added: [DetectedProject], recovered: [DetectedProject]) {
        guard let previous else { return ([], []) }
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let added = current.filter { previousByID[$0.id] == nil }
        let recovered = current.filter { project in
            guard let old = previousByID[project.id] else { return false }
            return old.state == .stopped && project.state == .running
        }
        return (added, recovered)
    }

    private static func average(_ values: [Double], fallback: Double) -> Double {
        guard !values.isEmpty else { return fallback }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func metricSeverity(
        current: Double,
        baseline: Double,
        currentThreshold: Double,
        deltaThreshold: Double
    ) -> InvestigationMetric.Severity {
        if current >= currentThreshold || current - baseline >= deltaThreshold {
            return .high
        }
        if current - baseline >= deltaThreshold * 0.55 {
            return .elevated
        }
        return .normal
    }

    private static func metricSummary(
        current: Double,
        baseline: Double,
        currentThreshold: Double,
        deltaThreshold: Double,
        labelHigh: String,
        labelElevated: String,
        labelNormal: String
    ) -> String {
        switch metricSeverity(current: current, baseline: baseline, currentThreshold: currentThreshold, deltaThreshold: deltaThreshold) {
        case .high: labelHigh
        case .elevated: labelElevated
        case .normal: labelNormal
        }
    }

    private static func responseSeverity(current: Double, baseline: Double) -> InvestigationMetric.Severity {
        let delta = current - baseline
        if delta >= 250 || (current >= 1_000 && baseline < 750) {
            return .high
        }
        if delta >= 140 || current >= 1_000 {
            return .elevated
        }
        return .normal
    }

    private static func responseSummary(current: Double, baseline: Double) -> String {
        switch responseSeverity(current: current, baseline: baseline) {
        case .high:
            return L10n.text("SSH-проверка стала заметно медленнее", "SSH checks became much slower", es: "la comprobación SSH se volvió mucho más lenta", zh: "SSH 检查明显变慢")
        case .elevated:
            if current >= 1_000 && current <= baseline {
                return L10n.text("ответ медленный, но хуже не стал", "response is slow, but not getting worse", es: "la respuesta es lenta, pero no empeoró", zh: "响应较慢，但没有变差")
            }
            return L10n.text("ответ медленнее обычного", "response is slower than usual", es: "la respuesta es más lenta de lo habitual", zh: "响应比通常更慢")
        case .normal:
            return L10n.text("ответ в обычном диапазоне", "response is within its usual range", es: "la respuesta está dentro del rango habitual", zh: "响应处于通常范围")
        }
    }

    private static func percentText(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    private static func signedPercentDelta(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f", value)) pp"
    }

    private static func latencyText(_ value: Double) -> String {
        "\(Int(value.rounded())) ms"
    }

    private static func signedLatencyDelta(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int(value.rounded())) ms"
    }

    private static func isSystemdService(_ service: RemoteService) -> Bool {
        service.name.hasSuffix(".service")
    }

    private static func isSyntheticProcess(_ service: RemoteService) -> Bool {
        service.name.hasPrefix("process:")
    }

    private static func processID(from serviceName: String) -> Int? {
        guard let pidText = serviceName.split(separator: ":").last else { return nil }
        return Int(pidText)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
