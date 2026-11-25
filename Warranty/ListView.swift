import SwiftUI

struct ListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var open: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    Text(L.t("app.name")).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    if model.state.items.isEmpty {
                        empty
                    } else {
                        deadlineHero
                        VStack(spacing: 12) {
                            chips
                            if model.state.items.count >= Launch.freeLimit { search }
                        }
                        if model.notificationsDenied {
                            Label(L.t("list.notificationsOff"), systemImage: "bell.slash")
                                .font(.footnote).foregroundStyle(Theme.muted).testID("list.notificationsOff")
                        }
                        let visible = model.visible
                        if visible.isEmpty {
                            VStack(spacing: 8) {
                                EmptyIllustration(icon: "magnifyingglass", size: 74)
                                Text(L.t("list.noMatch")).font(.headline).testID("list.noMatch")
                            }
                            .frame(maxWidth: .infinity).card()
                        } else {
                            rows(visible)
                        }
                    }
                    if !model.hasPro && !model.state.entitlement.purchasedPro {
                        Button { model.route = .paywall } label: {
                            IconTile(
                                title: L.f("list.freeLeft", max(0, Launch.freeLimit - model.state.items.count), Launch.freeLimit),
                                icon: "lock.open", tone: .amber
                            )
                        }.buttonStyle(.plain).testID("list.free")
                    } else if !model.state.entitlement.purchasedPro && !Launch.freePeriod {
                        Text(L.f("list.trial", model.trialDaysLeft)).font(.footnote).foregroundStyle(Theme.muted).testID("list.trial")
                    }
                }
                .padding(.horizontal, Theme.pageInset).padding(.top, 8).padding(.bottom, 16)
            }
            VStack(spacing: 8) {
                PrimaryButton(title: L.t("list.capture"), id: "list.capture", icon: "camera.fill") { model.beginCapture() }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    Button { model.addManual() } label: {
                        IconTile(title: L.t("list.manual"), icon: "square.and.pencil", tone: .mint)
                    }.buttonStyle(.plain).testID("list.manual")
                    Button { model.route = .settings } label: {
                        IconTile(title: L.t("settings.title"), icon: "gearshape.fill", tone: .blue)
                    }.buttonStyle(.plain).testID("list.settings")
                }
            }
            .padding(.horizontal, Theme.pageInset).padding(.bottom, 6).padding(.top, 8)
            .background(Theme.background)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var deadlineHero: some View {
        let today = model.today
        let soon = model.state.soon(on: today)
        let upcoming = soon.first ?? model.state.sorted(on: today).first { item in
            guard let deadline = item.next(after: today) else { return false }
            return deadline.day >= today
        }

        return HeroCard {
            if let item = upcoming, let deadline = item.next(after: today) {
                let days = today.days(until: deadline.day)
                let tone = AccentTone.deadline(days: days)
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack { SectionHeading(title: L.t("list.nextDeadline")); Spacer(minLength: 6); soonBadge(soon) }
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeading(title: L.t("list.nextDeadline"))
                            soonBadge(soon)
                        }
                    }
                    Button { open(item.id) } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L.f(days == 1 ? "list.heroDay" : "left.days", days))
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                                    .foregroundStyle(Theme.accent)
                                Text(item.displayName).font(.title3.bold()).foregroundStyle(Theme.ink)
                                Text(L.t("detail.until." + deadline.kind.rawValue) + " · " + deadline.day.label)
                                    .font(.footnote).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            ReceiptIllustration(tone: tone, size: typeSize.isAccessibilitySize ? 48 : 76)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let progress = deadlineProgress(item: item, deadline: deadline, today: today) {
                        ProgressCapsule(value: progress, tone: tone)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeading(title: L.t("list.nextDeadline"))
                        Text(L.t("list.noUpcoming")).font(.title3.bold())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ReceiptIllustration(tone: .blue, size: 64)
                }
            }
        }
    }

    @ViewBuilder private func soonBadge(_ soon: [Item]) -> some View {
        if let first = soon.first, let day = first.next(after: model.today)?.day {
            StatusPill(title: L.f("list.soonCount", soon.count), tone: .amber, icon: "clock")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L.f("list.soon", soon.count, first.displayName, day.label))
                .testID("list.soon")
        }
    }

    private func deadlineProgress(item: Item, deadline: Deadline, today: Day) -> Double? {
        let start: Day?
        switch deadline.kind {
        case .returnWindow, .warranty: start = item.purchased
        case .extended: start = item.warrantyEnd ?? item.purchased
        case .document: start = nil
        }
        guard let start else { return nil }
        let duration = start.days(until: deadline.day)
        guard duration > 0 else { return nil }
        return Double(start.days(until: today)) / Double(duration)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField(L.t("list.search"), text: $model.query).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).testID("list.search")
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(L.t("action.clear"))
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line).allowsHitTesting(false) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(L.f("list.all", model.state.items.count), icon: "square.grid.2x2.fill", tone: .slate,
                     on: model.filter == nil, id: "chip.all") { model.filter = nil }
                ForEach(model.state.categories.filter { c in model.state.items.contains { $0.category == c.id } }) { c in
                    let mark = CategoryMark(c.id)
                    chip(c.title, icon: mark.icon, tone: mark.tone, on: model.filter == c.id, id: "chip." + c.id) { model.filter = c.id }
                }
            }
        }
    }

    private func chip(_ title: String, icon: String, tone: AccentTone, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(on ? .white : tone.ink)
                    .accessibilityHidden(true)
                Text(title).font(.caption2.weight(.semibold))
                    .lineLimit(2, reservesSpace: true).minimumScaleFactor(0.75)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(on ? .white : Theme.ink)
            .padding(.horizontal, 4).padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(on ? Theme.accent : tone.soft, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .containerRelativeFrame(.horizontal, count: typeSize.isAccessibilitySize ? 3 : 5, spacing: 6)
        .accessibilityAddTraits(on ? .isSelected : [])
        .testID(id)
    }

    private func rows(_ list: [Item]) -> some View {
        let split = list.firstIndex { !$0.active(on: model.today) } ?? list.endIndex
        return VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            if split > list.startIndex {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: L.t("list.receipts"))
                    rowGroup(list, indices: list.startIndex..<split)
                }
            }
            if split < list.endIndex {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: L.t("list.expired")).testID("list.expiredHeader")
                    rowGroup(list, indices: split..<list.endIndex)
                }
            }
        }
    }

    private func rowGroup(_ list: [Item], indices: Range<Int>) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list[indices].enumerated()), id: \.element.id) { offset, item in
                let index = indices.lowerBound + offset
                if offset > 0 { Divider().overlay(Theme.line).padding(.leading, 62) }
                Button { open(item.id) } label: {
                    ItemRow(item: item, today: model.today, category: model.state.category(item.category).title)
                }
                .buttonStyle(.plain).testID("row.\(index)")
            }
        }
        .cardSurface()
    }

    private var empty: some View {
        VStack(spacing: 10) {
            EmptyIllustration()
            Text(L.t("list.emptyTitle")).font(.title2.bold())
            Text(L.t("list.emptyBody")).font(.subheadline).foregroundStyle(Theme.muted)
            SecondaryButton(title: L.t("list.import"), id: "list.import", icon: "tray.and.arrow.down") {
                model.route = .importCode
            }
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .contain).testID("list.empty")
    }
}

