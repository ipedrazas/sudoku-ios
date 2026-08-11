import Charts
import SudokuKit
import SwiftUI

/// Every field of the web app's `/api/stats`, rendered locally.
///
/// The order is deliberate: the numbers a player actually wants first (how many,
/// how long a streak, how fast), then the year at a glance, then the breakdowns,
/// then the achievements. Charts answer questions; they are not decoration, and
/// anything that is a single number is a tile rather than a one-bar chart.
struct StatsScreen: View {
    @Bindable var model: StatsModel
    /// Achievements unlocked by the solve that led here, if any.
    var highlighting: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.hasHistory {
                    headline
                    activity
                    difficultyBreakdown
                    times
                    rhythm
                    recent
                } else {
                    empty
                }

                achievements
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.refresh() }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(
                    value: String(model.stats.totalFinished),
                    label: "Solved",
                    symbol: "checkmark.seal.fill",
                    tint: .green
                )
                StatTile(
                    value: String(model.stats.streak.current),
                    label: "Day streak",
                    symbol: "flame.fill",
                    tint: model.stats.streak.current > 0 ? .orange : .secondary
                )
            }
            HStack(spacing: 12) {
                StatTile(value: String(model.stats.streak.best), label: "Best streak", symbol: "trophy.fill")
                StatTile(
                    value: model.completionRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                    label: "Finished vs. open",
                    symbol: "chart.pie.fill"
                )
            }
        }
    }

    // MARK: - Cards

    private var activity: some View {
        StatsCard(
            title: "The last year",
            subtitle: "One square a day, darker where you played more"
        ) {
            ContributionHeatmap(weeks: model.weeks)
        }
    }

    private var difficultyBreakdown: some View {
        StatsCard(title: "By difficulty", subtitle: "Puzzles solved on each rung") {
            Chart(model.countsByDifficulty) { entry in
                BarMark(
                    x: .value("Solved", entry.solved),
                    y: .value("Difficulty", entry.difficulty.name),
                    height: ChartStyle.barWidth
                )
                .foregroundStyle(ChartStyle.bar)
                .cornerRadius(ChartStyle.barCorner)
            }
            .chartYScale(domain: Difficulty.allCases.map(\.name))
            .statsChartAxesHorizontal()
            .frame(height: 140)
            .accessibilityLabel("Puzzles solved by difficulty")
        }
    }

    private var times: some View {
        StatsCard(title: "How long they take", subtitle: "Every solve, bucketed") {
            VStack(alignment: .leading, spacing: 16) {
                Chart(model.stats.timeDistribution) { bucket in
                    BarMark(
                        x: .value("Solves", bucket.count),
                        y: .value("Time", bucket.label),
                        height: ChartStyle.barWidth
                    )
                    .foregroundStyle(ChartStyle.bar)
                    .cornerRadius(ChartStyle.barCorner)
                }
                .chartYScale(domain: model.stats.timeDistribution.map(\.label))
                .statsChartAxesHorizontal()
                .frame(height: 160)
                .accessibilityLabel("Solve times, bucketed")

                if !model.timeStatsByDifficulty.isEmpty {
                    Divider()
                    ForEach(model.timeStatsByDifficulty) { entry in
                        LabeledContent {
                            HStack(spacing: 12) {
                                Text("avg \(Self.time(entry.stats.averageSeconds))")
                                Text("best \(Self.time(Double(entry.stats.bestSeconds)))")
                                    .foregroundStyle(.primary)
                            }
                            .font(.caption.monospacedDigit())
                        } label: {
                            Text(entry.difficulty.name)
                                .font(.caption.weight(.medium))
                        }
                    }
                }
            }
        }
    }

    private var rhythm: some View {
        VStack(spacing: 16) {
            StatsCard(title: "By day of the week") {
                // Plotted against the index rather than the initial: two days
                // share "S" in English and a chart cannot tell them apart. The
                // axis puts the letters back.
                let weekdays = model.countsByWeekday
                Chart(weekdays) { entry in
                    BarMark(
                        x: .value("Day", entry.index),
                        y: .value("Solved", entry.solved),
                        width: ChartStyle.barWidth
                    )
                    .foregroundStyle(ChartStyle.bar)
                    .cornerRadius(ChartStyle.barCorner)
                }
                .chartXScale(domain: -0.5...6.5)
                .chartXAxis {
                    AxisMarks(values: weekdays.map(\.index)) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self), weekdays.indices.contains(index) {
                                Text(weekdays[index].symbol)
                                    .font(.caption2)
                                    .foregroundStyle(ChartStyle.axisText)
                            }
                        }
                    }
                }
                .chartYAxis { valueAxis }
                .chartLegend(.hidden)
                .frame(height: ChartStyle.plotHeight)
                .accessibilityLabel("Puzzles solved by day of the week")
            }

            StatsCard(title: "By month", subtitle: "The last twelve, empty ones included") {
                let months = model.countsByMonth()
                Chart(months) { entry in
                    BarMark(
                        x: .value("Month", entry.key),
                        y: .value("Solved", entry.solved),
                        width: ChartStyle.barWidth
                    )
                    .foregroundStyle(ChartStyle.bar)
                    .cornerRadius(ChartStyle.barCorner)
                }
                .chartXAxis {
                    AxisMarks(values: months.map(\.key)) { value in
                        AxisValueLabel {
                            let key = value.as(String.self)
                            if let entry = months.first(where: { $0.key == key }) {
                                Text(entry.label)
                                    .font(.caption2)
                                    .foregroundStyle(ChartStyle.axisText)
                            }
                        }
                    }
                }
                .chartYAxis { valueAxis }
                .chartLegend(.hidden)
                .frame(height: ChartStyle.plotHeight)
                .accessibilityLabel("Puzzles solved by month")
            }
        }
    }

    private var recent: some View {
        StatsCard(title: "Recently solved") {
            VStack(spacing: 0) {
                ForEach(Array(model.stats.recentCompletions.enumerated()), id: \.offset) { index, completion in
                    if index > 0 { Divider() }
                    HStack {
                        Text(completion.difficulty.name)
                            .font(.subheadline)
                        Spacer()
                        Text(Self.time(Double(completion.timeSeconds)))
                            .font(.subheadline.monospacedDigit())
                        Text(completion.completedAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Achievements")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.unlockedCount) of \(model.achievements.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            AchievementsGrid(achievements: model.achievements, highlighting: highlighting)
        }
        .accessibilityIdentifier("stats.achievements")
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No finished puzzles yet")
                .font(.headline)
            Text("Solve one and this fills up: streaks, times, and a year of squares.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityIdentifier("stats.empty")
    }

    /// Hairline, solid, recessive — the same value axis for both column charts.
    private var valueAxis: AxisMarks<some AxisMark> {
        AxisMarks { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                .foregroundStyle(ChartStyle.gridLine)
            AxisValueLabel()
                .font(.caption2)
                .foregroundStyle(ChartStyle.axisText)
        }
    }

    /// `m:ss`, or `h:mm:ss` once a solve runs past an hour.
    static func time(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
