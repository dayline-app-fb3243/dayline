import SwiftUI
import UIKit

/// Maps use the phone's appearance, independent of Dayline's in-app Appearance setting.
enum SystemMapAppearance {
    static var scheme: ColorScheme {
        UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
    static var interfaceStyle: UIUserInterfaceStyle {
        UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}
