# Kaufarchiv

Private Kaufverwaltung für iPhone und iPad: Belege erfassen, Rückgabe- und Garantiefristen verfolgen und bei einem Defekt sofort alle Unterlagen bereitstellen.

Geschrieben in Swift (SwiftUI, SwiftData, Vision, StoreKit 2), ohne Drittanbieter-Abhängigkeiten, ohne Server, ohne Werbung und ohne Tracking.

> **Stand:** Der Code wurde in einer Linux-Umgebung ohne Xcode geschrieben und dort **nicht kompiliert und nicht ausgeführt**. Beim ersten Öffnen in Xcode sind einzelne Compilerfehler möglich. Auch die Unit-Tests in `KaufarchivCore` sind von Hand nachvollzogen, aber noch nicht gelaufen.

## Öffnen und starten

1. `Kaufarchiv.xcodeproj` mit Xcode 16 oder neuer öffnen (das Projekt verwendet synchronisierte Ordner).
2. Unter *Signing & Capabilities* das eigene Team wählen und die Bundle-ID `ch.kaufarchiv.app` durch eine eigene ersetzen.
3. Schema **Kaufarchiv** auf einem Simulator oder Gerät mit iOS 17+ starten. Belege scannen funktioniert nur auf einem echten Gerät.
4. Tests: `⌘U` oder im Ordner `KaufarchivCore` `swift test` ausführen.

Das Schema verweist bereits auf `Config/Products.storekit`, sodass Käufe im Simulator ohne App Store Connect getestet werden können. Im Debug-Build gibt es zusätzlich *Einstellungen › Entwicklung › Pro simulieren*.

## Vor der Veröffentlichung anpassen

| Was | Wo |
| --- | --- |
| Bundle-ID und Team | Target-Einstellungen |
| Produkt-IDs `ch.kaufarchiv.pro.yearly` / `ch.kaufarchiv.pro.lifetime` in App Store Connect anlegen | `App/Services/PurchaseManager.swift`, `Config/Products.storekit` |
| iCloud-Container `iCloud.<Bundle-ID>` anlegen, CloudKit-Schema in die Produktion übernehmen | `Config/Kaufarchiv.entitlements` |
| `aps-environment` für den Store auf `production` (macht Xcode beim Archivieren automatisch) | `Config/Kaufarchiv.entitlements` |
| Datenschutz-URL (derzeit Platzhalter `example.com`) | `AppLinks` in `App/Views/PaywallAndSettings.swift` |

Mit einem kostenlosen Apple-Entwicklerkonto sind iCloud und Push nicht verfügbar. In diesem Fall `CODE_SIGN_ENTITLEMENTS` aus den Build-Einstellungen entfernen; die App läuft dann rein lokal.

## Funktionsumfang

**Erfassen in fünf Schritten** – Beleg scannen, Foto oder PDF wählen oder aus einer anderen App über «Teilen/Öffnen mit» übergeben → Produkte auswählen → Angaben prüfen → Fristen bestätigen → speichern. Erfassung ohne Beleg ist ebenfalls möglich.

- **Mehrere Produkte pro Rechnung:** jede Position wird eine eigene Produktakte mit eigenen Fristen, bleibt aber mit derselben Originalrechnung verbunden.
- **Nachvollziehbare Erkennung:** zu Händler, Datum, Betrag und jeder Position lässt sich die Fundstelle im Beleg anzeigen. Unsichere Werte sind als «Vorschlag» markiert.
- **Beträge richtig unterscheiden:** Gesamtbetrag, Zwischensumme, MwSt, Bargeld, Rückgeld und Rabatte werden getrennt erkannt. Bar gegebener Betrag und Rückgeld werden nie als Preis übernommen.
- **Vier getrennte Fristen:** Rückgabe/Widerruf, gesetzliche Mängelrechte, Herstellergarantie, Zusatzgarantie. Länderregeln für CH, LI, DE, AT, FR, IT, ES, PT, NL, BE, LU, SE (z. B. kein allgemeines Widerrufsrecht in der Schweiz, drei Jahre in Portugal und Spanien). Alle Werte sind bestätigungspflichtige Vorschläge.
- **Ehrliche Erinnerungen:** lokale Mitteilungen werden bei jedem Start neu geplant; die App zeigt die *vom System tatsächlich eingeplanten* Erinnerungen und weist aus, wie viele wegen des iOS-Limits (64) erst später geplant werden. Zusätzlich Kalenderübergabe pro Frist.
- **Produktakte:** Seriennummer, Kategorie, Raum, Notizen, Status (im Besitz, zurückgegeben, verkauft, entsorgt), weitere Dokumente (Garantiebedingungen, Anleitung, Fotos), Reparaturen.
- **Suche** über Produkt, Händler, Seriennummer, Bestellnummer und den erkannten Text aller Dokumente.
- **Reklamationsablauf:** Produkt wählen, Mangel beschreiben, Fotos ergänzen → Nachrichtenentwurf (kopieren, teilen, in Mail öffnen), Verlauf mit Status und ein PDF-Dossier mit Produktdaten, Verlauf, Fotos und allen Originalunterlagen.
- **Datensicherheit:** Originaldateien werden unverändert gespeichert, die Vorschau getrennt. CSV-Export, ZIP aller Originale, vollständige Sicherung in einer Datei, Wiederherstellung und ein Sicherungstest mit Prüfsummenvergleich. Optionale App-Sperre mit Face ID.
- **Kaufarchiv Pro (StoreKit 2):** unbegrenzte Produkte (gratis: 10), Reklamationsdossier, iCloud-Synchronisation. Preise werden ausschliesslich aus StoreKit geladen. Die Kaufseite erscheint erst beim elften Produkt oder beim Aufruf einer Pro-Funktion. Originalbelege und Export bleiben immer zugänglich.

## Aufbau

```
Kaufarchiv.xcodeproj      Xcode-Projekt (ein App-Target, lokales Swift-Paket)
App/                      SwiftUI-App
  Models/                 SwiftData-Modelle (CloudKit-tauglich)
  Services/               Texterkennung, Erinnerungen, StoreKit, Sicherung, Dossier, App-Sperre
  Views/                  Übersicht, Meine Käufe, Fristen, Einstellungen, Erfassung, Reklamation
Config/                   Info.plist-Ergänzungen, Entitlements, StoreKit-Testkonfiguration
KaufarchivCore/           Plattformunabhängige Logik mit Unit-Tests:
                          Belegerkennung, Betrags- und Datumsparser, Länderregeln,
                          Erinnerungsplanung, Nachrichtenentwurf, CSV
```

## Bewusst offen gelassen

- **Share-Extension:** Die App nimmt PDFs und Bilder über «Öffnen mit / Teilen» als Dokumenttyp entgegen. Eine eigene Share-Extension (z. B. für markierten Text oder Webseiten) ist nicht enthalten.
- **`RecognizeDocumentsRequest` (iOS 26):** Die Erkennung nutzt `VNRecognizeTextRequest` mit eigener Zeilen- und Tabellenrekonstruktion. Die neuere Dokumentstruktur-API ist nicht eingebunden, weil sie hier nicht gegen das SDK geprüft werden konnte.
- **Fristen pro Produkt im Erfassungsablauf:** Beim Erfassen gelten die Fristen für alle gewählten Produkte einer Rechnung; die Anpassung je Produkt erfolgt danach in der Produktakte.
- **Sprache:** Oberfläche auf Deutsch; die Erkennung versteht deutsche, französische, italienische und englische Belege.
- Die hinterlegten Fristen sind Ausgangswerte und keine Rechtsberatung.
