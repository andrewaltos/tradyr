import Foundation
import Translation

/// On-device translation with Apple's Translation framework.
///
/// The language packs must already be installed. Use `status(from:to:)` to check, and
/// `TranslationSession.prepareTranslation()` (via SwiftUI's `translationTask`) to download them.
public actor SegmentTranslator {
    private let session: TranslationSession

    public init(source: Locale.Language, target: Locale.Language) {
        session = TranslationSession(installedSource: source, target: target)
    }

    public func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }

    public static func status(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }
}
