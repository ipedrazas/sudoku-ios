import SudokuKit
import SwiftUI

/// Hardware-keyboard control of the board.
///
/// The strategy doc deferred keyboard bindings as web-only, on the grounds that
/// no iPhone has a keyboard. iPad does, and iPad ships in v1 — a Magic Keyboard
/// is a first-class way to play. The bindings are the web app's defaults
/// (`lib/settings.ts:17-25`) so muscle memory carries across:
///
/// | key | action |
/// |---|---|
/// | `1`–`9` | place a digit |
/// | `0`, delete | erase |
/// | arrows | move the selection |
/// | `P` | notes |
/// | space | blind mode |
/// | `H` | hint |
/// | `N` | highlight the selected digit |
/// | `⌘Z` / `⌘⇧Z` | undo / redo |
struct KeyboardCommands: ViewModifier {
    @Bindable var session: GameSession
    var onHint: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(action: handle)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // ⌘Z and ⌘⇧Z first: the plain `z` binding must not swallow them.
        if press.modifiers.contains(.command), press.key.character.lowercased() == "z" {
            if press.modifiers.contains(.shift) { session.redo() } else { session.undo() }
            return .handled
        }
        guard press.modifiers.isEmpty else { return .ignored }

        switch press.key {
        case .upArrow: session.moveSelection(rowDelta: -1, colDelta: 0)
        case .downArrow: session.moveSelection(rowDelta: 1, colDelta: 0)
        case .leftArrow: session.moveSelection(rowDelta: 0, colDelta: -1)
        case .rightArrow: session.moveSelection(rowDelta: 0, colDelta: 1)
        case .delete, .deleteForward: session.erase()
        case .space:
            if let selection = session.selection { session.longPress(selection) }
        default:
            return handleCharacter(press.key.character)
        }
        return .handled
    }

    private func handleCharacter(_ character: Character) -> KeyPress.Result {
        if let digit = character.wholeNumberValue, (1...SudokuKit.Grid.size).contains(digit) {
            session.input(digit)
            return .handled
        }
        switch character.lowercased() {
        case "0": session.erase()
        case "p": session.toggleNotes()
        case "h": onHint()
        case "n": session.toggleHighlightOnSelection()
        default: return .ignored
        }
        return .handled
    }
}

extension View {
    /// Attaches hardware-keyboard control. A no-op without a keyboard, so it is
    /// applied unconditionally rather than gated on idiom.
    func keyboardCommands(session: GameSession, onHint: @escaping () -> Void) -> some View {
        modifier(KeyboardCommands(session: session, onHint: onHint))
    }
}
