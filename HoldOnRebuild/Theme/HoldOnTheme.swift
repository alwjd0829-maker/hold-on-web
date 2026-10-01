import SwiftUI
import UIKit

enum HoldOnTheme {
    static let ink = Color(red: 0.09, green: 0.10, blue: 0.16)
    static let muted = Color(red: 0.49, green: 0.52, blue: 0.60)
    static let faint = Color(red: 0.63, green: 0.65, blue: 0.71)
    static let purple = Color(red: 0.40, green: 0.34, blue: 0.96)
    static let blue = Color(red: 0.34, green: 0.63, blue: 0.97)
    static let background = Color(red: 0.976, green: 0.982, blue: 1.0)
    static let surface = Color.white.opacity(0.72)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.68, green: 0.47, blue: 0.96),
                Color(red: 0.42, green: 0.35, blue: 0.95),
                Color(red: 0.34, green: 0.63, blue: 0.97)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var ambientBackground: some View {
        ZStack {
            background
            RadialGradient(
                colors: [blue.opacity(0.08), .clear],
                center: UnitPoint(x: 0.86, y: 0.05),
                startRadius: 0,
                endRadius: 240
            )
            RadialGradient(
                colors: [purple.opacity(0.06), .clear],
                center: UnitPoint(x: 0.08, y: 0.42),
                startRadius: 0,
                endRadius: 260
            )
        }
        .ignoresSafeArea()
    }
}

extension Font {
    static func holdOnTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}


final class HoldOnFontManager: ObservableObject {
    static let shared = HoldOnFontManager()

    @Published private(set) var isGowunReady: Bool

    static let regularPostScriptName = "GowunBatang-Regular"
    static let boldPostScriptName = "GowunBatang-Bold"

    private init() {
        isGowunReady = UIFont(name: Self.regularPostScriptName, size: 18) != nil
            && UIFont(name: Self.boldPostScriptName, size: 18) != nil
    }

    func refresh() {
        isGowunReady = UIFont(name: Self.regularPostScriptName, size: 18) != nil
            && UIFont(name: Self.boldPostScriptName, size: 18) != nil
    }

    func swiftUIFont(size: CGFloat, bold: Bool = false) -> Font {
        if isGowunReady {
            return .custom(bold ? Self.boldPostScriptName : Self.regularPostScriptName, size: size)
        }
        return .system(size: size, weight: bold ? .semibold : .regular, design: .serif)
    }

    func uiFont(size: CGFloat, bold: Bool = false) -> UIFont {
        if isGowunReady, let font = UIFont(name: bold ? Self.boldPostScriptName : Self.regularPostScriptName, size: size) {
            return font
        }
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular).fontDescriptor
        return UIFont(descriptor: base.withDesign(.serif) ?? base, size: size)
    }
}
