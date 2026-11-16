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
| App Group `group.ch.kaufarchiv.app` anlegen bzw. umbenennen (App **und** Teilen-Erweiterung) | `Shared/InboxStore.swift`, beide Entitlements in `Config/` |
| Bundle-ID der Erweiterung `<Bundle-ID>.ShareExtension` | Target *ShareExtension* |
| iCloud-Container `iCloud.<Bundle-ID>` anlegen, CloudKit-Schema in die Produktion übernehmen | `Config/Kaufarchiv.entitlements` |
| `aps-environment` für den Store auf `production` (macht Xcode beim Archivieren automatisch) | `Config/Kaufarchiv.entitlements` |
| Datenschutz-URL (derzeit Platzhalter `example.com`) | `AppLinks` in `App/Views/PaywallAndSettings.swift` |

Mit einem kostenlosen Apple-Entwicklerkonto sind iCloud, Push und App Groups nicht verfügbar. In diesem Fall `CODE_SIGN_ENTITLEMENTS` bei beiden Targets entfernen; die App läuft dann rein lokal, Entwürfe landen in einem lokalen Eingang und die Teilen-Erweiterung kann nichts übergeben (PDFs und Bilder lassen sich weiterhin über «Öffnen mit» an die App geben).

## Funktionsumfang

**Erfassen in fünf Schritten** – Beleg scannen, Foto oder PDF wählen oder aus einer anderen App teilen → Produkte auswählen → Angaben prüfen → Fristen bestätigen → speichern. Erfassung ohne Beleg ist ebenfalls möglich.

- **Teilen-Erweiterung und Eingang:** Die Erweiterung legt geteilte PDFs und Bilder unverändert im Eingang ab; Erkennung und Speichern macht nur die Haupt-App. Abgebrochene Erfassungen lassen sich als Entwurf in denselben Eingang sichern. Die Übersicht zeigt, was noch nicht erfasst ist.
- **Keine Scheinfristen:** Ohne erkanntes oder bestätigtes Kaufdatum werden Fristen nur als unbestätigte Vorschläge gespeichert. Vorschläge werden neutral dargestellt und lösen keine Erinnerungen aus.
- **Lieferdatum:** Bei späterem Erhalt der Ware beginnen die Fristen mit der Lieferung.
- **Dateiprüfung:** Grössenlimit 50 MB, höchstens 12 Seiten für die Erkennung, verständliche Meldung bei passwortgeschützten PDFs, Hinweis bei bereits gespeicherter Datei (Prüfsumme).

- **Mehrere Produkte pro Rechnung:** jede Position wird eine eigene Produktakte mit eigenen Fristen, bleibt aber mit derselben Originalrechnung verbunden.
- **Nachvollziehbare Erkennung:** zu Händler, Datum, Betrag und jeder Position lässt sich die Fundstelle im Beleg anzeigen. Unsichere Werte sind als «Vorschlag» markiert.
- **Beträge richtig unterscheiden:** Gesamtbetrag, Zwischensumme, MwSt, Bargeld, Rückgeld und Rabatte werden getrennt erkannt. Bar gegebener Betrag und Rückgeld werden nie als Preis übernommen.
- **Vier getrennte Fristen:** Rückgabe/Widerruf, gesetzliche Mängelrechte, Herstellergarantie, Zusatzgarantie. Länderregeln für CH, LI, DE, AT, FR, IT, ES, PT, NL, BE, LU, SE (z. B. kein allgemeines Widerrufsrecht in der Schweiz, drei Jahre in Portugal und Spanien). Alle Werte sind bestätigungspflichtige Vorschläge.
- **Ehrliche Erinnerungen:** nur für bestätigte Fristen, zurückhaltend formuliert, Produktnamen auf Wunsch ausgeblendet. Jede Frist zeigt ihren Status (geplant, Mitteilungen deaktiviert, wird später eingeplant). Lokale Mitteilungen werden bei jedem Start neu geplant; die App zeigt die *vom System tatsächlich eingeplanten* Erinnerungen und weist aus, wie viele wegen des iOS-Limits (64) erst später geplant werden. Zusätzlich Kalenderübergabe pro Frist.
- **Produktakte:** Seriennummer, Kategorie, Raum, Notizen, Status (im Besitz, zurückgegeben, verkauft, entsorgt), weitere Dokumente (Garantiebedingungen, Anleitung, Fotos), Reparaturen.
- **Suche** über Produkt, Händler, Seriennummer, Bestellnummer und den erkannten Text aller Dokumente.
- **Rückgabe-Ablauf:** Bei laufender Rückgabefrist «Behalten» oder «Rückgabe vorbereiten»; mit Nachrichtenentwurf, Sendungsnummer, Verlauf und ausdrücklicher Bestätigung der Erstattung. Erst dann wird das Produkt als zurückgegeben archiviert.
- **Reklamationsablauf:** Produkt wählen, Mangel beschreiben, Fotos ergänzen → Nachrichtenentwurf (kopieren, teilen, in Mail öffnen), Verlauf mit Status und ein PDF-Dossier mit Produktdaten, Verlauf, Fotos und allen Originalunterlagen.
- **Datensicherheit:** Originaldateien werden unverändert gespeichert, die Vorschau getrennt. CSV-Export, ZIP aller Originale, vollständige Sicherung in einer Datei, Wiederherstellung mit Vorschau vor dem Zusammenführen und ein Sicherungstest mit Prüfsummenvergleich. Optionale App-Sperre mit Face ID.
- **Kaufarchiv Pro (StoreKit 2):** unbegrenzte Produkte (gratis: 10), Reklamationsdossier, iCloud-Synchronisation. Preise werden ausschliesslich aus StoreKit geladen. Die Kaufseite erscheint erst beim elften Produkt oder beim Aufruf einer Pro-Funktion. Originalbelege und Export bleiben immer zugänglich.

