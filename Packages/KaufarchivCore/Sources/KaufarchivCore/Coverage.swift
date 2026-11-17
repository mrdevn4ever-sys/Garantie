import Foundation

/// The different kinds of protection a purchase can have. They are tracked separately on purpose.
public enum CoverageKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Voluntary return/exchange policy of the retailer.
    case returnPolicy
    /// Statutory right of withdrawal for online/distance purchases.
    case withdrawal
    /// Statutory liability for defects (Gewährleistung / Mängelrechte).
    case statutory
    /// Manufacturer guarantee (Herstellergarantie).
    case manufacturer
    /// Paid or bundled extended warranty / insurance.
    case extended

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .returnPolicy: "Rückgabe/Umtausch"
        case .withdrawal: "Widerrufsrecht"
        case .statutory: "Gesetzliche Gewährleistung"
        case .manufacturer: "Herstellergarantie"
        case .extended: "Zusatzgarantie"
        }
    }

    public var shortTitle: String {
        switch self {
        case .returnPolicy: "Rückgabe"
        case .withdrawal: "Widerruf"
        case .statutory: "Gewährleistung"
        case .manufacturer: "Garantie"
        case .extended: "Zusatzgarantie"
        }
    }

    public var symbolName: String {
        switch self {
        case .returnPolicy: "arrow.uturn.backward.circle"
        case .withdrawal: "envelope.arrow.triangle.branch"
        case .statutory: "building.columns"
        case .manufacturer: "checkmark.shield"
        case .extended: "plus.circle"
        }
    }

    /// Default reminder offsets in days before the end date.
    public var defaultReminderOffsets: [Int] {
        switch self {
        case .returnPolicy, .withdrawal: [3, 1]
        case .statutory, .manufacturer, .extended: [30, 7]
        }
    }

    /// Threshold (days) under which a deadline is considered "soon".
    public var soonThresholdDays: Int {
        switch self {
        case .returnPolicy, .withdrawal: 5
        case .statutory, .manufacturer, .extended: 45
        }
    }
}

/// Plain-value description of one coverage, used by the calculator and planner.
public struct CoverageSpec: Codable, Hashable, Sendable {
    public var kind: CoverageKind
    public var start: Date
    /// Either a duration …
    public var months: Int?
    public var days: Int?
    /// … or an explicit end date (takes precedence).
    public var explicitEnd: Date?

    public init(kind: CoverageKind, start: Date, months: Int? = nil, days: Int? = nil, explicitEnd: Date? = nil) {
        self.kind = kind
        self.start = start
        self.months = months
        self.days = days
        self.explicitEnd = explicitEnd
    }

    public func endDate(calendar: Calendar = .current) -> Date? {
        if let explicitEnd { return explicitEnd }
        var comps = DateComponents()
        comps.month = months
        comps.day = days
        guard months != nil || days != nil else { return nil }
        return calendar.date(byAdding: comps, to: start)
    }
}

public enum DeadlineStatus: Hashable, Sendable {
    case active(daysLeft: Int)
    case soon(daysLeft: Int)
    case endsToday
    case expired(daysAgo: Int)
    case unknown

    public var isActive: Bool {
        switch self {
        case .active, .soon, .endsToday: true
        case .expired, .unknown: false
        }
    }

    public var label: String {
        switch self {
        case let .active(d): d == 1 ? "noch 1 Tag" : "noch \(d) Tage"
        case let .soon(d): d == 1 ? "noch 1 Tag" : "noch \(d) Tage"
        case .endsToday: "endet heute"
        case let .expired(d): d == 0 ? "abgelaufen" : (d == 1 ? "seit 1 Tag abgelaufen" : "seit \(d) Tagen abgelaufen")
        case .unknown: "keine Frist"
        }
    }
}

public enum DeadlineCalculator {
    public static func status(end: Date?, kind: CoverageKind, now: Date = Date(), calendar: Calendar = .current) -> DeadlineStatus {
        guard let end else { return .unknown }
        let today = calendar.startOfDay(for: now)
        let endDay = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: today, to: endDay).day ?? 0
        if days < 0 { return .expired(daysAgo: -days) }
        if days == 0 { return .endsToday }
        if days <= kind.soonThresholdDays { return .soon(daysLeft: days) }
        return .active(daysLeft: days)
    }

    /// Fraction of the coverage period that has elapsed (0...1), for progress bars.
    public static func progress(start: Date, end: Date?, now: Date = Date()) -> Double {
        guard let end, end > start else { return 1 }
        let total = end.timeIntervalSince(start)
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }

    /// Builds the default coverages for a new purchase.
    public static func defaultCoverages(purchaseDate: Date,
                                        deliveryDate: Date? = nil,
                                        countryCode: String,
                                        channel: SalesChannel,
                                        returnDays: Int?,
                                        manufacturerMonths: Int?) -> [CoverageSpec] {
        let rules = LegalRules.rules(for: countryCode)
        let handover = deliveryDate ?? purchaseDate
        var specs: [CoverageSpec] = []
        if let returnDays {
            specs.append(CoverageSpec(kind: .returnPolicy, start: purchaseDate, days: returnDays))
        }
        if channel == .online, let withdrawal = rules.onlineWithdrawalDays {
            specs.append(CoverageSpec(kind: .withdrawal, start: handover, days: withdrawal))
        }
        if let statutory = LegalRules.suggestedStatutoryMonths(for: countryCode) {
            specs.append(CoverageSpec(kind: .statutory, start: handover, months: statutory))
        }
        if let manufacturerMonths {
            specs.append(CoverageSpec(kind: .manufacturer, start: purchaseDate, months: manufacturerMonths))
        }
        return specs
    }
}
