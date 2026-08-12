import SudokuKit
import SwiftUI

/// Today's puzzle, the streak it feeds, and the way into the calendar.
///
/// Everyone gets the same medium puzzle on the same UTC day, with no server
/// involved — the date seeds the generator, so two devices that have never
/// spoken agree on the 3rd of March. That is the whole feature; the screen just
/// has to make the day feel like an occasion rather than a menu item.
struct DailyScreen: View {
    @Bindable var model: DailyModel
    var onPlay: (Date) -> Void
    var onShowCalendar: () -> Void

    @AppStorage("dailyReminderEnabled") private var reminderEnabled = false
    @AppStorage("dailyReminderHour") private var reminderHour = 19

    @Environment(\.scenePhase) private var scenePhase

    private var today: DailyState? { model.today() }

    var body: some View {
        List {
            Section {
                headline
                    .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
            }

            Section {
                playButton
            } footer: {
                Text("Everyone gets the same puzzle each day. Miss one and you can still play it later.")
            }

            Section {
                streakRow
                Button {
                    onShowCalendar()
                } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    } label: {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("daily.calendar")
            }

            reminderSection
        }
        .navigationTitle("Daily")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.refresh()
            await refreshReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the background may mean a new UTC day, in which
            // case everything on this screen is about yesterday.
            if phase == .active { model.refresh() }
        }
    }

    // MARK: - Pieces

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.largeTitle.bold())

            Text(statusLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        guard let today else { return String(localized: "Not started") }
        if today.isCompleted {
            return today.formattedTime.map { String(localized: "Solved in \($0)") } ?? String(localized: "Solved")
        }
        if today.isInProgress, let remaining = today.remainingCells {
            return String(localized: "In progress — \(remaining) to go")
        }
        return String(localized: "Not started")
    }

    private var playButton: some View {
        Button {
            onPlay(Date())
        } label: {
            Label(playTitle, systemImage: playSymbol)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("daily.play")
    }

    private var playTitle: String {
        guard let today else { return String(localized: "Play today's puzzle") }
        if today.isCompleted { return String(localized: "Play it again") }
        return today.isInProgress ? String(localized: "Continue") : String(localized: "Play today's puzzle")
    }

    private var playSymbol: String {
        today?.isCompleted == true ? "arrow.counterclockwise" : "play.fill"
    }

    private var streakRow: some View {
        LabeledContent {
            Text(model.streak.best > 0 ? "best \(model.streak.best)" : "")
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            Label {
                // The hand-written "1 day streak" special case is gone: one
                // inflected form covers both, and covers languages where the
                // split is not at one.
                Text("^[\(model.streak.current) day](inflect: true) streak")
            } icon: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(model.streak.current > 0 ? .orange : .secondary)
            }
        }
        .accessibilityIdentifier("daily.streak")
        .accessibilityLabel(
            Text("Current streak ^[\(model.streak.current) day](inflect: true), best \(model.streak.best)")
        )
    }

    @ViewBuilder
    private var reminderSection: some View {
        Section {
            Toggle("Remind me", isOn: $reminderEnabled)
                .accessibilityIdentifier("daily.reminder")

            if reminderEnabled {
                Picker("At", selection: $reminderHour) {
                    ForEach(Self.reminderHours, id: \.self) { hour in
                        Text(Self.label(forHour: hour)).tag(hour)
                    }
                }
            }
        } footer: {
            Text("A single nudge on days you have not played. It stops as soon as you finish the daily.")
        }
        .onChange(of: reminderEnabled) { _, enabled in
            Task {
                // Ask only when switching on, and only once — a refusal turns
                // the toggle back off rather than leaving it lying.
                if enabled, await StreakNotifications.isAuthorized() == false {
                    reminderEnabled = await StreakNotifications.requestAuthorization()
                }
                await refreshReminders()
            }
        }
        .onChange(of: reminderHour) { _, _ in
            Task { await refreshReminders() }
        }
    }

    /// Evening hours, and only whole ones. A minute picker would be precision
    /// nobody wants for something that only has to happen before midnight.
    private static let reminderHours = [17, 18, 19, 20, 21, 22]

    private static func label(forHour hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "\(hour):00" }
        return date.formatted(.dateTime.hour().minute())
    }

    private func refreshReminders() async {
        await StreakNotifications.reschedule(
            enabled: reminderEnabled,
            hour: reminderHour,
            streak: model.streak.current,
            isTodayCompleted: model.isCompleted()
        )
    }
}
