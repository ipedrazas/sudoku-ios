import SudokuKit
import SwiftUI
import WidgetKit

/// The Lock Screen widgets.
///
/// Separate from the Home Screen widget rather than more families on it, because
/// they answer a different question. A Home Screen widget is looked at; a Lock
/// Screen widget is *glanced past* on the way to something else, and the only
/// thing worth putting in that half-second is whether today is still owed.
///
/// Accessory widgets are drawn in a single tint with no colour of their own, so
/// nothing here uses colour to mean anything — which is also the Phase 9 rule
/// (P9-5) arriving early.
struct StreakWidget: Widget {
    static let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Whether today's puzzle is still waiting.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyEntry

    var body: some View {
        content
            .widgetURL(DeepLink.daily.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: CircularStreak(status: entry.status)
        case .accessoryInline: InlineStreak(entry: entry)
        default: RectangularStatus(entry: entry)
        }
    }
}

// MARK: - Circular

/// The streak as a gauge, because a bare number in a circle wastes the circle.
///
/// The ring runs to the best streak, so the gauge is "how close is this to the
/// best you have done" — a scale that means something, rather than an arbitrary
/// 30 that everyone hits and nobody exceeds. Before there is a best to measure
/// against, it falls back to a week.
private struct CircularStreak: View {
    let status: DailyStatus

    private var target: Double {
        Double(max(status.bestStreak, 7))
    }

    var body: some View {
        Gauge(value: min(Double(status.streak), target), in: 0...target) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text(status.streak, format: .number)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("Solve streak")
        .accessibilityValue("^[\(status.streak) day](inflect: true)")
        // The completion mark is a glyph rather than a colour, so it survives
        // the tinted, colourless rendering the Lock Screen applies.
        .overlay(alignment: .bottom) {
            if status.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Rectangular

/// "Daily ready" or "Daily done ✓" — the widget the plan asks for by name, and
/// the one that does the actual work of protecting a streak.
private struct RectangularStatus: View {
    let entry: DailyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text("Daily Sudoku")
                    .font(.headline)
            } icon: {
                Image(systemName: entry.status.symbol)
            }
            .widgetAccentable()

            Text(entry.lockScreenLine)
                .font(.caption)
            // A second line only when it adds a fact, not to fill the space.
            if let detail = entry.status.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inline

/// One line, next to the date. The tightest budget on the platform, so it says
/// exactly one thing.
private struct InlineStreak: View {
    let entry: DailyEntry

    var body: some View {
        Label(entry.inlineLine, systemImage: entry.status.symbol)
    }
}

// MARK: - Words

extension DailyEntry {

    /// Deliberately not `headline`. The Home Screen can afford encouragement;
    /// the Lock Screen gets the fact.
    var lockScreenLine: String {
        guard hasData else { return "Open the app to begin" }
        switch status.standing {
        case .ready: return status.streak > 0 ? "Ready — \(status.streak) day streak at stake" : "Ready to play"
        case .inProgress: return "In progress"
        case .completed: return "Done today"
        }
    }

    var inlineLine: String {
        switch status.standing {
        case .ready: status.streak > 0 ? "Daily ready · \(status.streak)" : "Daily ready"
        case .inProgress: "Daily in progress"
        case .completed: status.streak > 0 ? "Daily done · \(status.streak)" : "Daily done"
        }
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    StreakWidget()
} timeline: {
    DailyEntry(date: .now, status: .preview)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    StreakWidget()
} timeline: {
    DailyEntry(date: .now, status: .preview)
    DailyEntry(date: .now, status: .empty(), hasData: false)
}

#Preview("Inline", as: .accessoryInline) {
    StreakWidget()
} timeline: {
    DailyEntry(date: .now, status: .preview)
}
