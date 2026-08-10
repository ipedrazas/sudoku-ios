import Foundation
import SudokuKit
import UserNotifications

/// One reminder to schedule.
struct StreakReminder: Equatable, Sendable, Identifiable {
    /// The UTC day this reminder protects.
    let dateKey: String
    let fireDate: Date
    let title: String
    let body: String

    var id: String { "streak.\(dateKey)" }
}

/// Works out *when* to remind someone, with no reference to the notification
/// system at all.
///
/// Separated because the interesting part is the arithmetic — which days, at
/// what instant, and the time-zone trap below — and none of it is testable
/// through `UNUserNotificationCenter`.
enum StreakReminderPlan {

    /// How many days ahead to schedule.
    ///
    /// More than one, because the whole point is reaching someone who has *not*
    /// opened the app: scheduling only the next reminder means a player who
    /// misses one day never hears from us again, which is precisely backwards.
    static let horizon = 7

    /// The reminders to have pending, given what the player has already done.
    ///
    /// Only the first carries the streak count. The others are days away, by
    /// which time the number would be wrong — and a reminder that misstates the
    /// thing it is protecting is worse than a vague one.
    static func reminders(
        now: Date,
        hour: Int,
        streak: Int,
        isTodayCompleted: Bool,
        horizon: Int = horizon,
        calendar: Calendar = .current
    ) -> [StreakReminder] {
        var reminders: [StreakReminder] = []

        for dayOffset in 0..<horizon {
            guard let day = DailyPuzzle.calendar.date(byAdding: .day, value: dayOffset, to: now) else { break }
            // Today is already taken care of.
            if dayOffset == 0, isTodayCompleted { continue }
            guard let fireDate = fireDate(on: day, hour: hour, calendar: calendar), fireDate > now else { continue }

            // Only today can honestly say "tonight". Tomorrow's reminder is
            // scheduled now but fires after a day that may well have broken the
            // streak, so it makes no claim about it.
            let isTonight = dayOffset == 0 && streak > 0
            let days = streak == 1 ? "1 day" : "\(streak) days"

            reminders.append(
                StreakReminder(
                    dateKey: DailyPuzzle.dateKey(for: day),
                    fireDate: fireDate,
                    title: isTonight ? "Your streak ends tonight" : "Today's puzzle is waiting",
                    body: isTonight
                        ? "\(days) so far. Today's Sudoku takes a few minutes."
                        : "Keep your solve streak going."
                )
            )
        }

        return reminders
    }

    /// The instant to fire on a given UTC day: always inside that day, at the
    /// player's local hour where possible.
    ///
    /// Two clocks meet here and they do not agree. The hour is *local*, because
    /// that is the only hour meaning anything to the player. The day it protects
    /// is **UTC**, because that is when the daily rolls over. So the local
    /// evening of a UTC day can start before that UTC day does: in Newfoundland
    /// (UTC−3:30) the 10th of August begins at 8:30 pm on the 9th, and a 7 pm
    /// reminder "for the 10th" would fire while the app is still showing the
    /// 9th's puzzle — reminding the player about a puzzle they cannot see.
    ///
    /// So the hour is taken on the local day containing the UTC day's start, and
    /// then pushed forward a day if it had already passed. The upper clamp is a
    /// guard rather than a case: after the shift the fire time is within 24
    /// hours of the day's start, and only a DST seam could put it outside.
    static func fireDate(on day: Date, hour: Int, calendar: Calendar = .current) -> Date? {
        let dayStart = DailyPuzzle.utcMidnight(of: day)
        guard let deadline = DailyPuzzle.calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard var candidate = calendar.date(from: components) else { return nil }

        if candidate < dayStart {
            guard let shifted = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = shifted
        }
        return min(candidate, deadline.addingTimeInterval(-3600))
    }
}

/// The thin part: hands the plan to the system.
///
/// Everything here is a wrapper over one `UNUserNotificationCenter` call, which
/// is the point — there is nothing to test in it, and nothing worth testing is
/// in it.
@MainActor
enum StreakNotifications {

    /// Asks once. A refusal is a normal answer, not an error: the toggle goes
    /// back off and the app carries on.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Replaces every pending reminder with the current plan.
    ///
    /// Replacing rather than adding is what makes this safe to call from
    /// anywhere — screen appears, setting changes, puzzle solved — without
    /// keeping track of what is already scheduled.
    static func reschedule(
        enabled: Bool,
        hour: Int,
        streak: Int,
        isTodayCompleted: Bool,
        now: Date = Date()
    ) async {
        cancelAll()
        guard enabled, await isAuthorized() else { return }

        let center = UNUserNotificationCenter.current()
        for reminder in StreakReminderPlan.reminders(
            now: now,
            hour: hour,
            streak: streak,
            isTodayCompleted: isTodayCompleted
        ) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.fireDate
            )
            let request = UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
