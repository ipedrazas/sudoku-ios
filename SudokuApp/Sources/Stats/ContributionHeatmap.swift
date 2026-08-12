import SudokuKit
import SwiftUI

/// A year of solves, one square per day.
///
/// The only chart here where colour encodes magnitude, because a square has no
/// length to encode it with. So it follows the sequential rule exactly: **one
/// hue, light to dark**, never a rainbow. Empty days are a neutral gray rather
/// than the palest step of the hue, so "nothing happened" is a different kind of
/// thing from "a little happened" rather than the bottom of the same scale.
///
/// Dark mode is chosen rather than flipped: the steps below are their own ramp
/// against a dark surface, because opacity over black is not the same design as
/// opacity over white.
struct ContributionHeatmap: View {
    let weeks: [ContributionWeek]

    @Environment(\.colorScheme) private var colorScheme

    private let cell: CGFloat = 11
    private let spacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weeks) { week in
                        VStack(spacing: spacing) {
                            ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                                square(day)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            // The newest week is the interesting one, so the scroll starts there
            // rather than a year ago.
            .defaultScrollAnchor(.trailing)

            legend
        }
    }

    @ViewBuilder
    private func square(_ day: ContributionDay?) -> some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(day.map { fill(level: $0.level) } ?? .clear)
            .frame(width: cell, height: cell)
            .accessibilityLabel(day.map(label(for:)) ?? "")
            .accessibilityHidden(day == nil)
    }

    /// Colour is never the only channel: every square carries its count for
    /// VoiceOver, which is also the "table view" a continuous colour scale owes
    /// the reader.
    private func label(for day: ContributionDay) -> String {
        let date = day.date.formatted(.dateTime.day().month(.wide).year())
        guard day.solved > 0 else { return String(localized: "\(date), no puzzles") }
        return String(localized: "\(date), \(String(localized: "\(day.solved) puzzles solved"))")
    }

    private func fill(level: Int) -> Color {
        guard level > 0 else { return .secondary.opacity(colorScheme == .dark ? 0.16 : 0.10) }
        // Four steps of one hue. Light mode darkens as it climbs; dark mode
        // brightens, which is the same ramp read against its own surface.
        let steps: [Double] = colorScheme == .dark ? [0.35, 0.55, 0.75, 1.0] : [0.25, 0.45, 0.7, 1.0]
        return ChartStyle.bar.opacity(steps[min(level, steps.count) - 1])
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less")
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(fill(level: level))
                    .frame(width: 10, height: 10)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
