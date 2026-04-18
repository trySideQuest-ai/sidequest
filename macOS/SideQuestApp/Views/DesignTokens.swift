import SwiftUI
import AppKit

// MARK: - Design Tokens (Fantasy Parchment — authoritative design handoff)
//
// Mirrors design_handoff_sidequest_notification/Swift/DesignTokens.swift.
// Single source of truth for color, metric, and font tokens.

enum SQColor {
    // Ink (text)
    static let ink          = Color(hex: 0x1A1420) // near-black
    static let ink2         = Color(hex: 0x3A2F45) // subtitle
    static let ink3         = Color(hex: 0x6B6275) // hint/label

    // Parchment
    static let fantasyPaper = Color(hex: 0xF1EBE0)

    // Purple (inner ring, title, brand tag, dots)
    static let purple400    = Color(hex: 0x8B5CC4)
    static let purple600    = Color(hex: 0x5A2F96)
    static let purple700    = Color(hex: 0x3E1B73)
    static let purple800    = Color(hex: 0x2A0F52)

    // Gold (outer ring, pixel corners, timer bar, category tag, SIDE QUEST label)
    static let gold300      = Color(hex: 0xF0D886)
    static let gold400      = Color(hex: 0xE4C156)
    static let gold500      = Color(hex: 0xC9A32E)
    static let gold600      = Color(hex: 0x9E7D1A)

    // Keycap flash (accent pulse on hotkey fire)
    static let keycapFlash  = Color(hex: 0xC9A32E).opacity(0.4)
}

// MARK: - Metrics

enum SQMetric {
    static let cardWidth:       CGFloat = 336
    static let cardRadius:      CGFloat = 12
    static let ringInsetPurple: CGFloat = 3
    static let pixelCornerSize: CGFloat = 10
    static let pixelCornerPad:  CGFloat = 6

    static let cardPadTop:      CGFloat = 11
    static let cardPadRight:    CGFloat = 32
    static let cardPadBottom:   CGFloat = 11
    static let cardPadLeft:     CGFloat = 14
    static let contentGutter:   CGFloat = 6

    static let timerHeight:     CGFloat = 3
    static let timerRightInset: CGFloat = 13
    static let timerEdgeInset:  CGFloat = 5

    static let tagHeight:       CGFloat = 20
    static let keyCapSize:      CGFloat = 18
    static let closeSize:       CGFloat = 20

    // Stack + presenter tunables (preserved from prior implementation)
    static let defaultDuration: TimeInterval = 7.0
    static let stackGap:        CGFloat = 10
    static let stackMaxVisible: Int = 3
    static let topInset:        CGFloat = 20
    static let rightInset:      CGFloat = 20
}

// MARK: - Fonts (bundled TTFs registered via SQFontLoader)

enum SQFontName {
    static let interRegular  = "Inter-Regular"
    static let interMedium   = "Inter-Medium"
    static let interSemiBold = "Inter-SemiBold"
    static let pixel         = "PressStart2P-Regular"
}

enum SQFont {
    static func inter(_ size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium:
            name = SQFontName.interMedium
        case .semibold, .bold, .heavy, .black:
            name = SQFontName.interSemiBold
        default:
            name = SQFontName.interRegular
        }
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: swiftUIWeight(from: weight))
    }

    static func pixel(_ size: CGFloat) -> Font {
        if NSFont(name: SQFontName.pixel, size: size) != nil {
            return .custom(SQFontName.pixel, size: size)
        }
        return .system(size: size, weight: .regular, design: .monospaced)
    }

    private static func swiftUIWeight(from nsWeight: NSFont.Weight) -> Font.Weight {
        switch nsWeight {
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

// MARK: - Hex helper

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >>  8) & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - Font Loader (registers bundled TTFs with CoreText)

enum SQFontLoader {
    private static var didRun = false

    static func ensureLoaded() {
        guard !didRun else { return }
        didRun = true

        guard let resourceURL = Bundle.main.resourceURL else { return }
        let fontsDir = resourceURL.appendingPathComponent("Fonts", isDirectory: true)

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil) else {
            logFontLoadFailure("Fonts/ directory not found at \(fontsDir.path)")
            return
        }

        for url in items where url.pathExtension.lowercased() == "ttf" {
            var errorRef: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)
            if !registered {
                let desc = errorRef?.takeRetainedValue().localizedDescription ?? "unknown"
                logFontLoadFailure("Register failed for \(url.lastPathComponent): \(desc)")
            }
        }

        let required = [
            SQFontName.interRegular,
            SQFontName.interMedium,
            SQFontName.interSemiBold,
            SQFontName.pixel
        ]
        for name in required {
            if NSFont(name: name, size: 12) == nil {
                logFontLoadFailure("PostScript font not found after registration: \(name)")
            }
        }
    }

    private static func logFontLoadFailure(_ message: String) {
        ErrorHandler.logInfo("Font bundle: \(message)")
    }
}

// MARK: - Card shadow

struct SQShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color(hex: 0x231438, opacity: 0.28), radius: 15, x: 0, y: 10)
            .shadow(color: Color(hex: 0x231438, opacity: 0.22), radius: 30, x: 0, y: 24)
    }
}

extension View {
    func sqCardShadow() -> some View {
        self.modifier(SQShadow())
    }
}
