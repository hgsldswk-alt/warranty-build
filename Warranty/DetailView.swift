import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID
    @State private var askSaved = false
    @State private var savedText = ""
    @State private var zoom: String?

    var body: some View {
        Group {
            if let item = model.item(id) {
                content(item)
            } else {
                VStack(spacing: 10) {
                    EmptyIllustration(icon: "doc")
                    Text(L.t("error.gone")).font(.headline).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).card().padding(Theme.pageInset)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackground(Theme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.route = .editor(id, fresh: false) } label: {
                    Label(L.t("action.edit"), systemImage: "square.and.pencil")
                }.testID("detail.edit")
            }
        }
        .alert(L.t("fixed.title"), isPresented: $askSaved) {
            TextField(L.t("fixed.placeholder"), text: $savedText).keyboardType(.decimalPad)
            Button(L.t("fixed.share")) {
                model.markFixed(id, saved: Double(savedText.replacingOccurrences(of: ",", with: ".")) ?? 0)
                savedText = ""
            }
            Button(L.t("action.cancel"), role: .cancel) { savedText = "" }
        } message: { Text(L.t("fixed.message")) }
        .fullScreenCover(item: Binding(get: { zoom.map(ZoomBox.init) }, set: { zoom = $0?.name })) { box in
            ZoomView(name: box.name) { zoom = nil }
        }
    }

    private func content(_ item: Item) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                Text(item.displayName).font(.largeTitle.bold()).testID("detail.name")
                if !item.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(item.photos, id: \.self) { p in
                                Button { zoom = p } label: {
                                    Thumb(name: p)
                                        .frame(width: item.photos.count == 1 ? 300 : 160, height: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .accessibilityLabel(L.t("detail.openPhoto"))
                                }
                                    .buttonStyle(.plain).testID("detail.photo")
                            }
                        }
                    }
                }
                if let d = item.next(after: model.today) {
                    let tone = AccentTone.deadline(days: model.today.days(until: d.day))
                    HeroCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeading(title: L.t("detail.until." + d.kind.rawValue))
                            Text(d.day.label).font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accent).testID("detail.until")
                            StatusPill(title: Remaining.text(from: model.today, to: d.day), tone: tone, icon: "calendar")
                            if let p = item.progress(on: model.today) {
                                ProgressCapsule(value: p, tone: tone)
                            }
                        }
                    }
                }
                let list = rows(item)
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: L.t("field.details"))
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.offset) { index, row in
                            IconRow(title: row.title, icon: row.icon, tone: .slate) {
                                if row.title == L.t("field.phone"), let url = URL(string: "tel:" + row.value.filter { $0.isNumber || $0 == "+" }) {
                                    Link(row.value, destination: url).foregroundStyle(Theme.accent)
                                        .multilineTextAlignment(.trailing)
                                        .frame(minHeight: 44)
                                } else {
                                    Text(row.value).multilineTextAlignment(.trailing).textSelection(.enabled)
                                }
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            if index < list.count - 1 {
                                Divider().overlay(Theme.line).padding(.leading, 62)
                            }
                        }
                    }
                    .cardSurface()
                }
                VStack(spacing: 8) {
                    if !item.isDocument {
                        PrimaryButton(
                            title: item.saved == nil ? L.t("detail.fixed") : L.t("detail.shareAgain"),
                            id: "detail.fixed", icon: item.saved == nil ? "wrench.and.screwdriver" : "square.and.arrow.up"
                        ) {
                            if item.saved == nil { askSaved = true } else { model.route = .share(id) }
                        }
                    }
                    ShareLink(item: Transfer.code(for: item) + "\n" + L.t("transfer.hint") + " " + Launch.storeURL.absoluteString) {
                        Label(L.t("detail.sendFamily"), systemImage: "person.2").secondaryControl()
                    }.buttonStyle(.plain).testID("detail.sendFamily")
                }
            }
            .padding(Theme.pageInset)
        }
    }

    private func rows(_ item: Item) -> [(title: String, value: String, icon: String)] {
        var out = [(L.t("field.category"), model.state.category(item.category).title, CategoryMark(item.category).icon)]
        if let p = item.purchased, !item.isDocument { out.append((L.t("field.purchased"), p.label, "calendar")) }
        if !item.store.isEmpty { out.append((L.t("field.store"), item.store, "storefront")) }
        if !item.price.isEmpty { out.append((L.t("field.price"), item.price, "tag")) }
        for d in item.deadlines { out.append((L.t("kind." + d.kind.rawValue), d.day.label, "calendar.badge.clock")) }
        if !item.model.isEmpty { out.append((L.t("field.model"), item.model, "shippingbox")) }
        if !item.serial.isEmpty { out.append((L.t("field.serial"), item.serial, "barcode")) }
        if !item.phone.isEmpty { out.append((L.t("field.phone"), item.phone, "phone")) }
        if !item.notes.isEmpty { out.append((L.t("field.notes"), item.notes, "note.text")) }
        return out
    }
}

