import SwiftUI
import VPSMonitorCore

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    @State private var editingConfiguration: MonitorConfiguration?
    @State private var newName = ""
    @State private var newHost = ""
    @State private var newUser = "root"
    @State private var newRefreshInterval: TimeInterval = 30
    @State private var newAuthMethod: AuthMethod = .sshKey
    @State private var newPassword = ""

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
                            HStack(spacing: 4) {
                                Text("\(configuration.user)@\(configuration.host)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                authBadge(configuration.authMethod)
                            }
                        }
                        Spacer()
                        Button { editingConfiguration = configuration } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Редактировать")
                        Button { store.removeServer(id: configuration.id) } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Удалить")
                    }
                    .padding(.vertical, 5)
                }
                .onDelete(perform: store.removeServers)
            }
            .frame(minHeight: 140)

            Divider()

            Text("Добавить VPS")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                LabeledTextField("Название",        text: $newName,   placeholder: "Мой сервер")
                LabeledTextField("Адрес VPS",       text: $newHost,   placeholder: "192.168.1.1")
                LabeledTextField("Пользователь SSH", text: $newUser,   placeholder: "root")
                RefreshIntervalPicker(selection: $newRefreshInterval)

                // Auth method
                HStack {
                    Text("Подключение")
                        .frame(width: 140, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $newAuthMethod) {
                        Text("SSH-ключ (рекомендуется)").tag(AuthMethod.sshKey)
                        Text("Логин и пароль").tag(AuthMethod.password)
                    }
                    .labelsHidden()
                }

                if newAuthMethod == .password {
                    HStack {
                        Text("Пароль")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        SecureField("Введите пароль", text: $newPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Пароль хранится в Связке ключей macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 148)
                }

                Button("Добавить сервер") { addServer() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAddServer)
            }

            Spacer()

            Text("SSH-ключи берутся из ~/.ssh. Приложение только читает данные серверов.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520, height: 660)
        .sheet(item: $editingConfiguration) { configuration in
            EditServerSheet(configuration: configuration,
                            existingPassword: KeychainService.loadPassword(for: configuration.id)) { updated, password in
                store.updateConfiguration(updated)
                // Save or remove password in Keychain
                switch updated.authMethod {
                case .password:
                    if let pw = password, !pw.isEmpty {
                        KeychainService.savePassword(pw, for: updated.id)
                    }
                case .sshKey:
                    KeychainService.deletePassword(for: updated.id)
                }
                editingConfiguration = nil
            } onCancel: {
                editingConfiguration = nil
            }
        }
    }

    // MARK: - Helpers

    private var canAddServer: Bool {
        !newName.trimmed.isEmpty &&
        !newHost.trimmed.isEmpty &&
        !newUser.trimmed.isEmpty &&
        (newAuthMethod == .sshKey || !newPassword.isEmpty)
    }

    private func addServer() {
        let config = MonitorConfiguration(
            name: newName.trimmed,
            host: newHost.trimmed,
            user: newUser.trimmed,
            refreshInterval: newRefreshInterval,
            authMethod: newAuthMethod
        )
        store.addServer(config)
        if newAuthMethod == .password && !newPassword.isEmpty {
            KeychainService.savePassword(newPassword, for: config.id)
        }
        newName = ""; newHost = ""; newUser = "root"
        newRefreshInterval = 30; newAuthMethod = .sshKey; newPassword = ""
    }

    @ViewBuilder
    private func authBadge(_ method: AuthMethod) -> some View {
        switch method {
        case .sshKey:
            Text("ключ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.secondary.opacity(0.15), in: Capsule())
        case .password:
            Text("пароль")
                .font(.caption2)
                .foregroundStyle(.blue)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.blue.opacity(0.1), in: Capsule())
        }
    }
}

// MARK: - Edit sheet

private struct EditServerSheet: View {
    @State private var name: String
    @State private var host: String
    @State private var user: String
    @State private var refreshInterval: TimeInterval
    @State private var authMethod: AuthMethod
    @State private var password = ""  // empty = keep existing

    private let configuration: MonitorConfiguration
    private let existingPassword: String?
    private let onSave: (MonitorConfiguration, String?) -> Void
    private let onCancel: () -> Void

    init(
        configuration: MonitorConfiguration,
        existingPassword: String?,
        onSave: @escaping (MonitorConfiguration, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.existingPassword = existingPassword
        self.onSave = onSave
        self.onCancel = onCancel
        _name            = State(initialValue: configuration.name)
        _host            = State(initialValue: configuration.host)
        _user            = State(initialValue: configuration.user)
        _refreshInterval = State(initialValue: configuration.refreshInterval)
        _authMethod      = State(initialValue: configuration.authMethod)
    }

    private var canSave: Bool {
        !name.trimmed.isEmpty && !host.trimmed.isEmpty && !user.trimmed.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Редактировать сервер")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                LabeledTextField("Название",         text: $name,   placeholder: "Мой сервер")
                LabeledTextField("Адрес VPS",        text: $host,   placeholder: "192.168.1.1")
                LabeledTextField("Пользователь SSH", text: $user,   placeholder: "root")
                RefreshIntervalPicker(selection: $refreshInterval)

                HStack {
                    Text("Подключение")
                        .frame(width: 140, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $authMethod) {
                        Text("SSH-ключ (рекомендуется)").tag(AuthMethod.sshKey)
                        Text("Логин и пароль").tag(AuthMethod.password)
                    }
                    .labelsHidden()
                }

                if authMethod == .password {
                    HStack {
                        Text("Новый пароль")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        SecureField(
                            existingPassword != nil ? "Оставьте пустым, чтобы не менять" : "Введите пароль",
                            text: $password
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                    Text("Пароль хранится в Связке ключей macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 148)
                }
            }

            HStack {
                Button("Отменить", role: .cancel) { onCancel() }
                Spacer()
                Button("Сохранить") {
                    let updated = MonitorConfiguration(
                        id: configuration.id,
                        name: name.trimmed,
                        host: host.trimmed,
                        user: user.trimmed,
                        refreshInterval: refreshInterval,
                        authMethod: authMethod
                    )
                    onSave(updated, password.isEmpty ? nil : password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - Shared sub-views

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    init(_ label: String, text: Binding<String>, placeholder: String = "") {
        self.label = label; self._text = text; self.placeholder = placeholder
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

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
