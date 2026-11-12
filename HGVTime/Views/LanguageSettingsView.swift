import SwiftUI

/// Settings → Language: choose the app's language (or follow the iPhone).
struct LanguageSettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var selected = AppLanguage.current
    @State private var showRestart = false

    var body: some View {
        Form {
            Section {
                ForEach(AppLanguage.all, id: \.code) { lang in
                    Button {
                        guard lang.code != selected else { return }
                        AppLanguage.set(lang.code)
                        selected = lang.code
                        showRestart = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                if lang.code.isEmpty { Text("iPhone language") } else { Text(verbatim: lang.native) }
                                if !lang.english.isEmpty { Text(verbatim: lang.english).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if lang.code == selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.bold) }
                        }
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("The app restarts in the new language. Rules, limits and your records don't change. Some help texts may still be in English.")
            }
            Section {
                Button("Open iPhone Settings for HGV Hours") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text("You can also change the app's language in iPhone Settings → Apps → HGV Hours → Language.")
            }
        }
        .navigationTitle("Language")
        .alert("Restart to change the language", isPresented: $showRestart) {
            Button("Close app now") { AppLanguage.closeApp() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Close HGV Hours and open it again to see it in the new language.")
        }
    }
}

enum AppLanguage {
    struct Option { var code: String; var native: String; var english: String }

    /// Languages the app is translated into ("" = follow the iPhone).
    static let all: [Option] = [
        .init(code: "", native: "iPhone language", english: ""),
        .init(code: "en", native: "English", english: ""),
        .init(code: "pl", native: "Polski", english: "Polish"),
        .init(code: "ro", native: "Română", english: "Romanian"),
        .init(code: "ru", native: "Русский", english: "Russian"),
        .init(code: "uk", native: "Українська", english: "Ukrainian"),
        .init(code: "bg", native: "Български", english: "Bulgarian"),
        .init(code: "lt", native: "Lietuvių", english: "Lithuanian"),
        .init(code: "pt", native: "Português", english: "Portuguese"),
    ].filter { $0.code.isEmpty || $0.code == "en" || Bundle.main.localizations.contains($0.code) }

    private static let key = "AppleLanguages"
    private static let chosenKey = "hgv.appLanguage"

    static var current: String { UserDefaults.standard.string(forKey: chosenKey) ?? "" }

    static func set(_ code: String) {
        let d = UserDefaults.standard
        if code.isEmpty {
            d.removeObject(forKey: key)
            d.removeObject(forKey: chosenKey)
        } else {
            d.set([code], forKey: key)
            d.set(code, forKey: chosenKey)
        }
    }

    /// Sends the app to the background, then quits so it opens fresh in the new language.
    @MainActor static func closeApp() {
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exit(0) }
    }
}
