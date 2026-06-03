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
            Text(L10n.text("Серверы", "Servers"))
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
                        .help(L10n.text("Редактировать", "Edit"))
                        Button { store.removeServer(id: configuration.id) } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("Удалить", "Delete"))
                    }
                    .padding(.vertical, 5)
                }
                .onDelete(perform: store.removeServers)
            }
            .frame(minHeight: 140)

            Divider()

            Text(L10n.text("Добавить VPS", "Add VPS"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                LabeledTextField(L10n.text("Название", "Name"), text: $newName, placeholder: L10n.text("Мой сервер", "My server"))
                LabeledTextField(L10n.text("Адрес VPS", "VPS address"), text: $newHost, placeholder: "192.168.1.1")
                LabeledTextField(L10n.text("Пользователь SSH", "SSH user"), text: $newUser, placeholder: "root")
                RefreshIntervalPicker(selection: $newRefreshInterval)

                // Auth method
                HStack {
                    Text(L10n.text("Подключение", "Connection"))
                        .frame(width: 140, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $newAuthMethod) {
                        Text(L10n.text("SSH-ключ (рекомендуется)", "SSH key (recommended)")).tag(AuthMethod.sshKey)
                        Text(L10n.text("Логин и пароль", "Username and password")).tag(AuthMethod.password)
                    }
                    .labelsHidden()
                }

                if newAuthMethod == .password {
                    HStack {
                        Text(L10n.text("Пароль", "Password"))
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        SecureField(L10n.text("Введите пароль", "Enter password"), text: $newPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text(L10n.text("Пароль хранится в Связке ключей macOS.", "The password is stored in macOS Keychain."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 148)
                }

                Button(L10n.text("Добавить сервер", "Add server")) { addServer() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAddServer)
            }

            Spacer()

            Text(L10n.text(
                "SSH-ключи берутся из ~/.ssh. Приложение только читает данные серверов.",
                "SSH keys are loaded from ~/.ssh. The app only reads server data."
            ))
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
            Text(L10n.text("ключ", "key"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.secondary.opacity(0.15), in: Capsule())
        case .password:
            Text(L10n.text("пароль", "password"))
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
            Text(L10n.text("Редактировать сервер", "Edit server"))
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                LabeledTextField(L10n.text("Название", "Name"), text: $name, placeholder: L10n.text("Мой сервер", "My server"))
                LabeledTextField(L10n.text("Адрес VPS", "VPS address"), text: $host, placeholder: "192.168.1.1")
                LabeledTextField(L10n.text("Пользователь SSH", "SSH user"), text: $user, placeholder: "root")
                RefreshIntervalPicker(selection: $refreshInterval)

                HStack {
                    Text(L10n.text("Подключение", "Connection"))
                        .frame(width: 140, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $authMethod) {
                        Text(L10n.text("SSH-ключ (рекомендуется)", "SSH key (recommended)")).tag(AuthMethod.sshKey)
                        Text(L10n.text("Логин и пароль", "Username and password")).tag(AuthMethod.password)
                    }
                    .labelsHidden()
                }

                if authMethod == .password {
                    HStack {
                        Text(L10n.text("Новый пароль", "New password"))
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        SecureField(
                            existingPassword != nil
                                ? L10n.text("Оставьте пустым, чтобы не менять", "Leave blank to keep unchanged")
                                : L10n.text("Введите пароль", "Enter password"),
                            text: $password
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                    Text(L10n.text("Пароль хранится в Связке ключей macOS.", "The password is stored in macOS Keychain."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 148)
                }
            }

            HStack {
                Button(L10n.text("Отменить", "Cancel"), role: .cancel) { onCancel() }
                Spacer()
                Button(L10n.text("Сохранить", "Save")) {
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
            Text(L10n.text("Проверять автоматически", "Check automatically"))
                .frame(width: 140, alignment: .trailing)
                .foregroundStyle(.secondary)
            Picker("", selection: $selection) {
                Text(L10n.text("каждые 15 секунд", "every 15 seconds")).tag(TimeInterval(15))
                Text(L10n.text("каждые 30 секунд", "every 30 seconds")).tag(TimeInterval(30))
                Text(L10n.text("раз в минуту", "once a minute")).tag(TimeInterval(60))
            }
            .labelsHidden()
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
