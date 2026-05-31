import SwiftUI
import VPSMonitorCore

struct ProjectFilterView: View {
    let serverID: UUID
    let serverName: String
    @ObservedObject var store: MonitorStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("Проекты: \(serverName)")
                    .font(.title2.bold())
                Text("Включайте и отключайте то, что хотите видеть на дашборде.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            // ── Project list ──────────────────────────────────────────────
            let projects = store.allProjects(for: serverID)

            if projects.isEmpty {
                ContentUnavailableView(
                    "Проекты не обнаружены",
                    systemImage: "folder",
                    description: Text("Данные появятся после первого успешного опроса сервера.")
                )
                .frame(minHeight: 200)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // New projects first (if any)
                        let newOnes   = projects.filter { store.isNew($0.id, serverID: serverID) }
                        let restOnes  = projects.filter { !store.isNew($0.id, serverID: serverID) }

                        if !newOnes.isEmpty {
                            sectionHeader("Новые — появились с последнего запуска")
                            ForEach(newOnes) { project in
                                FilterRow(
                                    project: project,
                                    isHidden: store.isHidden(project.id, serverID: serverID),
                                    isNew: true
                                ) { hidden in
                                    store.setProjectHidden(hidden, projectID: project.id, serverID: serverID)
                                }
                                Divider().padding(.leading, 52)
                            }
                        }

                        sectionHeader("Все проекты")
                        ForEach(restOnes) { project in
                            FilterRow(
                                project: project,
                                isHidden: store.isHidden(project.id, serverID: serverID),
                                isNew: false
                            ) { hidden in
                                store.setProjectHidden(hidden, projectID: project.id, serverID: serverID)
                            }
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .frame(minHeight: 220)
            }

            Divider()

            // ── Footer ────────────────────────────────────────────────────
            HStack {
                let newCount = store.newProjectIDs[serverID]?.count ?? 0
                if newCount > 0 {
                    Button("Сбросить \(newCount) значка «Новый»") {
                        store.clearNewProjects(serverID: serverID)
                    }
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                }
                Spacer()
                let hidden = store.hiddenCount(for: serverID)
                if hidden > 0 {
                    Text("Скрыто: \(hidden)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Готово") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: 520)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Filter row

private struct FilterRow: View {
    let project: DetectedProject
    let isHidden: Bool
    let isNew: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: stateIcon)
                .foregroundStyle(stateColor)
                .frame(width: 20)

            // Name + badges
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .fontWeight(.medium)
                    if isNew {
                        Text("НОВЫЙ")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange, in: Capsule())
                    }
                }
                if let path = project.path {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Eye toggle
            Button {
                onToggle(!isHidden)
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .foregroundStyle(isHidden ? .secondary : .primary)
            }
            .buttonStyle(.borderless)
            .help(isHidden ? "Показать на дашборде" : "Скрыть с дашборда")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .opacity(isHidden ? 0.5 : 1.0)
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