struct ItemRow: View {
    let item: Item
    let today: Day
    let category: String

    var body: some View {
        let mark = CategoryMark(item.category)
        IconRow(title: item.displayName, subtitle: subtitle, icon: mark.icon, tone: mark.tone) {
            if let deadline = item.next(after: today) {
                let tone = AccentTone.deadline(days: today.days(until: deadline.day))
                VStack(alignment: .trailing, spacing: 3) {
                    StatusPill(title: Remaining.text(from: today, to: deadline.day), tone: tone)
                    Text(L.t("kind." + deadline.kind.rawValue)).font(.caption2).foregroundStyle(Theme.muted)
                }
                .multilineTextAlignment(.trailing)
            } else {
                StatusPill(title: L.t("list.noDeadline"), tone: .slate)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if item.isDocument { return category }
        var parts = [category]
        if let p = item.purchased { parts.append(p.label) }
        if !item.store.isEmpty, item.store != item.displayName { parts.append(item.store) }
        return parts.joined(separator: " · ")
    }
}

struct Thumb: View {
    let name: String?
    var body: some View {
        Group {
            if let name, let img = UIImage(contentsOfFile: Store.imageURL(name).path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.accentSoft
                    Image(systemName: "receipt").font(.title).foregroundStyle(Theme.accent)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line).allowsHitTesting(false) }
    }
}
