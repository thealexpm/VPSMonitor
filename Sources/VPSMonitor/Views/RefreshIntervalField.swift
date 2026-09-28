import SwiftUI
import VPSMonitorCore

struct RefreshIntervalField: View {
    @Binding var selection: TimeInterval

    private var seconds: Binding<Int> {
        Binding(
            get: { Int(selection.rounded()) },
            set: { selection = TimeInterval(min(max($0, 10), 86_400)) }
        )
    }

    var body: some View {
        HStack {
            Text(L10n.text("Проверять автоматически", "Check automatically"))
                .frame(width: 140, alignment: .trailing)
                .foregroundStyle(.secondary)

            TextField("60", value: seconds, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
            Text(L10n.text("секунд", "seconds"))
                .foregroundStyle(.secondary)

            Stepper("", value: seconds, in: 10...86_400, step: 10)
                .labelsHidden()

            Menu {
                preset(L10n.text("30 секунд", "30 seconds"), seconds: 30)
                preset(L10n.text("1 минута", "1 minute"), seconds: 60)
                preset(L10n.text("5 минут", "5 minutes"), seconds: 300)
                preset(L10n.text("15 минут", "15 minutes"), seconds: 900)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .help(L10n.text("Выбрать готовый интервал", "Choose a preset interval"))
        }
    }

    private func preset(_ title: String, seconds: Int) -> some View {
        Button(title) {
            selection = TimeInterval(seconds)
        }
    }
}
