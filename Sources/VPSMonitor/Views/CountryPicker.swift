import SwiftUI
import VPSMonitorCore

struct CountryPicker: View {
    let label: String
    @Binding var selection: String?
    var automaticCode: String?
    @State private var showingSelector = false

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 140, alignment: .trailing)
                .foregroundStyle(.secondary)
            Button {
                showingSelector = true
            } label: {
                HStack {
                    Text(selectedTitle)
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showingSelector) {
                CountrySelectionSheet(
                    selection: $selection,
                    automaticCode: automaticCode
                )
            }
        }
    }

    private var selectedTitle: String {
        if let selection = ServerPresentation.normalizedCountryCode(selection),
           let option = ServerPresentation.countryOptions.first(where: { $0.code == selection }) {
            return option.displayTitle
        }
        return autoTitle
    }

    private var autoTitle: String {
        let marker = automaticCode.flatMap(ServerPresentation.flagEmoji(for:)) ?? "🌐"
        return L10n.text("Авто \(marker)", "Auto \(marker)")
    }
}

private struct CountrySelectionSheet: View {
    @Binding var selection: String?
    var automaticCode: String?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var options: [ServerPresentation.CountryOption] {
        ServerPresentation.countryOptions(matching: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.text("Выбор страны", "Select country", es: "Seleccionar país", zh: "选择国家/地区"))
                    .font(.title3.bold())
                Spacer()
                Button(L10n.text("Готово", "Done", es: "Listo", zh: "完成")) {
                    dismiss()
                }
            }

            TextField(
                L10n.text("Поиск по русскому или английскому названию", "Search by Russian or English name", es: "Buscar por nombre ruso o inglés", zh: "按俄语或英语名称搜索"),
                text: $query
            )
            .textFieldStyle(.roundedBorder)

            List {
                Button {
                    selection = nil
                    dismiss()
                } label: {
                    HStack {
                        Text(autoTitle)
                        Spacer()
                        if selection == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                ForEach(options) { option in
                    Button {
                        selection = option.code
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.displayTitle)
                            Spacer()
                            Text(option.code)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if ServerPresentation.normalizedCountryCode(selection) == option.code {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 360)
        }
        .padding(20)
        .frame(width: 520, height: 520)
    }

    private var autoTitle: String {
        let marker = automaticCode.flatMap(ServerPresentation.flagEmoji(for:)) ?? "🌐"
        return L10n.text("Авто \(marker)", "Auto \(marker)", es: "Auto \(marker)", zh: "自动 \(marker)")
    }
}
