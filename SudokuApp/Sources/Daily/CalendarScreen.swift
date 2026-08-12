import SudokuKit
import SwiftUI

/// A month at a time: what has been solved, what was started, what is still
/// waiting.
///
/// Every past day is playable, and none of them needed storing to be — the date
/// is the seed, so history is reproduced rather than retained. A player who
/// installs the app today can go back and play the whole year.
struct CalendarScreen: View {
    @Bindable var model: DailyModel
    var onPlay: (Date) -> Void

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader

                LazyVGrid(columns: Self.columns, spacing: 6) {
                    ForEach(model.weekdaySymbols.indices, id: \.self) { index in
                        Text(model.weekdaySymbols[index])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(model.cells) { cell in
                        dayCell(cell)
                    }
                }

                legend
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            // Wide screens do not want a calendar the width of an iPad; the grid
            // stops growing and centres instead.
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.refresh() }
    }

    // MARK: - Pieces

    private var monthHeader: some View {
        HStack {
            Button {
                model.showPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("calendar.previous")
            .accessibilityLabel("Previous month")

            Spacer()

            Text(model.monthTitle)
                .font(.headline)
                .accessibilityIdentifier("calendar.month")

            Spacer()

            Button {
                model.showNextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(!model.canShowNextMonth)
            .accessibilityIdentifier("calendar.next")
            .accessibilityLabel("Next month")
        }
    }

    @ViewBuilder
    private func dayCell(_ cell: CalendarCell) -> some View {
        if let date = cell.date, let number = cell.dayNumber {
            let state = cell.dateKey.flatMap(model.state(forKey:))
            let playable = model.isPlayable(cell)

            Button {
                onPlay(date)
            } label: {
                Text(String(number))
                    .font(.callout.monospacedDigit())
                    .fontWeight(model.isToday(cell) ? .bold : .regular)
                    .foregroundStyle(foreground(state: state, playable: playable))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(background(state: state), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        // Today is ringed rather than filled, so it stays
                        // legible whatever its status is.
                        if model.isToday(cell) {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!playable)
            .accessibilityIdentifier("calendar.day.\(cell.dateKey ?? "")")
            .accessibilityLabel(label(for: cell, number: number, state: state, playable: playable))
        } else {
            Color.clear.frame(height: 44)
        }
    }

    /// Status is never carried by colour alone — solved days get a filled tint
    /// *and* bold weight, in-progress days a lighter tint and a visible outline.
    /// Required for colour-blind players and checked again in Phase 9.
    private func background(state: DailyState?) -> Color {
        guard let state else { return Color.secondary.opacity(0.08) }
        if state.isCompleted { return Color.green.opacity(0.25) }
        if state.isInProgress { return Color.orange.opacity(0.2) }
        return Color.secondary.opacity(0.08)
    }

    private func foreground(state: DailyState?, playable: Bool) -> Color {
        guard playable else { return .secondary.opacity(0.35) }
        return .primary
    }

    private func label(for cell: CalendarCell, number: Int, state: DailyState?, playable: Bool) -> String {
        let status: String
        if let state, state.isCompleted {
            status = state.formattedTime.map { String(localized: "solved in \($0)") } ?? String(localized: "solved")
        } else if state?.isInProgress == true {
            status = String(localized: "in progress")
        } else if playable {
            status = String(localized: "not played")
        } else {
            status = String(localized: "not available yet")
        }
        // Assembled by a format string rather than by joining on ", ": the
        // separator between a day and its status is punctuation, and a
        // translation is entitled to a different one — or to a different order.
        return String(localized: "Day \(number), \(status)")
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: .green.opacity(0.25), label: "Solved")
            legendItem(color: .orange.opacity(0.2), label: "Started")
            legendItem(color: .secondary.opacity(0.08), label: "Not played")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func legendItem(color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 14, height: 14)
            Text(label)
        }
    }
}
