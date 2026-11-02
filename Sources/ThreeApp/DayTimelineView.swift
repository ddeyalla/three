import SwiftUI
import ThreeCore

struct DayTimelineView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TIMELINE")
                .font(Theme.stat())
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 28)
                .padding(.top, 44)
                .padding(.bottom, 14)
            ScrollViewReader { proxy in
                ScrollView {
                    DayTimelineGrid()
                }
                .scrollIndicators(.never)
                .onAppear { proxy.scrollTo("now", anchor: .center) }
            }
        }
    }
}

/// Today on an hour grid: planned blocks outlined, actual sessions filled, a red line for now.
struct DayTimelineGrid: View {
    @Environment(AppModel.self) private var model
    private let hourHeight: CGFloat = 64
    private let gutter: CGFloat = 64

    private var hours: ClosedRange<Int> {
        let cal = Calendar.current
        let sessionHours = model.snapshot.sessions.map { cal.component(.hour, from: $0.startedAt) }
        let lo = min(7, sessionHours.min() ?? 7, cal.component(.hour, from: model.now))
        return lo...23
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            grid
            blocks
            nowLine
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .padding(.trailing, 28)
    }

    private var height: CGFloat { CGFloat(hours.count) * hourHeight + 20 }

    private var dayStart: Date {
        Calendar.current.date(bySettingHour: hours.lowerBound, minute: 0, second: 0, of: model.snapshot.day.startDate)!
    }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3600) * hourHeight + 10
    }

    private var grid: some View {
        ForEach(Array(hours), id: \.self) { h in
            let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: model.snapshot.day.startDate)!
            HStack(spacing: 10) {
                Text(date.formatted(.dateTime.hour()))
                    .font(Theme.stat(10))
                    .foregroundStyle(Theme.tertiary)
                    .frame(width: gutter - 10, alignment: .trailing)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            .offset(y: y(date) - 6)
        }
    }

    private var blocks: some View {
        let byTask = Dictionary(uniqueKeysWithValues: model.snapshot.tasks.map { ($0.id, $0) })
        return ZStack(alignment: .topLeading) {
            ForEach(model.snapshot.tasks.filter { $0.task.scheduledStart != nil }) { row in
                let start = row.task.scheduledStart!
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(row.category.color.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(height: CGFloat(row.task.blockMinutes) / 60 * hourHeight)
                    .padding(.leading, gutter + 4)
                    .offset(y: y(start))
            }
            if let running = model.running, !running.isPaused, running.plannedEnd > model.now {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(model.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(height: CGFloat(running.plannedEnd.timeIntervalSince(running.startedAt) / 3600) * hourHeight)
                    .padding(.leading, gutter + 4)
                    .offset(y: y(running.startedAt))
            }
            ForEach(model.snapshot.sessions) { s in
                let row = s.taskId.flatMap { byTask[$0] } ?? (s.taskId == model.runningTask?.id ? model.runningTask : nil)
                let end = s.endedAt ?? model.now
                let height = max(4, CGFloat(end.timeIntervalSince(s.startedAt) / 3600) * hourHeight)
                SessionBlock(session: s, row: row, height: height)
                    .padding(.leading, gutter + 4)
                    .offset(y: y(s.startedAt))
            }
        }
    }

    private var nowLine: some View {
        HStack(spacing: 0) {
            Text(Format.time(model.now))
                .font(Theme.stat(10))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.now, in: .rect(cornerRadius: 4))
                .frame(width: gutter, alignment: .trailing)
            Rectangle().fill(Theme.now).frame(height: 1.5)
        }
        .offset(y: y(model.now) - 8)
        .id("now")
    }
}

private struct SessionBlock: View {
    let session: Session
    let row: TaskRow?
    let height: CGFloat

    var body: some View {
        let color = session.kind == .break ? Color.white.opacity(0.12) : (row?.category.color ?? Theme.idle)
        RoundedRectangle(cornerRadius: 8)
            .fill(session.kind == .break ? AnyShapeStyle(color) : AnyShapeStyle(color.gradient.opacity(0.85)))
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if height >= 22 {
                    HStack(spacing: 6) {
                        Text(session.kind == .break ? "Break" : (row?.task.title ?? "Focus"))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Format.duration(session.elapsed(at: Date())))
                            .font(Theme.stat(10))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(session.kind == .break ? 0.6 : 0.95))
                    .padding(.horizontal, 10)
                    .padding(.top, 5)
                }
            }
    }
}
