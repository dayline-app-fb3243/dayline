import Foundation
import FoundationModels

/// Siri features only exist on iPhones with the new Siri (iOS 27 + Apple Intelligence).
/// Older iPhones get no Siri section at all.
enum SiriSupport {
    static var isAvailable: Bool {
        // Demo tour shows how it looks on a supported iPhone.
        if ProcessInfo.processInfo.arguments.contains("-demo") { return true }
        guard #available(iOS 27, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }
}
