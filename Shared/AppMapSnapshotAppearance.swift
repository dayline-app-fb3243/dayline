import SwiftUI
import UIKit

/// Siri map snapshots do not inherit the app view's color scheme. Match the user's
/// in-app Appearance choice there; System follows the device.
enum AppMapSnapshotAppearance {
    static var interfaceStyle: UIUserInterfaceStyle {
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "Light": return .light
        case "Dark": return .dark
        default: return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
    }
}
