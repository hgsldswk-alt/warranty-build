import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var exportFile: ExportFile?
    @State private var renaming: CategoryDef?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    exportSection
                    reminderSection
                    categorySection
                    SecondaryButton(title: L.t("list.import"), id: "settings.import", icon: "tray.and.arrow.down") {
                        model.route = nil
                        Task { try? await Task.sleep(for: .milliseconds(500)); model.route = .importCode }
                    }
                    purchaseSection
                }
                .padding(Theme.pageInset)
            }
            .tint(Theme.accent).background(Theme.background.ignoresSafeArea())
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationTitle(L.t("settings.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("action.done")) { model.route = nil }.testID("settings.done") } }
            .alert(L.t("category.rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(L.t("category.name"), text: $newName)
                Button(L.t("action.save")) { if let c = renaming { model.renameCategory(c.id, to: newName) }; renaming = nil }
                Button(L.t("action.cancel"), role: .cancel) { renaming = nil }
            }
        }
    }

    private var exportSection: some View {
        settingsSection(L.t("settings.export")) {
            Button { export(pdf: true) } label: {
                settingsRow(L.t("export.pdf"), icon: "doc.richtext", tone: .blue)
            }.buttonStyle(.plain).testID("export.pdf")
            Button { export(pdf: false) } label: {
                settingsRow(L.t("export.csv"), icon: "tablecells", tone: .mint)
            }.buttonStyle(.plain).testID("export.csv")
            Text(L.t("export.note")).font(.footnote).foregroundStyle(Theme.muted)
            if let f = exportFile {
                ShareLink(item: f.url) {
                    PrimaryButtonLabel(title: L.t("export.share") + " · " + f.url.lastPathComponent,
                                       icon: "square.and.arrow.up")
                }.buttonStyle(.plain).testID("export.ready")
            }
        }
    }

    private var reminderSection: some View {
        settingsSection(L.t("settings.reminders")) {
            Toggle(isOn: Binding(get: { model.state.settings.reminders },
                                 set: { v in Task { await model.setReminders(v) } })) {
                settingsRow(L.t("settings.remindersOn"), icon: "bell", tone: .amber)
            }.testID("settings.reminders")
            Stepper(value: Binding(get: { model.state.settings.hour },
                set: { model.state.settings.hour = $0; model.persist(); Task { await model.reschedule() } }), in: 6...22) {
                settingsRow(L.f("settings.hour", model.state.settings.hour), icon: "clock", tone: .amber)
            }
            Text(L.t("settings.leadNote")).font(.footnote).foregroundStyle(Theme.muted)
            if model.notificationsDenied {
                Label(L.t("settings.denied"), systemImage: "bell.slash").font(.footnote)
                    .foregroundStyle(Theme.dueText).testID("settings.denied")
                Button {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                } label: {
                    Label(L.t("camera.openSettings"), systemImage: "gearshape").secondaryControl()
                }.buttonStyle(.plain)
            }
        }
    }

    private var categorySection: some View {
        settingsSection(L.t("settings.categories")) {
            ForEach(model.state.categories) { c in
                let mark = CategoryMark(c.id)
                Button { renaming = c; newName = c.title } label: {
                    IconRow(title: c.title, icon: mark.icon, tone: mark.tone) {
                        Image(systemName: "pencil").foregroundStyle(Theme.muted).accessibilityHidden(true)
                    }
                }.buttonStyle(.plain).testID("category." + c.id)
            }
        }
    }

    private var purchaseSection: some View {
        settingsSection(L.t("settings.purchase")) {
            Button {
                model.route = nil
                Task { try? await Task.sleep(for: .milliseconds(500)); model.route = .paywall }
            } label: {
                settingsRow(model.state.entitlement.purchasedPro ? L.t("pay.owned") : L.t("settings.unlock"),
                            icon: "checkmark.shield", tone: .mint)
            }.buttonStyle(.plain).testID("settings.unlock")
            Text(L.t("settings.privacy")).font(.footnote).foregroundStyle(Theme.muted)
            Link(destination: Launch.placeholderURL) {
                settingsRow(L.t("settings.support"), icon: "questionmark.circle", tone: .blue)
            }.buttonStyle(.plain)
            ShareLink(item: Launch.storeURL) {
                settingsRow(L.t("settings.tell"), icon: "square.and.arrow.up", tone: .slate)
            }.buttonStyle(.plain)
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: title)
            VStack(alignment: .leading, spacing: 8, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private func settingsRow(_ title: String, icon: String, tone: AccentTone) -> some View {
        IconRow(title: title, icon: icon, tone: tone) { EmptyView() }
    }

    private func export(pdf: Bool) {
        guard model.hasPro else { model.route = nil; Task { try? await Task.sleep(for: .milliseconds(500)); model.route = .paywall }; return }
        let stamp = Day.today.iso
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Warranty-\(stamp).\(pdf ? "pdf" : "csv")")
        do {
            if pdf { try PDFExport.data(model.state, today: model.today).write(to: url, options: .atomic) }
            else { try Data(CSVExport.text(model.state).utf8).write(to: url, options: .atomic) }
            exportFile = ExportFile(url: url)
        } catch { model.notice = WarrantyError.save.message }
    }
}

struct ExportFile: Identifiable { let url: URL; var id: String { url.path } }

enum PDFExport {
    static func data(_ state: AppState, today: Day) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            for item in state.sorted(on: today) {
                ctx.beginPage()
                var y: CGFloat = 48
                func line(_ s: String, _ size: CGFloat, _ weight: UIFont.Weight = .regular, color: UIColor = .black) {
                    let attr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
                    let r = (s as NSString).boundingRect(with: CGSize(width: 516, height: 200), options: .usesLineFragmentOrigin, attributes: attr, context: nil)
                    (s as NSString).draw(with: CGRect(x: 48, y: y, width: 516, height: r.height), options: .usesLineFragmentOrigin, attributes: attr, context: nil)
                    y += r.height + 6
                }
                line(item.displayName, 22, .bold)
                line(state.category(item.category).title, 12, color: .darkGray)
                if let p = item.purchased, !item.isDocument { line(L.t("field.purchased") + ": " + p.iso, 12) }
                if !item.store.isEmpty { line(L.t("field.store") + ": " + item.store, 12) }
                if !item.price.isEmpty { line(L.t("field.price") + ": " + item.price, 12) }
                for d in item.deadlines { line(L.t("kind." + d.kind.rawValue) + ": " + d.day.iso, 12, .semibold) }
                for (k, v) in [("field.model", item.model), ("field.serial", item.serial), ("field.phone", item.phone), ("field.notes", item.notes)] where !v.isEmpty {
                    line(L.t(k) + ": " + v, 12)
                }
                y += 10
                for name in item.photos.prefix(2) {
                    guard let img = UIImage(contentsOfFile: Store.imageURL(name).path), y < 700 else { continue }
                    let maxH = 744 - y
                    let s = min(516 / img.size.width, maxH / img.size.height, 1)
                    let size = CGSize(width: img.size.width * s, height: img.size.height * s)
                    img.draw(in: CGRect(x: 48, y: y, width: size.width, height: size.height))
                    y += size.height + 10
                }
            }
        }
    }
}

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: StoreModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    HeroCard {
                        VStack(alignment: .leading, spacing: 10) {
                            IconGlyph(icon: "checkmark.shield.fill", tone: .mint, size: 48, circular: true)
                            Text(L.t("pay.title")).font(.largeTitle.bold()).foregroundStyle(Theme.accent)
                            Text(L.t("pay.once")).font(.subheadline).foregroundStyle(Theme.muted)
                            StatusPill(
                                title: model.state.entitlement.purchasedPro ? L.t("pay.owned") : model.hasPro
                                    ? L.f("pay.until", Day(model.state.entitlement.trialEnd).label) : L.f("pay.expired", Launch.freeLimit),
                                tone: model.hasPro ? .mint : .slate
                            ).testID("paywall.status")
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        feature("pay.unlimited", icon: "tray.full", tone: .mint)
                        feature("pay.export", icon: "doc.richtext", tone: .blue)
                        feature("pay.widget", icon: "rectangle.grid.1x2", tone: .amber)
                        feature("pay.keep", icon: "lock", tone: .slate)
                    }.card()
                    VStack(spacing: 8) {
                        if !model.state.entitlement.purchasedPro {
                            if let product = store.pro {
                                PrimaryButton(title: L.f("pay.buy", product.displayPrice), id: "paywall.buy", icon: "lock.open") {
                                    Task { await store.buy(product, update: model.applyPurchase) }
                                }.disabled(store.busy)
                            } else if Launch.testing {
                                PrimaryButton(title: L.f("pay.buy", "US$3.99"), id: "paywall.buy", icon: "lock.open") {}.disabled(true)
                            } else {
                                SecondaryButton(title: L.t("pay.load"), id: "paywall.load", icon: "arrow.clockwise") { Task { await store.load() } }
                            }
                            if model.state.entitlement.trialClaimedAt == nil, model.hasPro {
                                SecondaryButton(title: L.t("pay.claim"), id: "paywall.claim", icon: "calendar.badge.plus") {
                                    if let trial = store.trial { Task { await store.buy(trial, update: model.applyPurchase) } }
                                    else { Task { await store.load() } }
                                }.disabled(store.busy)
                            }
                        }
                        SecondaryButton(title: L.t("pay.restore"), id: "paywall.restore", icon: "arrow.counterclockwise") {
                            Task { await store.restore(model.applyPurchase) }
                        }.disabled(store.busy)
                        if store.busy { ProgressView() }
                        if let n = store.notice { Text(n).font(.footnote).foregroundStyle(Theme.muted).testID("paywall.notice") }
                    }
                }.padding(Theme.pageInset)
            }
            .tint(Theme.accent).background(Theme.background.ignoresSafeArea())
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { model.route = nil } label: {
                        Label(L.t("action.close"), systemImage: "xmark").labelStyle(.iconOnly)
                    }.testID("paywall.close")
                }
            }
            .task { await store.load() }
        }
    }

    private func feature(_ key: String, icon: String, tone: AccentTone) -> some View {
        IconRow(title: L.t(key), icon: icon, tone: tone) { EmptyView() }
    }
}
