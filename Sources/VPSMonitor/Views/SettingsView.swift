import SwiftUI
import VPSMonitorCore

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    @State private var editingConfiguration: MonitorConfiguration?
    @State private var newName = ""
    @State private var newHost = ""
    @State private var newUser = "root"
    @State private var newRefreshInterval: TimeInterval = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Серверы")
                .font(.title2.bold())

            List {
                ForEach(store.configurations) { configuration in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(configuration.name)
                                .fontWeight(.medium)
                            Text("\(configuration.user)@\(configuration.host)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            editingConfiguration = configuration
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Редактировать")
                        Button {
                            store.removeServer(id: configuration.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Удалить")
                    }
                    .padding(.vertical, 5)
                }
                .onDelete(perform: store.removeServers)
            }
            .frame(minHeight: 160)

            Divider()

            Text("Добавить VPS")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                LabeledTextField("Название", text: $newName, placeholder: "Мой сервер")
                LabeledTextField("Адрес VPS", text: $newHost, placeholder: "192.168.1.1")
                LabeledTextField("Пользователь SSH", text: $newUser, placeholder: "root")
                RefreshIntervalPicker(selection: $newRefreshInterval)
                Button("Добавить сервер") { addServer() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        newName.trimmingCharacters(in: .whitespaces).isEmpty ||
                        newHost.trimmingCharacters(in: .whitespaces).isEmpty ||
                        newUser.trimmingCharacters(in: .whitespaces).isEmpty
                    )
            }

            Spacer()

            Text("Используются существующие SSH-ключи. Приложение только читает данные серверов.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520, height: 600)
        .sheet(item: $editingConfiguration) { configuration in
            EditServerSheet(configuration: configuration) { updated in
                store.updateConfiguration(updated)
                editingConfiguration = nil
            } onCancel: {
                editingConfiguration = nil
            }
        }
    }

    private func addServer() {
        store.addServer(MonitorConfiguration(
            name: newName.trimmingCharacters(in: .whitespaces),
            host: newHost.trimmingCharacters(in: .whitespaces),
            user: newUser.trimmingCharacters(in: .whitespaces),
            refreshInterval: newRefreshInterval
        ))
        newName = ""
        newHost = ""
        newUser = "root"
        newRefreshInterval = 30
    }
}

private struct EditServerSheet: View {
    @State private var name: String
    @State private var host: String
    @State private var user: String
    @State private var refreshInterval: TimeInterval

    private let configuration: MonitorConfiguration
    private let onSave: (MonitorConfiguration) -> Void
    private let onCancel: () -> Void

    init(
        configuration: MonitorConfiguration,
        onSave: @escaping (MonitorConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: configuration.name)
        _host = State(initialValue: configuration.host)
        _user = State(initialValue: configuration.user)
        _refreshInterval = State(initialValue: configuration.refreshInterval)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !user.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Редактировать сервер")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                LabeledTextField("Название", text: $name, placeholder: "Мой сервер")
                LabeledTextField("Адрес VPS", text: $host, placeholder: "192.168.1.1")
                LabeledTextField("Пользователь SSH", text: $user, placeholder: "root")
                RefreshIntervalPicker(selection: $refreshInterval)
            }

            HStack {
                Button("Отменить", role: .cancel) { onCancel() }
                Spacer()
                Button("Сохранить") {
                    onSave(MonitorConfiguration(
                        id: configuration.id,
                        name: name.trimmingCharacters(in: .whitespaces),
                        host: host.trimmingCharacters(in: .whitespaces),
                        user: user.trimmingCharacters(in: .whitespaces),
                        refreshInterval: refreshInterval
                    ))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    init(_ label: String, text: Binding<String>, placeholder: String = "") {
        self.label = label
        self._text = text
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 140, alignment: .trailing)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct RefreshIntervalPicker: View {
    @Binding var selection: TimeInterval

    var body: some View {
        HStack {
            Text("Проверять автоматически")
                .frame(width: 140, alignment: .trailing)
                .foregroundStyle(.secondary)
            Picker("", selection: $selection) {
                Text("каждые 15 секунд").tag(TimeInterval(15))
                Text("каждые 30 секунд").tag(TimeInterval(30))
                Text("раз в минуту").tag(TimeInterval(60))
            }
            .labelsHidden()
        }
    }
}
