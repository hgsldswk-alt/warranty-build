import Foundation

struct Day: Codable, Hashable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    static func valid(year: Int, month: Int, day: Int) -> Day? {
        guard (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let back = Day(date, calendar: calendar)
        return back.year == year && back.month == month && back.day == day ? back : nil
    }

    var utcDate: Date { Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))! }

    func local(hour: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }

    func adding(months: Int) -> Day {
        Day(Self.calendar.date(byAdding: .month, value: months, to: utcDate)!, calendar: Self.calendar)
    }

    func adding(days: Int) -> Day {
        Day(Self.calendar.date(byAdding: .day, value: days, to: utcDate)!, calendar: Self.calendar)
    }

    func days(until other: Day) -> Int {
        Self.calendar.dateComponents([.day], from: utcDate, to: other.utcDate).day ?? 0
    }

    static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    static var today: Day {
        if Launch.testing, let raw = Launch.arguments.firstIndex(of: "-today").map({ Launch.arguments[$0 + 1] }),
           let d = Day(iso: raw) { return d }
        return Day(Date())
    }

    init?(iso: String) {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = Day.valid(year: p[0], month: p[1], day: p[2]) else { return nil }
        self = d
    }

    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var label: String { utcDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: TimeZone(identifier: "UTC")!)) }
}

enum DeadlineKind: String, Codable, CaseIterable {
    case returnWindow, warranty, extended, document

    var leadDays: [Int] {
        switch self {
        case .returnWindow: return [3]
        case .warranty, .extended: return [14, 1]
        case .document: return [60, 14]
        }
    }
}

struct Deadline: Equatable {
    var kind: DeadlineKind
    var day: Day
}

struct Item: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var store = ""
    var category = "appliance"
    var purchased: Day?
    var price = ""
    var warrantyMonths: Int? = 12
    var extendedEnd: Day?
    var returnDays: Int?
    var expires: Day?
    var model = ""
    var serial = ""
    var phone = ""
    var notes = ""
    var photos: [String] = []
    var saved: Double?
    var created = Date()

    var isDocument: Bool { category == "document" }
    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        let s = store.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? L.t("item.untitled") : s
    }

    var warrantyEnd: Day? {
        guard !isDocument, let purchased, let warrantyMonths, warrantyMonths > 0 else { return nil }
        return purchased.adding(months: warrantyMonths)
    }

    var returnEnd: Day? {
        guard !isDocument, let purchased, let returnDays, returnDays > 0 else { return nil }
        return purchased.adding(days: returnDays)
    }

    var deadlines: [Deadline] {
        if isDocument { return expires.map { [Deadline(kind: .document, day: $0)] } ?? [] }
        var out: [Deadline] = []
        if let r = returnEnd { out.append(Deadline(kind: .returnWindow, day: r)) }
        if let w = warrantyEnd { out.append(Deadline(kind: .warranty, day: w)) }
        if let e = extendedEnd, e > (warrantyEnd ?? Day(year: 1900, month: 1, day: 1)) { out.append(Deadline(kind: .extended, day: e)) }
        return out.sorted { $0.day < $1.day }
    }

    func next(after today: Day) -> Deadline? {
        deadlines.first { $0.day >= today } ?? deadlines.last
    }

    func active(on today: Day) -> Bool {
        guard let last = deadlines.last else { return true }
        return last.day >= today
    }

    func progress(on today: Day) -> Double? {
        guard let purchased, let end = (extendedEnd ?? warrantyEnd) else { return nil }
        let total = purchased.days(until: end)
        guard total > 0 else { return nil }
        return min(1, max(0, Double(purchased.days(until: today)) / Double(total)))
    }
}

struct CategoryDef: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var custom: String?
    var title: String {
        if let custom, !custom.trimmingCharacters(in: .whitespaces).isEmpty { return custom }
        return L.t("cat." + id)
    }

    static let presets = ["appliance", "electronics", "furniture", "car", "tools", "document", "other"]
        .map { CategoryDef(id: $0) }
}

struct Entitlement: Codable, Equatable {
    var firstOpen = Date()
    var trialClaimedAt: Date?
    var purchasedPro = false

    var trialStart: Date { min(firstOpen, trialClaimedAt ?? firstOpen) }
    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86_400) }
    func hasPro(at now: Date) -> Bool {
        Launch.freePeriod || purchasedPro || (now >= trialStart && now < trialEnd)
    }
}

struct Settings: Codable, Equatable {
    var reminders = true
    var hour = 10
}

struct AppState: Codable, Equatable {
    var items: [Item] = []
    var categories = CategoryDef.presets
    var entitlement = Entitlement()
    var settings = Settings()
    var openDays: [String] = []
    var reviewAsked = false
    var milestonesShown: [String] = []

    func category(_ id: String) -> CategoryDef {
        categories.first { $0.id == id } ?? CategoryDef(id: "other")
    }

    func sorted(on today: Day) -> [Item] {
        let active = items.filter { $0.active(on: today) }.sorted {
            let a = $0.next(after: today)?.day, b = $1.next(after: today)?.day
            switch (a, b) {
            case let (x?, y?): return x == y ? $0.created > $1.created : x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.created > $1.created
            }
        }
        let expired = items.filter { !$0.active(on: today) }.sorted {
            ($0.deadlines.last?.day ?? today) > ($1.deadlines.last?.day ?? today)
        }
        return active + expired
    }

    func soon(on today: Day, within days: Int = 14) -> [Item] {
        sorted(on: today).filter {
            guard let d = $0.next(after: today)?.day, d >= today else { return false }
            return today.days(until: d) <= days
        }
    }

    func canAdd(hasPro: Bool) -> Bool { hasPro || items.count < Launch.freeLimit }
}

enum WarrantyError: Error, Equatable {
    case store, unreadable, badCode, limit, save

    var message: String {
        switch self {
        case .store: return L.t("error.store")
        case .unreadable: return L.t("error.unreadable")
        case .badCode: return L.t("error.badCode")
        case .limit: return L.f("error.limit", Launch.freeLimit)
        case .save: return L.t("error.save")
        }
    }
}

enum Remaining {
    static func text(from today: Day, to end: Day) -> String {
        let days = today.days(until: end)
        if days < 0 { return L.t("left.expired") }
        if days == 0 { return L.t("left.today") }
        if days < 60 { return L.f("left.days", days) }
        let c = Day.calendar.dateComponents([.year, .month], from: today.utcDate, to: end.utcDate)
        let y = c.year ?? 0, m = c.month ?? 0
        if y == 0 { return L.f("left.months", m) }
        if m == 0 { return L.f("left.years", y) }
        return L.f("left.yearsMonths", y, m)
    }
}
