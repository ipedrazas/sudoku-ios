import SwiftUI

/// The one screen of onboarding this app gets.
///
/// A Sudoku app does not need to teach Sudoku. What it does need to say is the
/// three things that are *not* obvious from looking at a grid: that there is a
/// daily, that notes are a long press away, and that the hints explain rather
/// than fill in. Anything beyond that is a tutorial nobody asked for standing
/// between someone and the puzzle they opened the app to play.
///
/// Shown once, and re-showable from Settings — which is also what makes it safe
/// to keep short. Nothing here is the only chance to say something.
struct WelcomeSheet: View {
    var onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    // Keyed on the symbol, not the title: a `LocalizedStringKey`
                    // is not `Hashable`, and identity that moves with the
                    // language is not identity anyway.
                    ForEach(Self.points, id: \.symbol) { point in
                        Point(point: point)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }

            Button(action: onDismiss) {
                Text("Start playing")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(maxWidth: 520)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
            .accessibilityIdentifier("welcome.start")
        }
        .background(.background)
        // The sheet is dismissible only through the button, so there is exactly
        // one way out and no chance of swiping past it by accident on the way to
        // the first game.
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sudoku and Cake")
                .font(.largeTitle.bold())
            Text("No accounts, no ads, no internet. Just puzzles.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private struct Point: View {
        let point: Detail
        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
            // At the largest accessibility sizes an icon beside text leaves the
            // text a column three words wide, so the layout stacks instead.
            // P9-3 asks for XXL with no clipping; this is that, early.
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))

            layout {
                Image(systemName: point.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: typeSize.isAccessibilitySize ? nil : 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(point.title)
                        .font(.headline)
                    Text(point.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    struct Detail {
        let symbol: String
        /// `LocalizedStringKey`, because these reach `Text` through a stored
        /// property rather than as a literal at the call site — and `Text` only
        /// localises what it is handed as a key.
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private static let points = [
        Detail(
            symbol: "calendar",
            title: "A new puzzle every day",
            body: "Everyone gets the same daily. Solve it to build a streak — and add a widget so you don't forget."
        ),
        Detail(
            symbol: "pencil.and.outline",
            title: "Notes are a long press",
            body: "Hold a number to pencil it in, or turn notes on to mark candidates as you narrow them down."
        ),
        Detail(
            symbol: "lightbulb.max",
            title: "Hints that teach",
            body: """
                Ask for a nudge and it names the technique. Ask again and it shows you where. \
                The answer is the last resort.
                """
        ),
    ]
}

#Preview {
    WelcomeSheet(onDismiss: {})
}
