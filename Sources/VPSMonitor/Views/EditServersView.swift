import SwiftUI
import VPSMonitorCore

struct EditServersView: View {
    @ObservedObject var store: MonitorStore
    @State private var editingConfiguration: MonitorConfiguration?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Редактировать VPS", "Edit VPS", es: "Editar VPS", zh: "编辑 VPS"))
                .font(.title2.bold())

            if store.configurations.isEmpty {
                ContentUnavailableView(
                    L10n.text("Нет серверов", "No servers", es: "Sin servidores", zh: "没有服务器"),
                    systemImage: "server.rack"
                )
                .frame(width: 520, height: 260)
            } else {
                List {
                    ForEach(store.configurations) { configuration in
                        HStack(spacing: 12) {
                            Text(ServerPresentation.countryMarker(for: configuration))
                                .font(.title2)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(configuration.name)
                                    .fontWeight(.semibold)
                                Text("\(configuration.user)@\(configuration.host)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                editingConfiguration = configuration
                            } label: {
                                Label(L10n.text("Редактировать", "Edit", es: "Editar", zh: "编辑"), systemImage: "pencil")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 5)
                    }
                }
                .frame(width: 560, height: 320)
            }
        }
        .padding(24)
        .sheet(item: $editingConfiguration) { configuration in
            EditServerSheet(configuration: configuration,
                            existingPassword: KeychainService.loadPassword(for: configuration.id)) { updated, password in
                do {
                    switch updated.authMethod {
                    case .password:
                        if let pw = password, !pw.isEmpty {
                            try KeychainService.savePassword(pw, for: updated.id)
                        }
                    case .sshKey:
                        try KeychainService.deletePassword(for: updated.id)
                    }
                    store.updateConfiguration(updated)
                    editingConfiguration = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            } onCancel: {
                editingConfiguration = nil
            }
        }
        .alert(
            L10n.text("Не удалось сохранить сервер", "Could not save server", es: "No se pudo guardar el servidor", zh: "无法保存服务器"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
