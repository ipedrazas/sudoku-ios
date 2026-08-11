import SudokuKit
import SwiftUI

/// Everything the player can change, in the order they are likely to want it.
///
/// Until now these lived in the game screen's overflow menu, which was the right
/// call while there were three of them and no screen to put them on. There are
/// now nine, and two of them (haptics, theme) have nothing to do with the game
/// in front of you.
struct SettingsScreen: View {
    @Bindable var settings: AppSettings
    /// Deleting everything needs the store, and confirming it needs the counts.
    var stats: StatsModel
    var onEraseAll: () -> Void

    @State private var isConfirmingErase = false
    @State private var showsWelcome = false

    var body: some View {
        Form {
            Section {
                Toggle("Highlight mistakes", isOn: $settings.highlightsMistakes)
                    .accessibilityIdentifier("settings.highlightMistakes")

                Picker("Input", selection: $settings.inputMode) {
                    ForEach(InputMode.allCases, id: \.self) { Text($0.name).tag($0) }
                }

                Toggle("Start with notes filled in", isOn: $settings.autoFillNotes)
            } header: {
                Text("Playing")
            } footer: {
                Text(
                    """
                    Highlighting mistakes marks a clash as soon as you make it. \
                    It is off to begin with, because spotting them is part of the puzzle.
                    """
                )
            }

            Section {
                Picker("Offer to pause after", selection: $settings.inactivityMinutes) {
                    ForEach(AppSettings.inactivityChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Never" : "^[\(minutes) minute](inflect: true)").tag(minutes)
                    }
                }
            } header: {
                Text("Breaks")
            } footer: {
                Text("A puzzle left open while you answer the door should not ruin your best time.")
            }

            Section {
                Toggle("Remind me", isOn: $settings.reminderEnabled)
                    .accessibilityIdentifier("settings.reminder")

                if settings.reminderEnabled {
                    Picker("At", selection: $settings.reminderHour) {
                        ForEach(AppSettings.reminderHours, id: \.self) { hour in
                            Text(Self.label(forHour: hour)).tag(hour)
                        }
                    }
                }
            } header: {
                Text("Daily reminder")
            } footer: {
                Text("One nudge on days you have not played. It stops as soon as you finish the daily.")
            }

            Section("Feel") {
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
                Toggle("Sound", isOn: $settings.soundEnabled)
                Picker("Theme", selection: $settings.theme) {
                    ForEach(ThemePreference.allCases, id: \.self) { Text($0.name).tag($0) }
                }
            }

            Section {
                // The welcome sheet is three sentences, one of which is where
                // notes hide. Nobody remembers that from the day they installed
                // the app, and there is no other place to look it up.
                Button("Show the welcome again") { showsWelcome = true }
                    .accessibilityIdentifier("settings.welcome")
            }

            Section {
                Button("Delete all data", role: .destructive) { isConfirmingErase = true }
                    .accessibilityIdentifier("settings.erase")
            } footer: {
                Text(
                    """
                    Puzzles, saved games, history and achievements, all of it on this device only. \
                    There is no copy anywhere else, so this cannot be undone.
                    """
                )
            }

            Section {
                LabeledContent("Puzzles solved", value: String(stats.stats.totalFinished))
                LabeledContent("Achievements", value: "\(stats.unlockedCount) of \(stats.achievements.count)")
            } header: {
                Text("This device")
            } footer: {
                Text("No account, no sync, no tracking. Nothing here leaves the device.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete everything?",
            isPresented: $isConfirmingErase,
            titleVisibility: .visible
        ) {
            Button("Delete all data", role: .destructive, action: onEraseAll)
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("\(stats.stats.totalFinished) solved puzzles and every saved game. This cannot be undone.")
        }
        .sheet(isPresented: $showsWelcome) {
            WelcomeSheet { showsWelcome = false }
        }
    }

    private static func label(forHour hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "\(hour):00" }
        return date.formatted(.dateTime.hour().minute())
    }
}
