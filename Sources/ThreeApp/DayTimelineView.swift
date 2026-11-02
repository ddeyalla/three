import SwiftUI
import ThreeCore

struct DayTimelineView: View {
    @Environment(AppModel.self) private var model
    @State private var position = ScrollPosition()
    @State private var viewport: CGFloat = 0

    var body: some View {
        ScrollView {
            DayTimelineGrid()
                .padding(.vertical, 24)
        }
        .scrollIndicators(.never)
        .scrollPosition($position)
        // Put now 40% down once the viewport has a real size, and again each new day.
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.containerSize.height }) { _, height in
            let first = viewport == 0
            viewport = height
            if first, height > 0 { scrollToNow() }
        }
        .onChange(of: model.snapshot.day) { scrollToNow() }
    }

    private func scrollToNow() {
        let y = DayTimelineGrid.offset(of: model.now, day: model.snapshot) + 24
        position.scrollTo(y: max(0, y - viewport * 0.4))
    }
}

/// Today on an hour grid: planned blocks outlined, actual sessions filled, a red line for now.
struct DayTimelineGrid: View {
    @Environment(AppModel.self) private var model
    private let hourHeight = DayTimelineGrid.hourHeight
    private let gutter: CGFloat = 60

    private static let hourHeight: CGFloat = 60

    private var hours: ClosedRange<Int> { Self.hours(model.snapshot, now: model.now) }

    private static func hours(_ snap: DaySnapshot, now: Date) -> ClosedRange<Int> {
        let cal = Calendar.current
        let sessionHours = snap.sessions.map { cal.component(.hour, from: $0.startedAt) }
        return min(7, sessionHours.min() ?? 7, cal.component(.hour, from: now))...23
    }

    /// Where `date` sits in the grid, for scrolling to it.
    static func offset(of date: Date, day snap: DaySnapshot) -> CGFloat {
        let start = Calendar.current.date(bySettingHour: hours(snap, now: date).lowerBound, minute: 0, second: 0, of: snap.day.startDate)!
        return CGFloat(date.timeIntervalSince(start) / 3600) * hourHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            grid
            blocks
            nowLine
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .padding(.trailing, 24)
    }

    private var height: CGFloat { CGFloat(hours.count) * hourHeight }

    private var dayStart: Date {
        Calendar.current.date(bySettingHour: hours.lowerBound, minute: 0, second: 0, of: model.snapshot.day.startDate)!
    }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3600) * hourHeight
    }

    private var grid: some View {
        let nowY = y(model.now)
        return ForEach(Array(hours), id: \.self) { h in
            let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: model.snapshot.day.startDate)!
            HStack(spacing: 8) {
                Text(date.formatted(.dateTime.hour()))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: gutter - 8, alignment: .trailing)
                    .opacity(abs(y(date) - nowY) < 12 ? 0 : 1)
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            }
            .offset(y: y(date) - 7)
        }
    }

    private var blocks: some View {
        let byTask = Dictionary(uniqueKeysWithValues: model.snapshot.tasks.map { ($0.id, $0) })
        return ZStack(alignment: .topLeading) {
            ForEach(model.snapshot.tasks.filter { $0.task.scheduledStart != nil }) { row in
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(row.category.color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: CGFloat(row.task.blockMinutes) / 60 * hourHeight)
                    .padding(.leading, gutter + 2)
                    .offset(y: y(row.task.scheduledStart!))
            }
            if let running = model.running, !running.isPaused, running.plannedEnd > model.now {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(model.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: CGFloat(running.plannedEnd.timeIntervalSince(running.startedAt) / 3600) * hourHeight)
                    .padding(.leading, gutter + 2)
                    .offset(y: y(running.startedAt))
            }
            ForEach(model.snapshot.sessions) { s in
                let row = s.taskId.flatMap { byTask[$0] }
                let end = s.endedAt ?? model.now
                SessionBlock(session: s, row: row, now: model.now,
                             height: max(3, CGFloat(end.timeIntervalSince(s.startedAt) / 3600) * hourHeight - 1))
                    .padding(.leading, gutter + 2)
                    .offset(y: y(s.startedAt))
            }
        }
    }

    private var nowLine: some View {
        HStack(spacing: 0) {
            Text(Format.time(model.now))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.now)
                .frame(width: gutter - 8, alignment: .trailing)
                .padding(.trailing, 4)
            Circle().fill(Theme.now).frame(width: 7, height: 7)
            Rectangle().fill(Theme.now).frame(height: 1)
        }
        .offset(y: y(model.now) - 7)
        .accessibilityHidden(true)
    }
}

/// Calendar-style: a tinted fill with text in the same hue.
private struct SessionBlock: View {
    let session: Session
    let row: TaskRow?
    let now: Date
    let height: CGFloat

    var body: some View {
        let isBreak = session.kind == .break
        let color = isBreak ? Color.white : (row?.category.color ?? Theme.idle)
        Color.clear
            .frame(height: height)
            .glassEffect(isBreak ? .regular : .regular.tint(color.opacity(0.35)), in: .rect(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                if height >= 20 {
                    HStack(spacing: 6) {
                        Text(isBreak ? "Break" : (row?.task.title ?? "Focus"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isBreak ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Format.duration(session.elapsed(at: now)))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            }
            .accessibilityElement(children: .combine)
    }
}
