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
                Text(L10n.text("Проекты: \(serverName)", "Projects: \(serverName)"))
                    .font(.title2.bold())
                Text(L10n.text(
                    "Включайте и отключайте то, что хотите видеть на дашборде.",
                    "Choose which items you want to see on the dashboard."
                ))
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
                    L10n.text("Проекты не обнаружены", "No projects detected"),
                    systemImage: "folder",
                    description: Text(L10n.text(
                        "Данные появятся после первого успешного опроса сервера.",
                        "Data will appear after the first successful server check."
                    ))
                )
                .frame(minHeight: 200)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // New projects first (if any)
                        let newOnes   = projects.filter { store.isNew($0.id, serverID: serverID) }
                        let restOnes  = projects.filter { !store.isNew($0.id, serverID: serverID) }

                        if !newOnes.isEmpty {
                            sectionHeader(L10n.text(
                                "Новые — появились с последнего запуска",
                                "New — appeared since the last launch"
                            ))
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

                        sectionHeader(L10n.text("Все проекты", "All projects"))
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
                    Button(L10n.text(
                        "Сбросить \(newCount) значка «Новый»",
                        "Clear \(newCount) “New” badges"
                    )) {
                        store.clearNewProjects(serverID: serverID)
                    }
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                }
                Spacer()
                let hidden = store.hiddenCount(for: serverID)
                if hidden > 0 {
                    Text(L10n.text("Скрыто: \(hidden)", "Hidden: \(hidden)"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button(L10n.text("Готово", "Done")) { dismiss() }
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
                        Text(L10n.text("НОВЫЙ", "NEW"))
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
            .help(isHidden
                ? L10n.text("Показать на дашборде", "Show on dashboard")
                : L10n.text("Скрыть с дашборда", "Hide from dashboard"))
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
