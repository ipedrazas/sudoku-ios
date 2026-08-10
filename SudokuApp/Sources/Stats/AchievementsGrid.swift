import SudokuKit
import SwiftUI

/// All eleven achievements: what has been earned, and what is still out there.
///
/// Locked ones are shown rather than hidden. An achievement nobody can see is
/// not a goal, and the keys are frozen (`Achievements.all`) so the list is a
/// fixed, finite thing worth showing in full.
struct AchievementsGrid: View {
    let achievements: [AchievementState]
    /// Keys unlocked by the solve the player just finished, if they arrived here
    /// straight from it.
    var highlighting: Set<String> = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(achievements) { state in
                cell(state)
            }
        }
    }

    private func cell(_ state: AchievementState) -> some View {
        let isNew = highlighting.contains(state.achievement.key)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: state.achievement.icon))
                .font(.title3)
                .foregroundStyle(state.isUnlocked ? .yellow : Color.secondary.opacity(0.4))
                .symbolEffect(.bounce, options: .nonRepeating, isActive: isNew && !reduceMotion)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.achievement.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.isUnlocked ? .primary : .secondary)

                Text(state.achievement.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let unlockedAt = state.unlockedAt {
                    Text(unlockedAt, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        // Both dimensions: a grid row is as tall as its tallest cell, and
        // without this the shorter one keeps its own height and the row reads
        // as ragged rather than as a grid.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            // Earned is carried by weight, colour *and* an outline — never by
            // colour alone, which a colour-blind player could not read.
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isNew ? Color.accentColor : .clear, lineWidth: 2)
        }
        // Locked entries are dimmed but not hidden, and stay legible.
        .opacity(state.isUnlocked ? 1 : 0.65)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(state))
    }

    private func accessibilityLabel(_ state: AchievementState) -> String {
        guard let unlockedAt = state.unlockedAt else {
            return "\(state.achievement.name), locked. \(state.achievement.detail)"
        }
        let date = unlockedAt.formatted(.dateTime.day().month(.wide).year())
        return "\(state.achievement.name), unlocked \(date). \(state.achievement.detail)"
    }

    /// The engine names icon families rather than SF Symbols, because it has no
    /// business knowing what platform is drawing it.
    private func symbol(for icon: String) -> String {
        switch icon {
        case "zap": "bolt.fill"
        case "trophy": "trophy.fill"
        case "fire": "flame.fill"
        default: "star.fill"
        }
    }
}
