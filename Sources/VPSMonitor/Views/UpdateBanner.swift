import AppKit
import SwiftUI
import VPSMonitorCore

struct UpdateBanner: View {
    let update: AvailableUpdate
    let onDismiss: () -> Void

    private let strings = UpdateStrings.current

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(strings.title(version: update.version))
                        .font(.headline)
                    if let size = update.assetSizeBytes {
                        Text("· \(MonitorFormatters.bytes(size))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(strings.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(spacing: 6) {
                Button(strings.openButton) {
                    NSWorkspace.shared.open(update.releaseURL)
                }
                .buttonStyle(.borderedProminent)

                Button(strings.dismissButton, action: onDismiss)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.blue.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct UpdateStrings {
    let body: String
    let openButton: String
    let dismissButton: String
    let titleFormat: String

    func title(version: String) -> String {
        String(format: titleFormat, version)
    }

    static var current: UpdateStrings {
        L10n.isRussian ? .russian : .english
    }

    static let russian = UpdateStrings(
        body: "Доступна новая версия VPSMonitor. Откройте страницу релиза, чтобы скачать обновление.",
        openButton: "Открыть релиз",
        dismissButton: "Позже",
        titleFormat: "Доступна версия %@"
    )

    static let english = UpdateStrings(
        body: "A new VPSMonitor version is available. Open the release page to download the update.",
        openButton: "Open release",
        dismissButton: "Later",
        titleFormat: "Version %@ available"
    )
}
