import SwiftUI

@main
struct WarrantyApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .environmentObject(model)
                .onAppear { model.start() }
                .onChange(of: phase) { _, p in
                    if p == .active { model.pickUpInbox(); Task { await model.reschedule() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ListView(open: { path.append($0) })
                .navigationDestination(for: UUID.self) { DetailView(id: $0) }
        }
        .tint(Theme.accent)
        .foregroundStyle(Theme.ink)
        .fullScreenCover(isPresented: Binding(get: { model.route == .capture }, set: { if !$0, model.route == .capture { model.route = nil } })) {
            CaptureView().environmentObject(model)
        }
        .sheet(item: Binding(get: { model.route == .capture ? nil : model.route }, set: { if $0 == nil { model.route = nil } })) { route in
            sheet(route).environmentObject(model)
        }
        .overlay(alignment: .top) {
            if let n = model.notice {
                Label(n, systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .padding(10).cardSurface().padding(.top, 6).padding(.horizontal, 16)
                    .testID("app.notice")
                    .task(id: n) { try? await Task.sleep(for: .seconds(3)); if model.notice == n { model.notice = nil } }
            }
        }
        .onOpenURL { url in
            if let id = url.queryItem("item").flatMap(UUID.init(uuidString:)), model.item(id) != nil { path = [id] }
        }
    }

    @ViewBuilder private func sheet(_ route: Route) -> some View {
        switch route {
        case .editor(let id, let fresh): EditorView(id: id, fresh: fresh)
        case .paywall: PaywallView(store: model.purchases)
        case .settings: SettingsView()
        case .share(let id): ShareCardView(id: id)
        case .importCode: ImportView()
        case .milestone(let m): MilestoneView(kind: m)
        case .capture: EmptyView()
        }
    }
}

extension URL {
    func queryItem(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
