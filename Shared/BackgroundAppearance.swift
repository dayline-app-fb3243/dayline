import SwiftUI
import UIKit

/// Built-in backgrounds plus "your own photo". Content cards stay solid on top of any of these.
enum BackgroundPreset: String, CaseIterable, Identifiable {
    case system, white, black, gray, sky, ocean, mint, forest, lavender, rose, sunset, sand, night, graphite, aurora, photo
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Default"
        case .photo: "Your photo"
        default: rawValue.capitalized
        }
    }

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    var colors: [Color] {
        let c = Self.c
        switch self {
        case .system, .photo: return []
        // Settings white: Apple's light gray page, so the white cards and rows stand out on it.
        case .white: return [Color(.systemGroupedBackground), Color(.systemGroupedBackground)]
        case .black: return [.black, .black]
        case .gray: return [c(0.82, 0.82, 0.84), c(0.90, 0.90, 0.92)]
        case .sky: return [c(0.61, 0.77, 1.0), c(0.91, 0.94, 1.0)]
        case .ocean: return [c(0.18, 0.48, 1.0), c(0.04, 0.25, 0.69)]
        case .mint: return [c(0.66, 0.93, 0.83), c(0.93, 0.98, 0.96)]
        case .forest: return [c(0.18, 0.49, 0.36), c(0.07, 0.31, 0.23)]
        case .lavender: return [c(0.80, 0.72, 1.0), c(0.95, 0.93, 1.0)]
        case .rose: return [c(1.0, 0.70, 0.78), c(1.0, 0.91, 0.93)]
        case .sunset: return [c(1.0, 0.70, 0.54), c(1.0, 0.85, 0.78), c(0.79, 0.71, 1.0)]
        case .sand: return [c(0.91, 0.85, 0.72), c(0.97, 0.95, 0.89)]
        case .night: return [c(0.11, 0.14, 0.28), c(0.23, 0.25, 0.44)]
        case .graphite: return [c(0.28, 0.28, 0.29), c(0.11, 0.11, 0.12)]
        case .aurora: return [c(0.35, 0.78, 0.98), c(0.69, 0.32, 0.87)]
        }
    }
}

enum PhotoStyle: String, CaseIterable, Identifiable {
    case blur, sharp, dim
    var id: String { rawValue }
    var title: String { switch self { case .blur: "Soft blur"; case .sharp: "Sharp"; case .dim: "Dimmed" } }
}

/// Both the app canvas and Home Screen widget draw from the same preset and photo settings.
struct SharedBackgroundCanvas: View {
    let preset: BackgroundPreset
    let style: PhotoStyle
    let photo: UIImage?
    @Environment(\.colorScheme) private var scheme
    private func blob(_ color: Color, _ size: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size).blur(radius: 50)
    }
    var body: some View {
        ZStack {
            (scheme == .dark ? Color.black : Color(.systemGroupedBackground))
            switch preset {
            case .system:
                if scheme != .dark {
                    GeometryReader { geo in
                        ZStack {
                            blob(Color(red: 0.61, green: 0.76, blue: 1.0), 320).position(x: 80, y: 100)
                            blob(Color(red: 0.81, green: 0.88, blue: 1.0), 300).position(x: geo.size.width - 30, y: 330)
                            blob(Color(red: 0.73, green: 0.83, blue: 1.0), 320).position(x: 100, y: geo.size.height - 120)
                        }.opacity(0.75)
                    }
                }
            case .photo:
                if let photo {
                    GeometryReader { geo in
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height).clipped()
                            .blur(radius: style == .blur ? 24 : 0)
                            .overlay(Color.black.opacity(style == .dim ? 0.35 : (scheme == .dark ? 0.25 : 0.05)))
                    }
                }
            default:
                if scheme != .dark || preset != .white {
                    LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(scheme == .dark && preset != .night ? 0.35 : 1)
                }
            }
        }
    }
}

/// Appearance data is shared independently of the score timeline, so changing wallpaper reloads immediately.
enum SharedBackgroundStore {
    static let syncKey = "background.widgetSync"
    static var syncEnabled: Bool { defaults.bool(forKey: syncKey) }
    static let presetKey = "background.preset"
    static let styleKey = "background.style"
    static var defaults: UserDefaults { UserDefaults(suiteName: "group.app.dayline.shared") ?? .standard }
    static var photoURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.dayline.shared")?.appending(path: "background.jpg")
    }
    static func preset() -> BackgroundPreset { BackgroundPreset(rawValue: defaults.string(forKey: presetKey) ?? "system") ?? .system }
    static func style() -> PhotoStyle { PhotoStyle(rawValue: defaults.string(forKey: styleKey) ?? "blur") ?? .blur }
    static func photo() -> UIImage? { photoURL.flatMap { UIImage(contentsOfFile: $0.path()) } }
}
