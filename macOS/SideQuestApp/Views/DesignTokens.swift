import SwiftUI
import AppKit

// MARK: - Colors (Fantasy Parchment Palette)

enum SQColor {
    // Parchment background and rings
    static let parchment       = Color(red: 0.945, green: 0.922, blue: 0.878) // #f1ebe0
    static let parchmentDeep   = Color(red: 0.933, green: 0.898, blue: 0.839) // outer ring tone
    static let parchmentEdge   = Color(red: 0.914, green: 0.874, blue: 0.800) // inner edge

    // Gold (timer bar, pixel corners, borders)
    static let gold            = Color(red: 0.769, green: 0.608, blue: 0.239) // #c49c3d
    static let goldBright      = Color(red: 0.871, green: 0.702, blue: 0.310) // #de9f4f bar glow
    static let goldDeep        = Color(red: 0.557, green: 0.412, blue: 0.153) // #8e6927 edge
    static let goldShadow      = Color(red: 0.380, green: 0.267, blue: 0.094) // deep ink

    // Deep purple / ink
    static let ink             = Color(red: 0.180, green: 0.102, blue: 0.255) // #2e1a41 body text
    static let inkSoft         = Color(red: 0.298, green: 0.204, blue: 0.373) // #4c345f subtitle
    static let inkMute         = Color(red: 0.451, green: 0.373, blue: 0.506) // #735f81 brand tag
    static let inkPale         = Color(red: 0.604, green: 0.541, blue: 0.639) // #9a8aa3 keycap border

    // Accents
    static let categoryChip    = Color(red: 0.180, green: 0.102, blue: 0.255) // same as ink
    static let categoryTxt     = Color(red: 0.957, green: 0.906, blue: 0.765) // cream on ink
    static let keycapBg        = Color.white.opacity(0.55)
    static let keycapFlash     = Color(red: 0.769, green: 0.608, blue: 0.239).opacity(0.4)
    static let noiseDot        = Color(red: 0.298, green: 0.204, blue: 0.373).opacity(0.04)
    static let separator       = Color(red: 0.298, green: 0.204, blue: 0.373).opacity(0.2)

    // Shadow tones
    static let shadowSoft      = Color(red: 0.180, green: 0.102, blue: 0.255).opacity(0.18)
    static let shadowHard      = Color(red: 0.180, green: 0.102, blue: 0.255).opacity(0.28)
}

// MARK: - Metrics

enum SQMetric {
    static let cardWidth:       CGFloat = 340
    static let cardPadding:     CGFloat = 18
    static let contentLead:     CGFloat = 20
    static let outerCorner:     CGFloat = 10
    static let innerCorner:     CGFloat = 6
    static let ringOuter:       CGFloat = 2
    static let ringInner:       CGFloat = 1
    static let ringGap:         CGFloat = 4
    static let pixelCorner:     CGFloat = 12
    static let pixelUnit:       CGFloat = 3 // pixel block size inside the L-bracket
    static let timerBarHeight:  CGFloat = 5
    static let keycapWidth:     CGFloat = 22
    static let keycapHeight:    CGFloat = 20
    static let keycapRadius:    CGFloat = 3
    static let defaultDuration: TimeInterval = 7.0
    static let stackGap:        CGFloat = 10
    static let stackMaxVisible: Int = 3
    static let topInset:        CGFloat = 20 // spacing from top-right of active screen
    static let rightInset:      CGFloat = 20
}

// MARK: - Fonts (Bundled)

enum SQFontName {
    static let interRegular    = "Inter-Regular"
    static let interMedium     = "Inter-Medium"
    static let interSemiBold   = "Inter-SemiBold"
    static let pixel           = "PressStart2P-Regular"
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
        if let _ = NSFont(name: name, size: size) {
            return .custom(name, size: size)
        }
        // Fallback: system font w/ matching weight
        return .system(size: size, weight: swiftUIWeight(from: weight))
    }

    static func pixel(_ size: CGFloat) -> Font {
        if let _ = NSFont(name: SQFontName.pixel, size: size) {
            return .custom(SQFontName.pixel, size: size)
        }
        // Fallback: monospaced system font
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

// MARK: - Font Loader

/// Registers bundled fonts with CoreText so `NSFont(name:size:)` can find them.
/// `ATSApplicationFontsPath = Fonts/` in Info.plist auto-registers at launch,
/// but we also do explicit CTFontManager registration as a belt-and-suspenders
/// pass for dev builds where the plist key may not take effect.
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
            let registered = CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                &errorRef
            )
            if !registered {
                let desc = errorRef?.takeRetainedValue().localizedDescription ?? "unknown"
                logFontLoadFailure("Register failed for \(url.lastPathComponent): \(desc)")
            }
        }

        // Validate PostScript names
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
        // Non-fatal per FONT-04 — card must still render with fallback
        ErrorHandler.logInfo("Font bundle: \(message)")
    }
}

// MARK: - Shadow Definition

struct SQShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: SQColor.shadowSoft, radius: 8, x: 0, y: 4)
    }
}

extension View {
    func sqCardShadow() -> some View {
        self.modifier(SQShadow())
    }
}
