import Charts
import SwiftUI

/// The specs every chart on the stats screen shares.
///
/// Four charts, one look. The rules are deliberately few and all of them are
/// about restraint — the data is the only thing allowed to be loud.
///
/// **Every bar chart here is a single hue.** Bar length already encodes the
/// count; colouring bars by their value would spend the identity channel
/// re-encoding what the reader can already see, and colouring them by category
/// would claim four differences that do not exist — there is one series in each
/// chart. The only place colour carries magnitude is the heatmap, which has no
/// length to encode it with.
enum ChartStyle {
    /// Capped rather than filling the slot, so the band keeps some air.
    static let barWidth = MarkDimension.fixed(16)
    /// Rounds the data end. Swift Charts rounds both, which on a bar anchored to
    /// a baseline is a nicety rather than a lie.
    static let barCorner: CGFloat = 4

    static var bar: Color { .accentColor }

    /// Height that leaves room for the axis band beneath the plot. A chart sized
    /// to its plot alone crops its own labels.
    static let plotHeight: CGFloat = 150
}

extension ChartStyle {
    /// Axis ink, and it is **ink** — not the series colour.
    ///
    /// `.secondary` inside a chart is a *hierarchical* style, and the hierarchy
    /// it is relative to is the chart's foreground style, which is the accent.
    /// So `.foregroundStyle(.secondary)` on an axis label produced pale blue
    /// numbers: the text wearing the series colour, which is exactly what text
    /// must never do. `Color.secondary` is the label colour rather than a tint
    /// of whatever is being plotted.
    static let axisText = Color.secondary
    static let gridLine = Color.secondary.opacity(0.25)
}

extension View {
    /// Hairline, solid, recessive. Swift Charts dashes gridlines by default, and
    /// dashing reads as "estimated" — noise where the chart wanted quiet.
    func statsChartAxes() -> some View {
        chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(ChartStyle.gridLine)
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(ChartStyle.axisText)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(ChartStyle.axisText)
            }
        }
        // One series per chart, so the title says what is plotted and a legend
        // box would only restate it.
        .chartLegend(.hidden)
    }

    /// The same, for the charts drawn with the categories down the side.
    ///
    /// The category axis is pinned to the leading edge, which is what moves the
    /// labels out of the plot: left to itself the axis laid each one *inside* the
    /// plot, on top of the bar it named.
    ///
    /// Padding the plot instead is the obvious fix and a wrong one — it shifts
    /// the marks without shifting the axis, so the bars stop growing from the
    /// zero tick and every length silently reads high.
    func statsChartAxesHorizontal() -> some View {
        chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(ChartStyle.gridLine)
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(ChartStyle.axisText)
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading) { _ in
                AxisValueLabel(horizontalSpacing: 8)
                    .font(.caption2)
                    .foregroundStyle(ChartStyle.axisText)
            }
        }
        .chartLegend(.hidden)
    }
}

/// A titled card. Charts sit in one of these so the screen reads as a stack of
/// answers rather than a wall of plots.
struct StatsCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// One headline number. A single value is a stat tile, never a one-bar chart.
struct StatTile: View {
    let value: String
    let label: LocalizedStringKey
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        // Wrapped in `Text` rather than interpolated directly: a
        // `LocalizedStringKey` inside another one interpolates its debug
        // description, untranslated. `Text` is the composable form.
        .accessibilityLabel(Text("\(Text(label)): \(value)"))
    }
}