## Aufbau

```
Kaufarchiv.xcodeproj      Xcode-Projekt (App, Teilen-Erweiterung, lokales Swift-Paket)
Shared/                   Eingang – von App und Erweiterung gemeinsam genutzt
ShareExtension/           Teilen-Erweiterung
App/                      SwiftUI-App
  Models/                 SwiftData-Modelle (CloudKit-tauglich)
  Services/               Texterkennung, Erinnerungen, StoreKit, Sicherung, Dossier, App-Sperre
  Views/                  Übersicht, Meine Käufe, Fristen, Einstellungen, Erfassung, Reklamation
Config/                   Info.plist-Ergänzungen, Entitlements, StoreKit-Testkonfiguration
KaufarchivCore/           Plattformunabhängige Logik mit Unit-Tests:
                          Belegerkennung, Betrags- und Datumsparser, Länderregeln,
                          Erinnerungsplanung, Nachrichtenentwurf, CSV
```

## Abgleich mit dem Produktplan – noch offen

Der Plan sieht für die erste Version mehr vor, als hier umgesetzt ist. Nicht enthalten sind:

- **`RecognizeDocumentsRequest` (iOS 26) und Auswertung des PDF-Textlayers:** Die Erkennung nutzt `VNRecognizeTextRequest` auf gerenderten Seiten mit eigener Zeilenrekonstruktion. Die neuere API konnte hier nicht gegen das SDK geprüft werden.
- **Papierkorb für 30 Tage:** Löschen ist nach einer Rückfrage endgültig.
- **Versioniertes Regelwerk mit Quelle und Prüfdatum je Regel**, Parser-Version je übernommenem Wert, Unterscheidung Neu-/Gebrauchtware.
- **Core Data mit Haushaltsteilung:** Umgesetzt ist SwiftData für ein einzelnes iCloud-Konto – der Plan nennt das als zulässige einfachere Alternative. Synchronisationsstatus je Anhang und Konfliktanzeige fehlen.
- **Erinnerungsgerät wählen**, Bündelung mehrerer Erinnerungen am selben Tag.
- **Englische Oberfläche**, Demobeleg, Spotlight, Widget, App Intents, optionale Kürzung von Produktnamen mit Foundation Models.
- **Dateischutzklasse** für den Datenspeicher ist nicht ausdrücklich gesetzt (es gilt der iOS-Standard); die App-Sperre allein verschlüsselt nichts.
- **Fristen pro Produkt im Erfassungsablauf:** Beim Erfassen gelten die Fristen für alle gewählten Produkte einer Rechnung; die Anpassung je Produkt erfolgt danach in der Produktakte.
- **Entwürfe** sichern den Beleg, nicht die bereits geprüften Angaben; diese werden beim nächsten Öffnen neu erkannt.
- Die Qualitätsziele des Plans (Erkennungsquoten, Zeitziele, Testmatrix aus Kapitel 13 und 14) sind nicht gemessen – dafür braucht es echte Belege und Geräte.
- Die hinterlegten Fristen sind Ausgangswerte und keine Rechtsberatung; der Plan verlangt vor Veröffentlichung eine fachliche Prüfung.
