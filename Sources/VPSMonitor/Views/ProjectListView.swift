import AppKit
import SwiftUI
import VPSMonitorCore

struct ProjectListView: View {
    let serverID: UUID
    @ObservedObject var store: MonitorStore

    @State private var showingFilter = false

    private var visible: [DetectedProject] { store.visibleProjects(for: serverID) }
    private var hiddenCount: Int { store.hiddenCount(for: serverID) }
    private var hasNew: Bool { !(store.newProjectIDs[serverID] ?? []).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack(alignment: .center) {
                Text(L10n.text("Найденные проекты", "Detected projects"))
                    .font(.title2.bold())
                if hasNew {
                    Text(L10n.text("НОВЫЕ", "NEW")).font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.orange, in: Capsule())
                }
                Spacer()
                if hiddenCount > 0 {
                    Text(L10n.text("Скрыто: \(hiddenCount)", "Hidden: \(hiddenCount)", es: "Oculto: \(hiddenCount)", zh: "已隐藏：\(hiddenCount)"))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    showingFilter = true
                } label: {
                    Label(L10n.text("Настроить", "Configure"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
            }

            // List
            if visible.isEmpty && store.allProjects(for: serverID).isEmpty {
                Text(L10n.text("Прикладные проекты не найдены.", "No application projects found."))
                    .foregroundStyle(.secondary)
            } else if visible.isEmpty {
                Text(L10n.text("Все проекты скрыты. Нажмите «Настроить».", "All projects are hidden. Click “Configure”."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visible) { project in
                    ProjectRow(project: project,
                               isNew: store.isNew(project.id, serverID: serverID))
                }
            }
        }
        .sheet(isPresented: $showingFilter) {
            ProjectFilterView(
                serverID: serverID,
                serverName: store.configurations.first { $0.id == serverID }?.name ?? L10n.text("Сервер", "Server", es: "Servidor", zh: "服务器"),
                store: store
            )
        }
    }
}

// MARK: - Project row

private struct ProjectRow: View {
    let project: DetectedProject
    let isNew: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ── Title row ──────────────────────────────────────────────
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: stateIcon)
                    .foregroundStyle(stateColor)
                    .font(.title3)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(project.name).font(.headline)
                        if isNew {
                            Text(L10n.text("НОВЫЙ", "NEW")).font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.orange, in: Capsule())
                        }
                    }
                    Text(stateText).font(.callout).foregroundStyle(stateColor)
                    if let path = project.path {
                        Text(path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Project-level totals (only when there's meaningful data)
                if project.totalCPUPercent > 0 || project.totalMemoryBytes > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        if project.totalCPUPercent > 0 {
                            ResourcePill(
                                label: "CPU",
                                value: String(format: "%.1f%%", project.totalCPUPercent),
                                color: project.totalCPUPercent > 50 ? .orange : .green
                            )
                        }
                        if project.totalMemoryBytes > 0 {
                            ResourcePill(
                                label: "RAM",
                                value: MonitorFormatters.bytes(project.totalMemoryBytes),
                                color: .blue
                            )
                        }
                    }
                }
            }

            // ── Per-service breakdown ──────────────────────────────────
            if project.services.count > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(project.services, id: \.name) { service in
                        ServiceStatRow(service: service)
                    }
                }
                .padding(.leading, 32)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var stateText: String {
        switch project.state {
        case .running:    L10n.text("Работает", "Running", es: "En ejecución", zh: "运行中")
        case .stopped:    L10n.text("Требует внимания: служба не работает", "Needs attention: service is not running", es: "Requiere atención: el servicio no se está ejecutando", zh: "需要关注：服务未运行")
        case .folderOnly: L10n.text(
            "Код найден, отдельная служба или процесс не привязаны",
            "Code found, no dedicated service or process is linked",
            es: "Código encontrado, sin servicio o proceso dedicado vinculado",
            zh: "发现代码，但未关联专用服务或进程"
        )
        }
    }
    private var stateIcon: String {
        switch project.state {
        case .running:    "checkmark.circle.fill"
        case .stopped:    "exclamationmark.triangle.fill"
        case .folderOnly: "folder.fill"
        }
    }
    private var stateColor: Color {
        switch project.state {
        case .running:    .green
        case .stopped:    .orange
        case .folderOnly: .secondary
        }
    }
}

// MARK: - Service stat row

private struct ServiceStatRow: View {
    let service: RemoteService

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(service.isRunning ? Color.green : .orange)
                .frame(width: 6, height: 6)

            Text(displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if service.cpuPercent > 0 {
                Text(String(format: "CPU %.1f%%", service.cpuPercent))
                    .font(.caption2)
                    .foregroundStyle(service.cpuPercent > 50 ? .orange : .secondary)
                    .monospacedDigit()
            }
            if service.memoryBytes > 0 {
                Text("RAM \(MonitorFormatters.bytes(service.memoryBytes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !service.isRunning {
                Text(L10n.text("не запущена", "not running", es: "no se está ejecutando", zh: "未运行"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var displayName: String {
        if service.name.hasPrefix("process:") {
            let parts = service.name.split(separator: ":")
            if parts.count >= 2 {
                return L10n.text("процесс \(parts[1])", "process \(parts[1])", es: "proceso \(parts[1])", zh: "进程 \(parts[1])")
            }
        }
        return service.name.replacingOccurrences(of: ".service", with: "")
    }
}

// MARK: - Resource pill

private struct ResourcePill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(color.opacity(0.8))
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }
}
