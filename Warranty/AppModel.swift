import StoreKit
import SwiftUI
import UIKit
import WidgetKit

enum Route: Identifiable, Equatable {
    case capture, editor(UUID, fresh: Bool), paywall, settings, share(UUID), importCode, milestone(String)
    var id: String {
        switch self {
        case .capture: return "capture"
        case .editor(let id, let fresh): return "editor-\(id)-\(fresh)"
        case .paywall: return "paywall"
        case .settings: return "settings"
        case .share(let id): return "share-\(id)"
        case .importCode: return "import"
        case .milestone(let m): return "milestone-\(m)"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state = AppState()
    @Published var route: Route?
    @Published var notice: String?
    @Published var filter: String?
    @Published var query = ""
    @Published var busy = false
    @Published var notificationsDenied = false
    let purchases = StoreModel()
    private var loaded = false

    var today: Day { .today }
    var now: Date { Launch.testFlag("-expired") ? state.entitlement.firstOpen.addingTimeInterval(40 * 86_400) : Date() }
    var hasPro: Bool { state.entitlement.hasPro(at: now) }
    var trialDaysLeft: Int { max(0, Int(ceil(state.entitlement.trialEnd.timeIntervalSince(now) / 86_400))) }

    var visible: [Item] {
        var all = state.sorted(on: today)
        if let filter { all = all.filter { $0.category == filter } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { i in [i.displayName, i.store, i.model, i.serial, i.notes].contains { $0.lowercased().contains(q) } }
    }

    func start() {
        guard !loaded else { return }
        loaded = true
        if Launch.testFlag("-reset") { Store.reset() }
        if let saved = Store.load() {
            state = saved
        } else {
            state = AppState()
            state.entitlement.firstOpen = Launch.testing ? Date() : TrialAnchor.firstOpen(Date())
            if Launch.testFlag("-demo") { state.items = Demo.items(today: today) }
        }
        if Launch.testFlag("-paid") { state.entitlement.purchasedPro = true }
        if Launch.testFlag("-milestone-seen") { state.milestonesShown = ["ten"] }
        markOpen()
        persist()
        purchases.start(applyPurchase)
        Task { await reschedule() }
        pickUpInbox()
        if Launch.testFlag("-capture") { route = .capture }
        if Launch.testFlag("-paywall") { route = .paywall }
    }


    func persist() {
        do { try Store.save(state) } catch { notice = WarrantyError.save.message }
        WidgetCenter.shared.reloadTimelines(ofKind: Launch.widgetKind)
    }

    func item(_ id: UUID) -> Item? { state.items.first { $0.id == id } }

    func update(_ item: Item) {
        guard let i = state.items.firstIndex(where: { $0.id == item.id }) else { return }
        state.items[i] = item
        persist()
        Task { await reschedule() }
    }

    func delete(_ id: UUID) {
        guard let i = state.items.firstIndex(where: { $0.id == id }) else { return }
        Store.removeImages(state.items[i].photos)
        state.items.remove(at: i)
        persist()
        Task { await reschedule() }
    }


    func beginCapture() {
        guard state.canAdd(hasPro: hasPro) else { route = .paywall; notice = WarrantyError.limit.message; return }
        route = .capture
    }

    func addManual() {
        guard state.canAdd(hasPro: hasPro) else { route = .paywall; notice = WarrantyError.limit.message; return }
        var item = Item()
        item.purchased = today
        if let filter { item.category = filter }
        if item.isDocument { item.warrantyMonths = nil; item.expires = today.adding(months: 12) }
        insert(item)
    }

    func captured(_ images: [UIImage]) async {
        guard let first = images.first else { return }
        guard state.canAdd(hasPro: hasPro) else { route = .paywall; return }
        busy = true
        defer { busy = false }
        let parsed = ReceiptParser.parse(await OCR.lines(first), today: today)
        var item = Item()
        item.store = parsed.store ?? ""
        item.name = parsed.name ?? ""
        item.model = parsed.model ?? ""
        item.purchased = parsed.date ?? today
        item.price = parsed.amount ?? ""
        if let filter { item.category = filter }
        if item.isDocument { item.warrantyMonths = nil; item.expires = today.adding(months: 12) }
        item.photos = images.compactMap { $0.jpegForReceipt().flatMap { try? Store.writeImage($0) } }
        insert(item)
    }

    private func insert(_ item: Item) {
        state.items.append(item)
        persist()
        Task { await reschedule() }
        guard route != nil else { route = .editor(item.id, fresh: true); return }
        route = nil
        Task { try? await Task.sleep(for: .milliseconds(650)); route = .editor(item.id, fresh: true) }
    }

    func finishedEditing(_ fresh: Bool) {
        guard fresh else { return }
        if state.items.count >= 10, !state.milestonesShown.contains("ten") {
            state.milestonesShown.append("ten")
            persist()
            Task { try? await Task.sleep(for: .milliseconds(600)); route = .milestone("ten") }
            return
        }
        askReviewIfReady()
    }


    func pickUpInbox() {
        let files = Store.inboxFiles()
        guard !files.isEmpty else { return }
        let images = files.compactMap { url -> UIImage? in
            defer { try? FileManager.default.removeItem(at: url) }
            if url.pathExtension.lowercased() == "pdf" { return PDFThumb.image(url) }
            return UIImage(contentsOfFile: url.path)
        }
        guard !images.isEmpty else { notice = WarrantyError.unreadable.message; return }
        Task { await captured(images) }
    }


    func markFixed(_ id: UUID, saved: Double) {
        guard var item = item(id) else { return }
        item.saved = saved
        update(item)
        if !state.milestonesShown.contains("fixed") { state.milestonesShown.append("fixed"); persist() }
        Task { try? await Task.sleep(for: .milliseconds(600)); route = .share(id) }
    }


    func importCode(_ text: String) -> Bool {
        do {
            let item = try Transfer.item(from: text, categories: state.categories)
            guard state.canAdd(hasPro: hasPro) else { route = .paywall; notice = WarrantyError.limit.message; return false }
            state.items.append(item)
            persist()
            Task { await reschedule() }
            notice = L.f("import.done", item.displayName)
            return true
        } catch {
            notice = (error as? WarrantyError ?? .badCode).message
            return false
        }
    }


    func renameCategory(_ id: String, to name: String) {
        guard let i = state.categories.firstIndex(where: { $0.id == id }) else { return }
        let t = name.trimmingCharacters(in: .whitespaces)
        state.categories[i].custom = t.isEmpty ? nil : String(t.prefix(20))
        persist()
    }

    func addCategory(_ name: String) {
        let t = name.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        state.categories.insert(CategoryDef(id: "c" + UUID().uuidString.prefix(8), custom: String(t.prefix(20))), at: max(0, state.categories.count - 1))
        persist()
    }


    func setReminders(_ on: Bool) async {
        state.settings.reminders = on
        persist()
        await reschedule()
    }

    func reschedule() async {
        notificationsDenied = await Reminders.sync(state, today: today)
    }


    func applyPurchase(_ pro: Bool?, _ trial: Date?) async throws {
        if let pro { state.entitlement.purchasedPro = pro }
        if let trial { state.entitlement.trialClaimedAt = min(state.entitlement.trialClaimedAt ?? trial, trial) }
        try Store.save(state)
        WidgetCenter.shared.reloadTimelines(ofKind: Launch.widgetKind)
    }


    private func markOpen() {
        let d = today.iso
        if !state.openDays.contains(d) { state.openDays = Array((state.openDays + [d]).suffix(10)) }
    }

    private func askReviewIfReady() {
        guard !state.reviewAsked, state.openDays.count >= 3, !Launch.testing || Launch.testFlag("-review") else { return }
        state.reviewAsked = true
        persist()
        if Launch.testing { notice = "review.requested"; return }
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            AppStore.requestReview(in: scene)
        }
    }
}

extension UIImage {
    func jpegForReceipt() -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > 1600 ? 1600 / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: 0.6)
    }
}

