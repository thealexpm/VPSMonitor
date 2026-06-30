import AppKit
import SwiftUI
import VPSMonitorCore

struct AddServerView: View {
    @ObservedObject var store: MonitorStore
    var onAdded: (() -> Void)?

    @State private var newName = ""
    @State private var newHost = ""
    @State private var newUser = "root"
    @State private var newRefreshInterval: TimeInterval = 30
    @State private var newAuthMethod: AuthMethod = .sshKey
    @State private var newCountryCodeOverride: String?
    @State private var newPassword = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("Добавить VPS", "Add VPS"))
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                AddServerField(L10n.text("Название", "Name"), text: $newName, placeholder: L10n.text("Мой сервер", "My server"))
                AddServerField(L10n.text("Адрес VPS", "VPS address"), text: $newHost, placeholder: "192.168.1.1")
                AddServerField(L10n.text("Пользователь SSH", "SSH user"), text: $newUser, placeholder: "root")
                AddServerRefreshIntervalPicker(selection: $newRefreshInterval)
                CountryPicker(
                    label: L10n.text("Страна", "Country"),
                    selection: $newCountryCodeOverride,
                    automaticCode: ServerPresentation.inferredCountryCode(name: newName, host: newHost)
                )

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
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(L10n.text("Добавить сервер", "Add server")) {
                    addServer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAddServer)
                .keyboardShortcut(.return)

                Spacer()
            }

            Text(L10n.text(
                "SSH-ключи берутся из ~/.ssh. Приложение только читает данные серверов.",
                "SSH keys are loaded from ~/.ssh. The app only reads server data.",
                es: "Las claves SSH se cargan desde ~/.ssh. La app solo lee datos del servidor.",
                zh: "SSH 密钥从 ~/.ssh 加载。应用只读取服务器数据。"
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

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
            authMethod: newAuthMethod,
            countryCode: ServerPresentation.inferredCountryCode(name: newName.trimmed, host: newHost.trimmed),
            countryCodeOverride: newCountryCodeOverride
        )
        do {
            if newAuthMethod == .password {
                try KeychainService.savePassword(newPassword, for: config.id)
            }
            store.addServer(config)
            reset()
            onAdded?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        newName = ""
        newHost = ""
        newUser = "root"
        newRefreshInterval = 30
        newAuthMethod = .sshKey
        newCountryCodeOverride = nil
        newPassword = ""
        errorMessage = nil
    }
}

private struct AddServerField: View {
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

private struct AddServerRefreshIntervalPicker: View {
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
