import SudokuKit
import SwiftUI

/// Undo · Redo · Erase · Notes · Hint.
///
/// Sits directly above the number pad, in the bottom third where a thumb
/// reaches (§8.1). Everything here is also available from the keyboard on iPad.
struct ControlBar: View {
    @Bindable var session: GameSession
    var onHint: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            control("Undo", systemImage: "arrow.uturn.backward", enabled: session.canUndo) {
                session.undo()
            }
            control("Redo", systemImage: "arrow.uturn.forward", enabled: session.canRedo) {
                session.redo()
            }
            control("Erase", systemImage: "eraser", enabled: session.selection != nil) {
                session.erase()
            }
            control(
                "Notes",
                systemImage: session.isPencilMode ? "pencil.circle.fill" : "pencil.circle",
                enabled: true,
                isActive: session.isPencilMode
            ) {
                session.toggleNotes()
            }
            control("Hint", systemImage: "lightbulb", enabled: !session.isSolved, badge: session.hintPoints) {
                onHint()
            }
        }
    }

    private func control(
        _ title: String,
        systemImage: String,
        enabled: Bool,
        isActive: Bool = false,
        badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .frame(height: 24)
                    if badge > 0 {
                        Text(String(badge))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 12, y: -6)
                    }
                }
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(isActive ? Color.accentColor : (enabled ? Color.primary : Color.secondary.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("control.\(title.lowercased())")
        .accessibilityLabel(isActive ? "\(title), on" : title)
    }
}