enum Demo {
    static func items(today: Day) -> [Item] {
        func make(_ name: String, _ store: String, _ cat: String, bought: Day, months: Int?, returnDays: Int? = nil,
                  extended: Day? = nil, expires: Day? = nil, model: String = "", phone: String = "", price: String = "") -> Item {
            var i = Item()
            i.name = name; i.store = store; i.category = cat; i.purchased = bought; i.warrantyMonths = months
            i.returnDays = returnDays; i.extendedEnd = extended; i.expires = expires; i.model = model; i.phone = phone; i.price = price
            return i
        }
        return [
            make(L.t("demo.dishwasher"), "Costco", "appliance", bought: today.adding(days: 14).adding(months: -12), months: 12,
                 model: "SHPM65Z55N", phone: "1-800-944-2904", price: "919.11"),
            make(L.t("demo.headphones"), "Best Buy", "electronics", bought: today.adding(days: -27), months: 12, returnDays: 30, price: "349.99"),
            make(L.t("demo.passport"), "", "document", bought: today, months: nil, expires: today.adding(months: 5)),
            make("MacBook Air", "Apple", "electronics", bought: today.adding(months: -17), months: 12,
                 extended: today.adding(months: 19), price: "1199.00"),
            make(L.t("demo.battery"), "AutoZone", "car", bought: today.adding(months: -12), months: 36, price: "189.99")
        ] + (Launch.testFlag("-demo-old") ? [make("Blender", "Target", "appliance", bought: today.adding(months: -30), months: 24, price: "79.99")] : [])
    }
}
