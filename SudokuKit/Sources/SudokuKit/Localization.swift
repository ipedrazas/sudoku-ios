import Foundation

/// Player-facing copy, looked up rather than written inline.
///
/// The kit is otherwise free of Foundation-flavoured platform behaviour, and
/// this is the one place that isn't: hint sentences, achievement names and
/// difficulty labels are read by a person, so they translate.
///
/// **Sentences are format strings, never interpolation.** A hint built by
/// `"There's a hidden single in \(unit)"` is untranslatable in any language that
/// inflects, because the translator cannot move the unit relative to the verb.
/// Every sentence below takes its pieces as positional arguments (`%1$@`) so a
/// translation is free to reorder them.
enum Copy {

    /// Forces a language, ignoring the device's.
    ///
    /// Only the tests set this. It is a task-local rather than a plain global
    /// because the suite runs in parallel: a mutable static would have one test
    /// asserting Spanish copy while another asserted English against the same
    /// storage. Bound with `Copy.$language.withValue("es") { … }`, the override
    /// reaches everything that call runs and nothing that it doesn't.
    @TaskLocal static var language: String?

    /// One bundle per `.lproj` the kit ships, resolved once.
    ///
    /// Derived from what is actually in the bundle rather than a hard-coded
    /// list, so a third language is a directory of strings and no code at all.
    private static let localizedBundles: [String: Bundle] = Dictionary(
        uniqueKeysWithValues: Bundle.module.localizations.compactMap { code in
            Bundle.module.path(forResource: code, ofType: "lproj")
                .flatMap(Bundle.init(path:))
                .map { (code, $0) }
        }
    )

    /// Every language the kit actually ships copy for.
    ///
    /// The tests run their assertions across all of them, and they read the list
    /// from here rather than from their own `Bundle.module` — which is the *test*
    /// bundle, and knows nothing about what the kit was built with.
    static var availableLanguages: [String] { localizedBundles.keys.sorted() }

    /// The localised copy for `key`, with `arguments` substituted.
    ///
    /// A missing key returns the key itself, which is deliberate and is what
    /// `HintCopyTests` catches: every hint must end in a full stop, and
    /// `hint.xWing.nudge` does not. A typo fails the suite rather than shipping.
    static func text(_ key: String, _ arguments: any CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    /// Cells or digits written out as a list a person would read: "R5C2 and
    /// R5C6", "R5C2, R5C6 and R5C8".
    ///
    /// Both the separator and the word before the last item come from the
    /// strings file. English's "and" is Spanish's "y", and which of the two
    /// joins goes where is not the same everywhere either — a list is
    /// punctuation, and punctuation is part of a language.
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        let leading = items.dropLast().joined(separator: text("list.separator"))
        return leading + text("list.conjunction") + last
    }

    private static var bundle: Bundle {
        guard let language, let override = localizedBundles[language] else { return .module }
        return override
    }

    private static var locale: Locale {
        guard let language else { return .current }
        return Locale(identifier: language)
    }
}
