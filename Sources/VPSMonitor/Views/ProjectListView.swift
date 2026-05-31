import SwiftUI
import VPSMonitorCore

struct ProjectListView: View {
    let projects: [DetectedProject]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Найденные проекты")
                .font(.title2.bold())

            if projects.isEmpty {
                Text("Прикладные проекты не найдены.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projects) { project in
                    ProjectRow(project: project)
                }
            }
        }
    }
}

private struct ProjectRow: View {
    let project: DetectedProject

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(project.name)
                    .font(.headline)
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
        case .running: "Работает"
        case .stopped: "Требует внимания: служба не работает"
        case .folderOnly: "Найдена папка, связанная служба не обнаружена"
        }
    }

    private var icon: String {
        switch project.state {
        case .running: "checkmark.circle.fill"
        case .stopped: "exclamationmark.triangle.fill"
        case .folderOnly: "folder.fill"
        }
    }

    private var color: Color {
        switch project.state {
        case .running: .green
        case .stopped: .orange
        case .folderOnly: .secondary
        }
    }
}
