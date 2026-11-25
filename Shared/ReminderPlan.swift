import Foundation

struct PlannedReminder: Equatable {
    var id: String
    var day: Day
    var itemID: UUID
    var kind: DeadlineKind
    var leadDays: Int
    var end: Day
}

enum ReminderPlan {
    static func plan(_ state: AppState, today: Day) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        for item in state.items {
            for d in item.deadlines {
                for lead in d.kind.leadDays {
                    let fire = d.day.adding(days: -lead)
                    guard fire >= today else { continue }
                    out.append(PlannedReminder(id: "\(item.id.uuidString)-\(d.kind.rawValue)-\(lead)", day: fire,
                                               itemID: item.id, kind: d.kind, leadDays: lead, end: d.day))
                }
            }
        }
        return Array(out.sorted { $0.day == $1.day ? $0.id < $1.id : $0.day < $1.day }.prefix(60))
    }

    static func title(_ r: PlannedReminder, name: String) -> String {
        L.f("notify.title." + r.kind.rawValue, name)
    }

    static func body(_ r: PlannedReminder) -> String {
        L.f("notify.body", r.leadDays, r.end.label)
    }
}
