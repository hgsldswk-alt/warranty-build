import PhotosUI
import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    let fresh: Bool
    @State private var item = Item()
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var morePhotos: [PhotosPickerItem] = []
    @State private var newCategory = ""
    @State private var addingCategory = false

    var body: some View {
        NavigationStack {
            Form {
                if fresh {
                    Section {
                        HeroCard {
                            Label {
                                Text(L.t("editor.savedBanner")).font(.subheadline.weight(.semibold))
                            } icon: {
                                IconGlyph(icon: "checkmark.circle.fill", tone: .mint)
                            }.testID("editor.saved")
                        }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                }
                if let first = item.photos.first, let img = UIImage(contentsOfFile: Store.imageURL(first).path) {
                    Section {
                        Image(uiImage: img).resizable().scaledToFit()
                            .frame(maxHeight: 200).frame(maxWidth: .infinity)
                            .card()
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                }
                Section {
                    editorField("tag", tone: .mint) {
                        TextField(L.t("field.name"), text: $item.name, prompt: Text(item.store.isEmpty ? L.t("field.namePrompt") : item.store))
                            .testID("editor.name")
                    }
                    Picker(selection: $item.category) {
                        ForEach(model.state.categories) { Text($0.title).tag($0.id) }
                    } label: {
                        let mark = CategoryMark(item.category)
                        editorLabel(L.t("field.category"), icon: mark.icon, tone: mark.tone)
                    }.testID("editor.category")
                    if item.isDocument {
                        DatePicker(selection: dayBinding(\.expires, fallback: model.today.adding(months: 12)), displayedComponents: .date) {
                            editorLabel(L.t("field.expires"), icon: "calendar", tone: .blue)
                        }.testID("editor.expires")
                    } else {
                        editorField("storefront", tone: .slate) {
                            TextField(L.t("field.store"), text: $item.store).testID("editor.store")
                        }
                        DatePicker(selection: dayBinding(\.purchased, fallback: model.today), displayedComponents: .date) {
                            editorLabel(L.t("field.purchased"), icon: "calendar", tone: .blue)
                        }.testID("editor.date")
                        editorField("creditcard", tone: .mint) {
                            TextField(L.t("field.price"), text: $item.price).keyboardType(.decimalPad).testID("editor.price")
                        }
                    }
                }
                if !item.isDocument {
                    Section {
                        Picker(L.t("field.warranty"), selection: Binding(get: { item.warrantyMonths ?? 0 }, set: { item.warrantyMonths = $0 == 0 ? nil : $0 })) {
                            Text(L.t("warranty.none")).tag(0)
                            ForEach([12, 24, 36], id: \.self) { Text(L.f("warranty.years", $0 / 12)).tag($0) }
                            if let m = item.warrantyMonths, ![12, 24, 36].contains(m) { Text(L.f("warranty.months", m)).tag(m) }
                        }.pickerStyle(.segmented).testID("editor.warranty")
                        Stepper(L.f("warranty.months", item.warrantyMonths ?? 0), value: Binding(get: { item.warrantyMonths ?? 0 }, set: { item.warrantyMonths = $0 == 0 ? nil : $0 }), in: 0...240)
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        if let end = item.warrantyEnd {
                            LabeledContent {
                                Text(end.label).monospacedDigit()
                            } label: {
                                editorLabel(L.t("kind.warranty"), icon: "calendar.badge.clock", tone: .amber)
                            }.testID("editor.warrantyEnd")
                        }
                        Toggle(L.t("field.extended"), isOn: Binding(get: { item.extendedEnd != nil }, set: { item.extendedEnd = $0 ? (item.warrantyEnd ?? model.today).adding(months: 24) : nil }))
                            .testID("editor.extendedToggle")
                        if item.extendedEnd != nil {
                            DatePicker(L.t("kind.extended"), selection: dayBinding(\.extendedEnd, fallback: model.today), displayedComponents: .date)
                        }
                        Toggle(L.t("field.return"), isOn: Binding(get: { item.returnDays != nil }, set: { item.returnDays = $0 ? 30 : nil }))
                            .testID("editor.returnToggle")
                        if let days = item.returnDays {
                            Stepper(L.f("field.returnDays", days), value: Binding(get: { days }, set: { item.returnDays = $0 }), in: 1...365)
                        }
                    } header: {
                        SectionHeading(title: L.t("field.warranty")).textCase(nil)
                    }
                }
                Section {
                    editorField("shippingbox", tone: .slate) {
                        TextField(L.t("field.model"), text: $item.model).testID("editor.model")
                    }
                    editorField("barcode", tone: .slate) { TextField(L.t("field.serial"), text: $item.serial) }
                    editorField("phone", tone: .mint) {
                        TextField(L.t("field.phone"), text: $item.phone).keyboardType(.phonePad)
                    }
                    editorField("note.text", tone: .blue) { TextField(L.t("field.notes"), text: $item.notes, axis: .vertical) }
                    PhotosPicker(selection: $morePhotos, maxSelectionCount: 3, matching: .images) {
                        editorLabel(L.f("field.photos", item.photos.count), icon: "photo.badge.plus", tone: .blue)
                    }
                } header: {
                    SectionHeading(title: L.t("field.details")).textCase(nil)
                }
                Section {
                    Button { addingCategory = true } label: {
                        Label(L.t("category.add"), systemImage: "folder.badge.plus")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(L.t("editor.delete"), systemImage: "trash")
                    }.testID("editor.delete")
                }
            }
            .listSectionSpacing(Theme.sectionSpacing)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .tint(Theme.accent)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(fresh ? L.t("editor.newTitle") : L.t("editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("action.done")) { close() }.fontWeight(.bold).testID("editor.done")
                }
            }
            .onAppear {
                guard !loaded, let found = model.item(id) else { return }
                item = found; loaded = true
            }
            .onChange(of: item) { _, new in
                if new.isDocument && new.expires == nil { item.expires = model.today.adding(months: 12); return }
                if loaded, new != model.item(id) { model.update(new) }
            }
            .onChange(of: morePhotos) { _, picks in
                guard !picks.isEmpty else { return }
                Task {
                    for p in picks {
                        if let d = try? await p.loadTransferable(type: Data.self), let img = UIImage(data: d),
                           let jpg = img.jpegForReceipt(), let name = try? Store.writeImage(jpg) { item.photos.append(name) }
                    }
                    morePhotos = []
                }
            }
            .confirmationDialog(L.t("editor.deleteConfirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L.t("editor.delete"), role: .destructive) { model.delete(id); model.route = nil }
            }
            .alert(L.t("category.add"), isPresented: $addingCategory) {
                TextField(L.t("category.name"), text: $newCategory)
                Button(L.t("action.add")) { model.addCategory(newCategory); newCategory = "" }
                Button(L.t("action.cancel"), role: .cancel) { newCategory = "" }
            }
        }
        .interactiveDismissDisabled(false)
        .onDisappear { model.finishedEditing(fresh) }
    }

    private func editorField<Content: View>(_ icon: String, tone: AccentTone, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            IconGlyph(icon: icon, tone: tone)
            content()
        }
    }

    private func editorLabel(_ title: String, icon: String, tone: AccentTone) -> some View {
        editorField(icon, tone: tone) { Text(title) }
    }

    private func close() {
        model.update(item)
        model.route = nil
    }

    private func dayBinding(_ path: WritableKeyPath<Item, Day?>, fallback: Day) -> Binding<Date> {
        Binding(get: { (item[keyPath: path] ?? fallback).localNoon },
                set: { item[keyPath: path] = Day($0) })
    }
}

extension Day {
    var localNoon: Date { local(hour: 12) ?? Date() }
}
