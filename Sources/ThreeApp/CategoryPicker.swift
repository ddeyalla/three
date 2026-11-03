import SwiftUI
import ThreeCore

struct CategoryPicker: View {
    let categories: [ThreeCore.Category]
    let selection: ThreeCore.Category?
    var onSelect: (ThreeCore.Category) -> Void
    @State private var presented = false
    @State private var hovering = false

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: Space.sm) {
                Circle().fill(selection?.color ?? Theme.idle)
                    .frame(width: 7, height: 7)
                Text(selection?.name ?? "Category")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .font(Typo.meta)
            .foregroundStyle(.primary)
            .padding(.horizontal, Space.sm)
            .frame(minHeight: 26)
            .background(hovering || presented ? Theme.rowFill : .clear, in: .capsule)
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.25)))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(categories.isEmpty)
        .help("Change category")
        .accessibilityLabel("Category")
        .accessibilityValue(selection?.name ?? "No categories")
        .popover(isPresented: $presented, attachmentAnchor: .point(.bottomTrailing), arrowEdge: .bottom) {
            CategoryChoices(categories: categories, selectedID: selection?.id) { category in
                onSelect(category)
                presented = false
            }
            .onExitCommand { presented = false }
        }
    }
}

private struct CategoryChoices: View {
    let categories: [ThreeCore.Category]
    let selectedID: String?
    var onSelect: (ThreeCore.Category) -> Void
    @FocusState private var focusedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Category")
                .font(Typo.meta)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Space.sm)
                .padding(.top, Space.xs)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Space.hairline) {
                        ForEach(categories) { category in
                            Button { onSelect(category) } label: {
                                CategoryChoiceLabel(category: category, selected: category.id == selectedID)
                            }
                            .buttonStyle(CategoryChoiceStyle(focused: focusedID == category.id))
                            .focusable()
                            .focusEffectDisabled()
                            .focused($focusedID, equals: category.id)
                            .accessibilityLabel(category.name)
                            .accessibilityAddTraits(category.id == selectedID ? .isSelected : [])
                            .id(category.id)
                        }
                    }
                }
                .frame(height: max(0, CGFloat(min(categories.count, 7)) * 34 - Space.hairline))
                .onChange(of: focusedID) {
                    if let focusedID { proxy.scrollTo(focusedID) }
                }
            }
        }
        .padding(Space.sm)
        .frame(width: 232)
        .onAppear {
            DispatchQueue.main.async { focusedID = selectedID ?? categories.first?.id }
        }
        .onMoveCommand { direction in
            guard !categories.isEmpty, direction == .up || direction == .down else { return }
            let index = categories.firstIndex { $0.id == focusedID } ?? 0
            focusedID = categories[(index + (direction == .down ? 1 : categories.count - 1)) % categories.count].id
        }
        .onKeyPress(.return) {
            guard let category = categories.first(where: { $0.id == focusedID }) else { return .ignored }
            onSelect(category)
            return .handled
        }
    }
}

private struct CategoryChoiceLabel: View {
    let category: ThreeCore.Category
    let selected: Bool

    var body: some View {
        HStack(spacing: Space.md) {
            Circle().fill(category.color).frame(width: 8, height: 8)
            Text(category.name).lineLimit(1)
            Spacer(minLength: Space.sm)
            Image(systemName: "checkmark")
                .opacity(selected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .font(Typo.body)
        .foregroundStyle(.primary)
        .padding(.horizontal, Space.sm)
        .frame(height: 32)
        .contentShape(.rect(cornerRadius: Radius.block))
    }
}

private struct CategoryChoiceStyle: ButtonStyle {
    let focused: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed || hovering || focused ? Theme.rowFill : .clear,
                        in: .rect(cornerRadius: Radius.block))
            .onHover { hovering = $0 }
    }
}
