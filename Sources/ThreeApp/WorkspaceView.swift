import AppKit
import SwiftUI

struct WorkspaceView: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkspaceLayout.self) private var layout

    var body: some View {
        WorkspaceSplitView(model: model, layout: layout, order: layout.panes)
            .padding(.horizontal, Space.sm)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.md)
    }
}

private extension WorkspacePane {
    var minimumWidth: CGFloat {
        switch self {
        case .tasks: 320
        case .now: 360
        case .timeline: 300
        }
    }
}

private struct WorkspaceSplitView: NSViewControllerRepresentable {
    let model: AppModel
    let layout: WorkspaceLayout
    let order: [WorkspacePane]

    func makeNSViewController(context: Context) -> PaneSplitController {
        PaneSplitController(model: model, layout: layout, order: order)
    }

    func updateNSViewController(_ controller: PaneSplitController, context: Context) {
        controller.arrange(order)
    }
}

private final class BorderlessSplitView: NSSplitView {
    override func drawDivider(in rect: NSRect) {}
}

private final class PaneSplitController: NSSplitViewController {
    private var items: [WorkspacePane: NSSplitViewItem] = [:]
    private var order: [WorkspacePane] = []

    init(model: AppModel, layout: WorkspaceLayout, order: [WorkspacePane]) {
        super.init(nibName: nil, bundle: nil)
        splitView = BorderlessSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        for pane in WorkspacePane.allCases {
            let content = WorkspacePaneView(pane: pane)
                .environment(model)
                .environment(layout)
                .padding(.horizontal, Space.xs)
            let host = NSHostingController(rootView: content)
            host.sizingOptions = []
            let item = NSSplitViewItem(viewController: host)
            item.minimumThickness = pane.minimumWidth + 2 * Space.xs
            item.canCollapse = false
            items[pane] = item
        }
        arrange(order)
    }

    required init?(coder: NSCoder) { nil }

    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
                            forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        let native = super.splitView(splitView, effectiveRect: proposedEffectiveRect,
                                    forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        let gap = drawnRect.insetBy(dx: -Space.xs, dy: 0)
        return native.isEmpty ? gap : native.union(gap)
    }

    func arrange(_ updated: [WorkspacePane]) {
        guard order != updated else { return }
        let widths = items.mapValues { $0.viewController.view.frame.width }
        // Keep hosting controllers alive so moving a pane cannot discard its SwiftUI draft or scroll state.
        for item in splitViewItems { removeSplitViewItem(item) }
        for pane in updated {
            if let item = items[pane] { addSplitViewItem(item) }
        }
        let hadLayout = !order.isEmpty
        order = updated
        if hadLayout {
            splitView.layoutSubtreeIfNeeded()
            var position: CGFloat = 0
            for (index, pane) in updated.dropLast().enumerated() {
                position += widths[pane] ?? 0
                splitView.setPosition(position, ofDividerAt: index)
                position += splitView.dividerThickness
            }
        }
    }
}

private struct WorkspacePaneView: View {
    @Environment(WorkspaceLayout.self) private var layout
    let pane: WorkspacePane
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(Space.sm)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.thinMaterial, in: .rect(cornerRadius: Radius.panel))
        .clipShape(.rect(cornerRadius: Radius.panel))
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: Radius.panel)
                    .strokeBorder(.primary.opacity(0.5), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: WorkspacePane.self) { items, _ in
            guard items.count == 1, let source = items.first, source != pane else { return false }
            layout.move(source, to: pane)
            return true
        } isTargeted: {
            isDropTarget = $0
        }
        .dropConfiguration { _ in DropConfiguration(operation: .move) }
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(pane.title)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(.rect)
            .draggable(pane) {
                Label(pane.title, systemImage: "line.3.horizontal")
                    .font(Typo.heading)
                    .padding(Space.md)
                    .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
            }
            .dragConfiguration(.init(operationsWithinApp: .init(allowCopy: false, allowMove: true),
                                     operationsOutsideApp: .init(allowCopy: false)))
            .help("Drag \(pane.title) onto another pane to move it. The menu also offers Move Left and Move Right.")
            Menu {
                PaneMoveCommands(layout: layout, pane: pane)
                Divider()
                Button("Reset Pane Order") { layout.reset() }
                    .disabled(layout.panes == WorkspacePane.allCases)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Arrange \(pane.title)")
            .help("Arrange \(pane.title)")
        }
        .font(Typo.heading)
        .padding(.leading, Space.md)
        .padding(.trailing, Space.xs)
    }

    @ViewBuilder private var content: some View {
        switch pane {
        case .tasks: TasksPane()
        case .now: NowPane()
        case .timeline: DayTimelineView()
        }
    }
}

struct PaneMoveCommands: View {
    let layout: WorkspaceLayout
    let pane: WorkspacePane

    var body: some View {
        Button("Move Left", systemImage: "arrow.left") { layout.move(pane, by: -1) }
            .disabled(!layout.canMove(pane, by: -1))
        Button("Move Right", systemImage: "arrow.right") { layout.move(pane, by: 1) }
            .disabled(!layout.canMove(pane, by: 1))
    }
}
