import SwiftUI
import WidgetKit

/// Everything this extension offers.
///
/// Two entries, both driven by the same App Group snapshot: the Home Screen
/// widget that shows today's board, and the Lock Screen family that says whether
/// today is still owed.
@main
struct SudokuWidgets: WidgetBundle {
    var body: some Widget {
        DailyWidget()
        StreakWidget()
    }
}
