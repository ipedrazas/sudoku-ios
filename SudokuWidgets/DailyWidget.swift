import SudokuKit
import SwiftUI
import WidgetKit

/// The Home Screen widget: where today's puzzle stands.
///
/// One widget across three families rather than three widgets, because they say
/// the same thing at three sizes — and a gallery listing the same idea three
/// times makes the player choose between them before they know what any of them
/// look like.
struct DailyWidget: Widget {
    static let kind = "DailyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            DailyWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily puzzle")
        .description("Today's Sudoku, and how your streak is doing.")
        // `systemLarge` earns its place on iPad, where the mini board is legible
        // and a Home Screen has room for it. It is offered on iPhone too — the
        // families a widget supports are not per-device, and a large widget on a
        // phone is a choice its owner is allowed to make.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Picks the layout for the family it finds itself in.
struct DailyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyEntry

    var body: some View {
        content
            // Every family, one destination. §6.4 of the plan asks for deep
            // links from every widget family, and the way to get that is to put
            // the URL on the container rather than remembering it per layout.
            .widgetURL(DeepLink.daily.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall: SmallDaily(entry: entry)
        case .systemLarge: LargeDaily(entry: entry)
        default: MediumDaily(entry: entry)
        }
    }
}

// MARK: - Small

/// A glance: the state of today, the streak, and a hint of the board.
private struct SmallDaily: View {
    let entry: DailyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: entry.status.symbol)
                    .foregroundStyle(.tint)
                Text("Daily")
                    .font(.caption.weight(.semibold))
                Spacer()
                StreakBadge(streak: entry.status.streak)
            }

            if let board = entry.status.displayBoard, let givens = entry.status.givens {
                // No digits at this size: a 6-point numeral is a smudge, but the
                // pattern of a part-filled grid still reads as one.
                MiniBoard(givens: givens, board: board, showsDigits: false)
            } else {
                Spacer()
            }

            Text(entry.headline)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Medium

/// Room for words: what today is, and what it is worth.
private struct MediumDaily: View {
    let entry: DailyEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Daily puzzle", systemImage: entry.status.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)

                Text(entry.headline)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let detail = entry.status.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                StreakLine(status: entry.status)
            }

            if let board = entry.status.displayBoard, let givens = entry.status.givens {
                MiniBoard(givens: givens, board: board, showsDigits: false)
                    .frame(maxWidth: 110)
            }
        }
    }
}

// MARK: - Large

/// The board itself, at a size where the digits mean something. This is the one
/// the iPad Home Screen is for (§8 of the plan, D1).
private struct LargeDaily: View {
    let entry: DailyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Daily puzzle", systemImage: entry.status.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                StreakBadge(streak: entry.status.streak)
            }

            if let board = entry.status.displayBoard, let givens = entry.status.givens {
                MiniBoard(givens: givens, board: board)
                    .frame(maxWidth: .infinity)
            } else {
                // The state before the app has ever opened today's puzzle. An
                // empty 9×9 would be a lie about what is waiting.
                ContentUnavailableView {
                    Label("Today's puzzle is ready", systemImage: "square.grid.3x3")
                } description: {
                    Text("Open the app to start it.")
                }
                .frame(maxHeight: .infinity)
            }

            HStack {
                Text(entry.headline)
                    .font(.subheadline)
                Spacer()
                if let detail = entry.status.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Pieces

/// The streak, or nothing at all. A zero is not worth the pixels, and showing
/// "0 days" to someone who has just lost a streak is a poor way to invite them
/// back.
private struct StreakBadge: View {
    let streak: Int

    var body: some View {
        if streak > 0 {
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                Text(streak, format: .number)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tint)
            .accessibilityLabel(Text("^[\(streak) day](inflect: true) streak"))
        }
    }
}

private struct StreakLine: View {
    let status: DailyStatus

    var body: some View {
        if status.streak > 0 {
            Label {
                Text("^[\(status.streak) day](inflect: true) streak")
            } icon: {
                Image(systemName: "flame.fill")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.tint)
        } else if status.bestStreak > 0 {
            Text("Best streak: ^[\(status.bestStreak) day](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Words

extension DailyEntry {
    /// What the status says, unless the app has never published anything — in
    /// which case "today's puzzle is ready" would be a claim about a store this
    /// widget has never seen.
    var headline: LocalizedStringKey {
        hasData ? status.headline : "Open the app to begin"
    }
}

extension DailyStatus {

    var symbol: String {
        switch standing {
        case .ready: "square.grid.3x3"
        case .inProgress: "pencil.and.outline"
        case .completed: "checkmark.circle.fill"
        }
    }

    /// The one line the widget exists to say.
    ///
    /// `LocalizedStringKey`, not `String`. `Text(someString)` takes the
    /// `StringProtocol` overload, which is documented as displaying a stored
    /// string *without* localization — so a `String` here would have shipped the
    /// English through untranslated, and `detail`'s `^[…](inflect:)` markup
    /// would have been drawn literally, brackets and all.
    var headline: LocalizedStringKey {
        switch standing {
        case .ready: streak > 0 ? "Keep the streak going" : "Today's puzzle is ready"
        case .inProgress: "Picked up, not finished"
        case .completed: "Solved today"
        }
    }

    /// The supporting number, when there is one worth showing.
    var detail: LocalizedStringKey? {
        switch standing {
        case .ready:
            nil
        case .inProgress:
            remainingCells.map { "^[\($0) cell](inflect: true) left" }
        case .completed:
            elapsedSeconds.map { "in \($0 / 60):\(String(format: "%02d", $0 % 60))" }
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    DailyWidget()
} timeline: {
    DailyEntry(date: .now, status: .preview)
    DailyEntry(date: .now, status: .empty(), hasData: false)
}

#Preview("Medium", as: .systemMedium) {
    DailyWidget()
} timeline: {
    DailyEntry(date: .now, status: .preview)
}

#Preview("Large", as: .systemLarge) {
    DailyWidget()
} timeline: {
    DailyEntry(date: .now, status: .preview)
}
