import Foundation

/// App Shortcuts use App Intents on every supported iOS version; Apple Intelligence
/// is not required to show the available Siri/Shortcuts examples in Profile.
enum SiriSupport {
    static var isAvailable: Bool { true }
}
