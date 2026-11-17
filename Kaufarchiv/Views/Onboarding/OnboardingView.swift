import SwiftUI
import KaufarchivCore

struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(ReminderService.self) private var reminders
    @AppStorage(SettingsKey.defaultCountry) private var defaultCountry = "CH"
    @State private var page = 0

    var body: some View {
        VStack {
            TabView(selection: $page) {
                OnboardingPage(symbol: "doc.viewfinder", title: "Beleg fotografieren – fertig",
                               text: "Kaufarchiv liest Händler, Datum, Betrag und Produkte direkt auf deinem iPhone. Mehrere Produkte einer Rechnung bekommen eigene Fristen.")
                    .tag(0)
                OnboardingPage(symbol: "doc.text.magnifyingglass", title: "Jeder Wert ist nachvollziehbar",
                               text: "Tippe auf Datum oder Preis und sieh die Stelle im Beleg. Unsichere Angaben sind als Vorschlag markiert.")
                    .tag(1)
                OnboardingPage(symbol: "exclamationmark.bubble", title: "Defekt? In zwei Minuten reklamiert",
                               text: "Produkt suchen, Fehler beschreiben, Fotos ergänzen – Rechnung, Seriennummer und Nachrichtenentwurf sind sofort bereit.")
                    .tag(2)
                setupPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 3 {
                    withAnimation { page += 1 }
                } else {
                    Task {
                        await reminders.requestAuthorization()
                        onFinish()
                    }
                }
            } label: {
                Text(page < 3 ? "Weiter" : "Erinnerungen erlauben und starten")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            if page == 3 {
                Button("Ohne Erinnerungen starten", action: onFinish)
                    .padding(.bottom)
            }
        }
    }

    private var setupPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe.europe.africa")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Wo kaufst du meistens ein?")
                .font(.title2.bold())
            Picker("Land", selection: $defaultCountry) {
                ForEach(LegalRules.all) { Text($0.name).tag($0.code) }
            }
            .pickerStyle(.wheel)
            .frame(height: 140)
            Text("Damit schlägt Kaufarchiv passende gesetzliche Fristen vor. Du kannst sie bei jedem Kauf anpassen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

private struct OnboardingPage: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(32)
    }
}
