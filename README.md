# Kaufarchiv

Private Kaufverwaltung für iPhone und iPad: Belege erfassen, Rückgabe-, Gewährleistungs- und Garantiefristen verfolgen und bei einem Defekt sofort alle Unterlagen bereitstellen.

SwiftUI · SwiftData · Vision · StoreKit 2 · iOS 17+ (Dokumentstruktur-Erkennung ab iOS 26)

## Projekt öffnen

Das Xcode-Projekt wird aus `project.yml` erzeugt und ist deshalb nicht eingecheckt.

```bash
brew install xcodegen
xcodegen generate
open Kaufarchiv.xcodeproj
```

Vor dem ersten Start auf einem Gerät:

1. Bei allen drei Targets das eigene Team unter **Signing & Capabilities** wählen.
2. Bundle-IDs (`ch.kaufarchiv.app`, `…share`), App Group `group.ch.kaufarchiv.app` und iCloud-Container `iCloud.ch.kaufarchiv.app` an die eigene Kennung anpassen. Danach im Code `SharedInbox.appGroupID` und `Persistence.cloudContainerID` mitziehen.
3. In App Store Connect die Produkte `ch.kaufarchiv.pro.yearly` (Abo, 1 Jahr) und `ch.kaufarchiv.pro.lifetime` (nicht verbrauchbar) anlegen. Lokal testet das Schema mit `Kaufarchiv/Resources/Kaufarchiv.storekit`.

Tests:

```bash
# Kernlogik (läuft auch auf macOS ohne Simulator)
cd Packages/KaufarchivCore && swift test

# App-Tests (SwiftData, Sicherung, Dossier)
xcodebuild test -scheme Kaufarchiv -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Aufbau

```
Packages/KaufarchivCore      Plattformunabhängige, getestete Logik
  ReceiptParser              Händler, Datum, Total, Positionen, Seriennummern, Bestellnummer,
                             Kaufart, Land, Garantie- und Rückgabehinweise – jeder Wert mit Fundstelle
  MoneyParser / DateParser   1'234.50 · 1.234,50 · 29.– · 12. März 2025 · 05/10/26 …
  LineAssembler              Fügt von der Texterkennung getrennte Zeilenteile wieder zusammen
  LegalRules / Coverage      Länderregeln (CH, DE, AT, FR, IT, ES, PT, NL, BE, LU, SE, EU)
                             und Fristberechnung, getrennt nach Rückgabe, Widerruf,
                             Gewährleistung, Herstellergarantie, Zusatzgarantie
  ReminderPlanner            Plant die frühesten Erinnerungen innerhalb des iOS-Limits (64)
                             und meldet wartende und verpasste Erinnerungen
  ClaimTemplate              Nachrichtenentwurf für Reklamationen
Kaufarchiv/                  iOS-App
  Models                     SwiftData-Modelle (CloudKit-kompatibel)
  Services                   Texterkennung, Dokumentablage, Import, Erinnerungen, Kalender,
                             StoreKit, Sicherung/Wiederherstellung, Dossier-PDF, Spotlight, App-Sperre
  Views                      Übersicht · Meine Käufe · Fristen · Einstellungen,
                             Erfassung in 5 Schritten, Produktakte, Reklamationsablauf, Kaufseite
KaufarchivShare/             Teilen-Erweiterung: Rechnungen aus Mail, Dateien, Safari, Fotos übernehmen
KaufarchivTests/             App-Tests
```

## Wichtige Entscheidungen

- **Kein „grösster Betrag“**: Jeder Betrag wird zuerst eingeordnet (Total, Zwischensumme, Bargeld, Rückgeld, Rabatt, MwSt, Anzahlung, Kartenzahlung, Position). Das Total wird über Kartenzahlung, Bargeld minus Rückgeld oder Positionssumme bestätigt.
- **Mehrere Produkte pro Rechnung**: Jede gewählte Position wird ein eigenes Produkt mit eigenen Fristen; alle verweisen auf denselben Originalbeleg.
- **Nachvollziehbarkeit**: Jeder erkannte Wert speichert Seite, Position und Textausschnitt. Ein Tipp zeigt die markierte Stelle im Beleg. Unsichere Werte erscheinen als Vorschlag.
- **Fristen getrennt**: Gesetzliche Gewährleistung, Herstellergarantie, Zusatzgarantie, Rückgaberecht des Händlers und gesetzlicher Widerruf (nicht in der Schweiz) sind eigene Einträge.
- **Ehrliche Erinnerungen**: Die App zeigt, was bei iOS tatsächlich geplant ist, wie viele Erinnerungen wegen des Limits warten und bis wann die App geöffnet werden sollte. Fristen lassen sich zusätzlich in den Kalender übertragen.
- **Originale bleiben unverändert**: Originaldatei mit SHA-256-Prüfsumme, Vorschau separat. Die Sicherung enthält alle Originale und wird beim Wiederherstellen geprüft. „Wiederherstellbarkeit prüfen“ testet den kompletten Export.
- **Lokal zuerst**: Texterkennung auf dem Gerät, keine Werbung, kein Tracking. iCloud ist optional (Pro).
- **Fair bezahlen**: 10 Produkte gratis; Pro jährlich oder dauerhaft. Preise kommen immer aus StoreKit. Export und Originalbelege bleiben ohne Pro verfügbar.
