import Foundation
import KaufarchivCore

#if os(macOS)
import Vision
import ImageIO
import CoreGraphics

// Prüfwerkzeug für echte Belegfotos.
// Verwendet dieselben Einstellungen wie die App (App/Services/DocumentProcessing.swift):
// Bild aufrecht normalisieren (max. 2400 px), VNRecognizeTextRequest «accurate» ohne Sprachkorrektur,
// Zeilenrekonstruktion und ReceiptParser aus KaufarchivCore.

func loadImage(_ url: URL, maxDimension: Int = 2400) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

func recognize(_ image: CGImage) throws -> [TextLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["de-DE", "fr-FR", "it-IT", "en-US"]
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    var fragments: [TextLine] = []
    for observation in request.results ?? [] {
        guard let candidate = observation.topCandidates(1).first else { continue }
        let box = observation.boundingBox
        fragments.append(TextLine(
            text: candidate.string,
            box: NormRect(x: Double(box.minX), y: Double(1 - box.maxY), width: Double(box.width), height: Double(box.height)),
            page: 0,
            confidence: Double(candidate.confidence)
        ))
    }
    return LayoutReconstructor.rows(from: fragments)
}

func label(_ confidence: Confidence) -> String {
    switch confidence {
    case .high: return "hoch"
    case .medium: return "mittel"
    case .low: return "niedrig"
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("Aufruf: ReceiptEval <Ordner mit Bildern>")
    exit(2)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff", "webp", "gif"]
let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
    .filter { extensions.contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

let dateFormatter = DateFormatter()
dateFormatter.locale = Locale(identifier: "en_US_POSIX")
dateFormatter.dateFormat = "yyyy-MM-dd"

var processed = 0
for file in files {
    print("")
    print("=== \(file.lastPathComponent) ===")
    guard let image = loadImage(file) else {
        print("FEHLER: Bild nicht lesbar")
        continue
    }
    let started = Date()
    let lines: [TextLine]
    do {
        lines = try recognize(image)
    } catch {
        print("FEHLER: Texterkennung: \(error)")
        continue
    }
    let seconds = Date().timeIntervalSince(started)
    let draft = ReceiptParser.parse(lines: lines, now: Date(), calendar: Calendar(identifier: .gregorian), defaultCurrency: "CHF")
    processed += 1

    print("Bild \(image.width)x\(image.height), \(lines.count) Zeilen, OCR \(String(format: "%.2f", seconds)) s")
    print("--- Zeilen ---")
    for (index, line) in lines.enumerated() {
        print(String(format: "%3d | %@", index, line.text))
    }
    print("--- Ergebnis ---")
    func show<T>(_ name: String, _ detected: Detected<T>?, _ text: (T) -> String) {
        if let detected {
            let lineText = detected.lineIndex.map { "Zeile \($0)" } ?? "ohne Fundstelle"
            print("\(name): \(text(detected.value)) [\(label(detected.confidence)), \(lineText)]")
        } else {
            print("\(name): –")
        }
    }
    show("Händler", draft.merchant) { $0 }
    show("Datum", draft.purchaseDate) { dateFormatter.string(from: $0) }
    show("Total", draft.total) { "\($0)" }
    print("Währung: \(draft.currency)")
    show("Bestellnr", draft.orderNumber) { $0 }
    if let given = draft.cashGiven { print("Bar gegeben: \(given)") }
    if let change = draft.change { print("Rückgeld: \(change)") }
    print("Online: \(draft.isOnlineOrder)")
    for serial in draft.serialNumbers { print("Seriennummer: \(serial.value)") }
    print("Positionen: \(draft.items.count)")
    for item in draft.items {
        let unit = item.unitPrice.map { "\($0)" } ?? "–"
        let total = item.totalPrice.map { "\($0)" } ?? "–"
        let lineText = item.lineIndex.map { "Zeile \($0)" } ?? "–"
        print("  \(item.quantity) x \(item.name) | Einzel \(unit) | Total \(total) [\(label(item.confidence)), \(lineText)]")
    }
    let sum = draft.items.reduce(Decimal(0)) { $0 + ($1.totalPrice ?? 0) }
    if let total = draft.total?.value, !draft.items.isEmpty {
        print("Summe Positionen: \(sum) | Differenz zum Total: \(total - sum)")
    }
}
print("")
print("Verarbeitet: \(processed) von \(files.count) Bildern")
#else
print("ReceiptEval läuft nur unter macOS.")
#endif
