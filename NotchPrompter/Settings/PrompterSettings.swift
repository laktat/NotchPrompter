import SwiftUI
import AppKit

enum ScrollMode: String, Codable, CaseIterable, Identifiable {
    case fixed
    case voice
    case speech

    var id: String { rawValue }

    static let available: [ScrollMode] = allCases

    var title: String {
        switch self {
        case .fixed: "Fixed speed"
        case .voice: "Voice-activated"
        case .speech: "Word tracking"
        }
    }
}

/// sRGB colour that survives a JSON round-trip.
struct RGBAColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }
}

struct PrompterSettings: Codable, Equatable {
    // Appearance
    var width: Double = 460
    var height: Double = 130
    var fontSize: Double = 22
    var lineSpacing: Double = 4
    var textColor: RGBAColor = .white
    var backgroundOpacity: Double = 1.0

    // Scrolling
    var wordsPerMinute: Double = 140
    var countdownEnabled = true
    var countdownSeconds = 3
    var mode: ScrollMode = .fixed

    // Voice modes
    var voiceSensitivity: Double = 0.5
    var speechLocale = "cs-CZ"

    static let wpmRange: ClosedRange<Double> = 40...400

    init() {}

    // Decode field by field so settings files from older versions keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PrompterSettings()
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? d.width
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? d.height
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? d.lineSpacing
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? d.backgroundOpacity
        wordsPerMinute = try c.decodeIfPresent(Double.self, forKey: .wordsPerMinute) ?? d.wordsPerMinute
        countdownEnabled = try c.decodeIfPresent(Bool.self, forKey: .countdownEnabled) ?? d.countdownEnabled
        countdownSeconds = try c.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? d.countdownSeconds
        mode = try c.decodeIfPresent(ScrollMode.self, forKey: .mode) ?? d.mode
        voiceSensitivity = try c.decodeIfPresent(Double.self, forKey: .voiceSensitivity) ?? d.voiceSensitivity
        speechLocale = try c.decodeIfPresent(String.self, forKey: .speechLocale) ?? d.speechLocale
    }
}