private struct ZoomBox: Identifiable { let name: String; var id: String { name } }

private struct ZoomView: View {
    let name: String
    var close: () -> Void
    @State private var scale: CGFloat = 1
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let img = UIImage(contentsOfFile: Store.imageURL(name).path) {
                Image(uiImage: img).resizable().scaledToFit().scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, min(5, $0.magnification)) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button(action: close) { Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white) }
                .padding().accessibilityLabel(L.t("action.close")).testID("zoom.close")
        }
    }
}

struct ShareCardView: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID
    @State private var rendered: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.sectionSpacing) {
                    if let item = model.item(id) {
                        ShareCard(item: item).frame(maxWidth: 360).testID("share.card")
                        if let rendered {
                            ShareLink(item: rendered, preview: SharePreview(L.t("app.name"), image: rendered)) {
                                PrimaryButtonLabel(title: L.t("share.image"), icon: "square.and.arrow.up")
                            }.buttonStyle(.plain).testID("share.send")
                        }
                    }
                }
                .frame(maxWidth: .infinity).padding(Theme.pageInset)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("action.done")) { model.route = nil }.testID("share.done") } }
            .task {
                guard let item = model.item(id) else { return }
                let r = ImageRenderer(content: ShareCard(item: item).frame(width: 360))
                r.scale = 3
                if let ui = r.uiImage { rendered = Image(uiImage: ui) }
            }
        }
    }
}

struct ShareCard: View {
    let item: Item
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(L.f("share.fixedWhat", item.displayName)).font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ReceiptIllustration()
            }
            Text(L.f("share.saved", money(item.saved ?? 0)))
                .font(.system(size: 46, weight: .bold, design: .rounded)).foregroundStyle(Theme.due)
                .monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(L.t("share.reminded")).font(.subheadline).opacity(0.85)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("app.name")).font(.footnote.weight(.semibold))
                    Text(Launch.hashtag).font(.footnote)
                }
                Spacer()
                if let qr = QR.image(Launch.storeURL.absoluteString) {
                    Image(uiImage: qr).interpolation(.none).resizable().frame(width: 72, height: 72)
                        .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(.top, 18)
        }
        .foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(LinearGradient(colors: [Theme.accent, Theme.shareBack], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(
                    LinearGradient(colors: [Theme.blue, Theme.accent, Theme.mint], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2
                )
                .allowsHitTesting(false)
        }
    }

    private func money(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(v.rounded() == v ? 0 : 2)))
    }
}

struct MilestoneView: View {
    @EnvironmentObject private var model: AppModel
    let kind: String
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                HeroCard {
                    VStack(spacing: 6) {
                        ReceiptIllustration()
                        Text(L.t("milestone." + kind)).font(.title2.bold()).testID("milestone.title")
                        Text(L.t("milestone.body")).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                VStack(spacing: 8) {
                    ShareLink(item: L.t("milestone.shareText") + " " + Launch.hashtag + " " + Launch.storeURL.absoluteString) {
                        PrimaryButtonLabel(title: L.t("milestone.share"), icon: "square.and.arrow.up")
                    }.buttonStyle(.plain).testID("milestone.share")
                    SecondaryButton(title: L.t("action.done"), id: "milestone.done", icon: "checkmark") { model.route = nil }
                }
            }
            .padding(Theme.pageInset)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

struct ImportView: View {
    @EnvironmentObject private var model: AppModel
    @State private var text = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    HeroCard {
                        HStack(spacing: 12) {
                            IconGlyph(icon: "tray.and.arrow.down", tone: .blue)
                            Text(L.t("import.body")).font(.subheadline)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(L.t("import.placeholder"), text: $text, axis: .vertical).lineLimit(3...6)
                            .card().testID("import.field")
                        PasteButton(payloadType: String.self) { strings in
                            guard let s = strings.first else { return }
                            Task { @MainActor in text = s; if model.importCode(s) { model.route = nil } }
                        }.tint(Theme.accent).testID("import.paste")
                        if let n = model.notice { Text(n).font(.footnote).foregroundStyle(Theme.dueText).testID("import.error") }
                    }
                }
                .padding(Theme.pageInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(title: L.t("import.go"), id: "import.go", icon: "plus") {
                    if model.importCode(text) { model.route = nil }
                }
                .padding(.horizontal, Theme.pageInset).padding(.vertical, 8)
                .background(Theme.background)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationTitle(L.t("import.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("action.cancel")) { model.route = nil } } }
        }
    }
}
