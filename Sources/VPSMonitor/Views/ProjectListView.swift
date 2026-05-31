import SwiftUI
import VPSMonitorCore

struct ProjectListView: View {
    let serverID: UUID
    @ObservedObject var store: MonitorStore

    @State private var showingFilter = false

    private var visible: [DetectedProject] { store.visibleProjects(for: serverID) }
    private var hiddenCount: Int { store.hiddenCount(for: serverID) }
    private var hasNewProjects: Bool { !(store.newProjectIDs[serverID] ?? []).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Header ────────────────────────────────────────────────────
            HStack(alignment: .center) {
                Text("Найденные проекты")
                    .font(.title2.bold())

                if hasNewProjects {
                    Text("НОВЫЕ")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.orange, in: Capsule())
                }

                Spacer()

                // Hidden counter chip
                if hiddenCount > 0 {
                    Text("Скрыто: \(hiddenCount)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showingFilter = true
                } label: {
                    Label("Настроить", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
            }

            // ── Project rows ──────────────────────────────────────────────
            if visible.isEmpty && store.allProjects(for: serverID).isEmpty {
                Text("Прикладные проекты не найдены.")
                    .foregroundStyle(.secondary)
            } else if visible.isEmpty {
                Text("Все проекты скрыты. Нажмите «Настроить» чтобы изменить.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visible) { project in
                    ProjectRow(
                        project: project,
                        isNew: store.isNew(project.id, serverID: serverID)
                    )
                }
            }
        }
        .sheet(isPresented: $showingFilter) {
            ProjectFilterView(
                serverID: serverID,
                serverName: store.configurations.first(where: { $0.id == serverID })?.name ?? "Сервер",
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.headline)
                    if isNew {
                        Text("НОВЫЙ")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange, in: Capsule())
                    }
                }

                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(color)

                if let path = project.path {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                ForEach(project.services, id: \.name) { service in
                    Text("\(service.name): \(service.isRunning ? "запущена" : "не запущена")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusText: String {
        switch project.state {
        case .running:    "Работает"
        case .stopped:    "Требует внимания: служба не работает"
        case .folderOnly: "Найдена папка, связанная служба не обнаружена"
        }
    }

    private var icon: String {
        switch project.state {
        case .running:    "checkmark.circle.fill"
        case .stopped:    "exclamationmark.triangle.fill"
        case .folderOnly: "folder.fill"
        }
    }

    private var color: Color {
        switch project.state {
        case .running:    .green
        case .stopped:    .orange
        case .folderOnly: .secondary
        }
    }
}
