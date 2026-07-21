import SwiftUI

struct URLMonitorSettingsView: View {
    @ObservedObject var urlMonitor: URLMonitor
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("URLs surveillées")
                .font(.headline)
            Text("Une URL par ligne. Chaque URL est vérifiée toutes les 10 minutes ; une notification critique est envoyée en cas d'erreur serveur (5xx) ou de site injoignable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(height: 220)
                .border(Color.gray.opacity(0.3))

            if !urlMonitor.urls.isEmpty {
                statusList
            }

            HStack {
                Spacer()
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            text = urlMonitor.urls.joined(separator: "\n")
        }
    }

    private var statusList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            ForEach(urlMonitor.urls, id: \.self) { url in
                let status = urlMonitor.statuses[url]
                HStack(spacing: 8) {
                    Circle()
                        .fill(status?.isDown == true ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                    Text(url)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let detail = status?.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func save() {
        let lines = text.components(separatedBy: .newlines)
        urlMonitor.updateURLs(lines)
    }
}
