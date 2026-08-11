import Foundation
import SwiftUI

/// How the app picks its appearance.
enum ThemePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Nil means "whatever the device is set to".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Every preference, in one place.
///
/// `@AppStorage` is a view-only property wrapper, and these are read by things
/// that are not views — a session is built from the input mode and the mistake
/// setting before any view exists, and the reminder scheduler needs the hour
/// from a background refresh. So this is an `@Observable` over `UserDefaults`
/// instead: views bind to it exactly as they would to `@AppStorage`, and
/// everything else can just read it.
///
/// The keys match the web app's `lib/settings.ts` where a setting exists in
/// both, and so do the defaults — including the one that looks wrong.
@Observable
@MainActor
final class AppSettings {

    // MARK: - Play

    /// **Off by default, matching the web app.** Highlighting mistakes as they
    /// happen turns the puzzle into a different game, and deciding that for the
    /// player is not ours to do.
    var highlightsMistakes: Bool { didSet { write(highlightsMistakes, .highlightsMistakes) } }

    var inputMode: InputMode { didSet { write(inputMode.rawValue, .inputMode) } }

    /// Minutes idle before the app offers to pause. 0 disables the prompt.
    var inactivityMinutes: Int { didSet { write(inactivityMinutes, .inactivityMinutes) } }

    /// Fill every empty cell's candidates when a game starts.
    var autoFillNotes: Bool { didSet { write(autoFillNotes, .autoFillNotes) } }

    // MARK: - Feedback

    var hapticsEnabled: Bool { didSet { write(hapticsEnabled, .haptics) } }
    var soundEnabled: Bool { didSet { write(soundEnabled, .sound) } }

    // MARK: - Appearance

    var theme: ThemePreference { didSet { write(theme.rawValue, .theme) } }

    // MARK: - Daily reminder

    var reminderEnabled: Bool { didSet { write(reminderEnabled, .reminderEnabled) } }
    var reminderHour: Int { didSet { write(reminderHour, .reminderHour) } }

    // MARK: - Onboarding

    /// Whether the welcome sheet has been seen. Written the moment it is shown
    /// rather than when it is dismissed: a first launch that is force-quit
    /// halfway through the sheet has still had its introduction, and being
    /// introduced to an app twice is worse than not at all.
    var hasSeenWelcome: Bool { didSet { write(hasSeenWelcome, .hasSeenWelcome) } }

    private let defaults: UserDefaults

    /// The suite is injectable so tests get their own, rather than editing the
    /// preferences of whatever machine runs them.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        highlightsMistakes = defaults.object(forKey: Key.highlightsMistakes.rawValue) as? Bool ?? false
        inputMode =
            (defaults.string(forKey: Key.inputMode.rawValue).flatMap(InputMode.init(rawValue:))) ?? .cellFirst
        inactivityMinutes = defaults.object(forKey: Key.inactivityMinutes.rawValue) as? Int ?? 5
        autoFillNotes = defaults.object(forKey: Key.autoFillNotes.rawValue) as? Bool ?? false
        hapticsEnabled = defaults.object(forKey: Key.haptics.rawValue) as? Bool ?? true
        soundEnabled = defaults.object(forKey: Key.sound.rawValue) as? Bool ?? false
        theme = (defaults.string(forKey: Key.theme.rawValue).flatMap(ThemePreference.init(rawValue:))) ?? .system
        reminderEnabled = defaults.object(forKey: Key.reminderEnabled.rawValue) as? Bool ?? false
        reminderHour = defaults.object(forKey: Key.reminderHour.rawValue) as? Int ?? 19
        hasSeenWelcome = defaults.object(forKey: Key.hasSeenWelcome.rawValue) as? Bool ?? false
    }

    /// The inactivity choices the web app offers (`lib/settings.ts:34`), plus
    /// the option to turn it off.
    static let inactivityChoices = [0, 1, 3, 5, 10]

    /// Evening hours only, and only whole ones. Minute precision is precision
    /// nobody wants for something that has to happen before midnight.
    static let reminderHours = [17, 18, 19, 20, 21, 22]

    private enum Key: String {
        case highlightsMistakes = "highlightMistakes"
        case inputMode
        case inactivityMinutes
        case autoFillNotes
        case haptics = "hapticsEnabled"
        case sound = "soundEnabled"
        case theme
        // Unchanged from Phase 5, so an upgrade keeps the player's reminder.
        case reminderEnabled = "dailyReminderEnabled"
        case reminderHour = "dailyReminderHour"
        case hasSeenWelcome
    }

    private func write(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
