import SwiftUI
import ThreeCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detail
                .background(Backdrop())
                .inspector(isPresented: $model.showInspector) {
                    TaskInspector()
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.showInspector.toggle() } label: {
                            Label("Details", systemImage: "sidebar.right")
                        }
                        .help("Show task details (⌘I)")
                        .keyboardShortcut("i", modifiers: .command)
                    }
                }
        }
        .toolbar(removing: .title)
        .onAppear { if ProcessInfo.processInfo.environment["THREE_OPEN"] == "settings" { openSettings() } }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1040, minHeight: 700)
    }

    @ViewBuilder private var detail: some View {
        switch model.destination {
        case .today: TodayView()
        case .inbox: InboxView()
        case .upcoming: UpcomingView()
        case .category(let id): CategoryView(categoryId: id)
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding<Destination?>(get: { model.destination }, set: { if let d = $0 { model.destination = d } })) {
            Section {
                Label("Today", systemImage: "sun.max")
                    .badge(model.snapshot.tasks.filter { $0.task.status.isOpen }.count)
                    .tag(Destination.today)
                Label("Inbox", systemImage: "tray")
                    .badge(model.inbox.count)
                    .tag(Destination.inbox)
                Label("Upcoming", systemImage: "calendar")
                    .tag(Destination.upcoming)
            }
            Section("Categories") {
                ForEach(model.liveCategories) { c in
                    Label {
                        Text(c.name)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(c.color)
                            .imageScale(.small)
                    }
                    .tag(Destination.category(c.id))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }
}
