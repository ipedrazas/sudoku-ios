import SudokuKit
import SwiftUI

/// Undo · Redo · Erase · Notes · Hint.
///
/// Sits directly above the number pad, in the bottom third where a thumb
/// reaches (§8.1). Everything here is also available from the keyboard on iPad.
struct ControlBar: View {
    @Bindable var session: GameSession
    var onHint: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility sizes the captions come off and the icons stand alone.
    ///
    /// Five equal columns cannot hold five words once a caption is 30 points
    /// tall: "Undo" broke to "Und / o", "Erase" to "Eras / e", and the wrapped
    /// halves collided with the icons above them. Widening is not available —
    /// there are five of them and the screen is the screen.
    ///
    /// Dropping the captions is the honest trade. The icons are standard and
    /// already larger at these sizes, the tap targets grow rather than shrink,
    /// and nothing is lost to VoiceOver: `accessibilityLabel` carries the word
    /// whether or not it is drawn. Someone who needs the caption *and* the size
    /// has Larger Text and VoiceOver, and both still work.
    private var showsCaptions: Bool { !typeSize.isAccessibilitySize }

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
                if showsCaptions {
                    Text(title)
                        .font(.caption2)
                        // One line, always. A caption that wraps is the defect
                        // this guards against, and a five-column bar has no
                        // width to give it a second line even if it wanted one.
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            // The row keeps its height when the captions go, so the controls do
            // not jump up the screen as the type size crosses the threshold.
            .frame(minHeight: showsCaptions ? 0 : 44)
            .foregroundStyle(isActive ? Color.accentColor : (enabled ? Color.primary : Color.secondary.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("control.\(title.lowercased())")
        .accessibilityLabel(isActive ? "\(title), on" : title)
    }
}
