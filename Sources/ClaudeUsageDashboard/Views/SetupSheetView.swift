import SwiftUI

struct SetupSheetView: View {
    @ObservedObject var usageService: UsageService
    @Binding var isPresented: Bool
    @State private var text: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration du suivi de quota")
                .font(.headline)
            Text("Va sur claude.ai/settings/usage, ouvre les DevTools (Cmd+Option+I) > onglet Network, recharge la page, clique-droit sur la requête « usage » > Copy > Copy as cURL (bash), puis colle le contenu ci-dessous.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(height: 160)
                .border(Color.gray.opacity(0.3))
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Annuler") { isPresented = false }
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func save() {
        guard let parsed = CurlParser.parse(text) else {
            errorMessage = "Impossible de lire cette commande cURL. Vérifie qu'elle contient bien l'URL et le header cookie."
            return
        }
        usageService.saveConfig(usageURL: parsed.usageURL, cookie: parsed.cookie)
        isPresented = false
    }
}
