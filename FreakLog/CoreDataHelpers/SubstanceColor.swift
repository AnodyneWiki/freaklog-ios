import SwiftUI

// swiftlint:disable file_length

// MARK: - SubstanceColor

// A color stored as a hex code (#RRGGBB). The suggested palette holds the named colors of earlier versions:
// a code from it is drawn in that color's light and dark variants, any other code as it is.
struct SubstanceColor: Hashable, Identifiable, Sendable {
    // e.g. "#0A84FF"
    let hex: String

    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).uppercased()
        let code = digits.hasPrefix("#") ? String(digits.dropFirst()) : digits
        guard code.count == 6, code.allSatisfy(\.isHexDigit) else { return nil }
        self.hex = "#" + code
    }

    // A stored value: a hex code, or the name of a palette color in data from before hex codes
    init?(rawValue: String) {
        if let palette = PaletteColor(rawValue: rawValue.uppercased()) {
            self.init(palette)
        } else {
            self.init(hex: rawValue)
        }
    }

    // The closest code for a color, e.g. one chosen in the system color picker
    init(_ color: Color) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: nil)
        let component = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        hex = String(format: "#%02X%02X%02X", component(red), component(green), component(blue))
    }

    fileprivate init(_ palette: PaletteColor) {
        hex = palette.hex
    }

    var id: String {
        hex
    }

    // What is stored in CoreData
    var rawValue: String {
        hex
    }

    var swiftUIColor: Color {
        if let palette {
            return palette.swiftUIColor
        }
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    // "fire engine red" for a palette color, else the hex code
    var name: String {
        palette?.name ?? hex
    }

    // Journal files keep the names of palette colors, which the Android app reads
    var exportValue: String {
        palette?.rawValue ?? hex
    }

    var isInPalette: Bool {
        palette != nil
    }

    private var palette: PaletteColor? {
        PaletteColor.byHex[hex]
    }

    // The named colors of earlier versions
    static let palette = PaletteColor.allCases.map(SubstanceColor.init)

    // Shown for a substance that has no color assigned
    static let fallback = SubstanceColor.purple

    // A color for something new, as different as possible from the ones in use
    static func suggested(avoiding used: some Sequence<SubstanceColor>) -> SubstanceColor {
        distinctColors(from: used, count: 1).first ?? .blue
    }

    static let blue = SubstanceColor(PaletteColor.blue)
    static let brown = SubstanceColor(PaletteColor.brown)
    static let cyan = SubstanceColor(PaletteColor.cyan)
    static let green = SubstanceColor(PaletteColor.green)
    static let indigo = SubstanceColor(PaletteColor.indigo)
    static let mint = SubstanceColor(PaletteColor.mint)
    static let orange = SubstanceColor(PaletteColor.orange)
    static let pink = SubstanceColor(PaletteColor.pink)
    static let purple = SubstanceColor(PaletteColor.purple)
    static let red = SubstanceColor(PaletteColor.red)
    static let teal = SubstanceColor(PaletteColor.teal)
    static let yellow = SubstanceColor(PaletteColor.yellow)
    static let fireEngineRed = SubstanceColor(PaletteColor.fireEngineRed)
    static let coral = SubstanceColor(PaletteColor.coral)
    static let tomato = SubstanceColor(PaletteColor.tomato)
    static let cinnabar = SubstanceColor(PaletteColor.cinnabar)
    static let rust = SubstanceColor(PaletteColor.rust)
    static let orangeRed = SubstanceColor(PaletteColor.orangeRed)
    static let auburn = SubstanceColor(PaletteColor.auburn)
    static let saddleBrown = SubstanceColor(PaletteColor.saddleBrown)
    static let darkOrange = SubstanceColor(PaletteColor.darkOrange)
    static let darkGold = SubstanceColor(PaletteColor.darkGold)
    static let khaki = SubstanceColor(PaletteColor.khaki)
    static let bronze = SubstanceColor(PaletteColor.bronze)
    static let gold = SubstanceColor(PaletteColor.gold)
    static let olive = SubstanceColor(PaletteColor.olive)
    static let oliveDrab = SubstanceColor(PaletteColor.oliveDrab)
    static let darkOliveGreen = SubstanceColor(PaletteColor.darkOliveGreen)
    static let mossGreen = SubstanceColor(PaletteColor.mossGreen)
    static let limeGreen = SubstanceColor(PaletteColor.limeGreen)
    static let lime = SubstanceColor(PaletteColor.lime)
    static let forestGreen = SubstanceColor(PaletteColor.forestGreen)
    static let seaGreen = SubstanceColor(PaletteColor.seaGreen)
    static let jungleGreen = SubstanceColor(PaletteColor.jungleGreen)
    static let lightSeaGreen = SubstanceColor(PaletteColor.lightSeaGreen)
    static let darkTurquoise = SubstanceColor(PaletteColor.darkTurquoise)
    static let dodgerBlue = SubstanceColor(PaletteColor.dodgerBlue)
    static let royalBlue = SubstanceColor(PaletteColor.royalBlue)
    static let deepLavender = SubstanceColor(PaletteColor.deepLavender)
    static let blueViolet = SubstanceColor(PaletteColor.blueViolet)
    static let darkViolet = SubstanceColor(PaletteColor.darkViolet)
    static let heliotrope = SubstanceColor(PaletteColor.heliotrope)
    static let byzantium = SubstanceColor(PaletteColor.byzantium)
    static let magenta = SubstanceColor(PaletteColor.magenta)
    static let darkMagenta = SubstanceColor(PaletteColor.darkMagenta)
    static let fuchsia = SubstanceColor(PaletteColor.fuchsia)
    static let deepPink = SubstanceColor(PaletteColor.deepPink)
    static let grayishMagenta = SubstanceColor(PaletteColor.grayishMagenta)
    static let hotPink = SubstanceColor(PaletteColor.hotPink)
    static let jazzberryJam = SubstanceColor(PaletteColor.jazzberryJam)
    static let maroon = SubstanceColor(PaletteColor.maroon)
}

// MARK: Codable

// A single string: the hex code, or a palette color's name as journal files and older data have them
extension SubstanceColor: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = SubstanceColor(rawValue: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(text) is not a color")
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

// MARK: Suggestions

extension SubstanceColor {
    // Colors that are told apart easily from `used` and from each other, made on demand. Each one is the candidate
    // farthest from every color taken so far, measured in OKLab, where distances follow how different colors look.
    // The same colors in use give the same suggestions.
    static func distinctColors(from used: some Sequence<SubstanceColor>, count: Int) -> [SubstanceColor] {
        let candidates = SuggestionCandidate.all
        // The distance from each candidate to the closest color taken so far
        var distances = candidates.map { _ in Double.infinity }
        func take(_ lab: OKLab) {
            for index in candidates.indices {
                distances[index] = min(distances[index], candidates[index].lab.distance(to: lab))
            }
        }
        used.forEach { take($0.oklab) }
        var result: [SubstanceColor] = []
        for _ in 0 ..< count {
            // The first of equally far candidates, so suggestions start with the first candidate's hue
            guard let best = distances.indices.max(by: { distances[$0] < distances[$1] }) else { break }
            result.append(candidates[best].color)
            take(candidates[best].lab)
        }
        return result
    }

    // How different two colors look: 0 for the same, about 0.4 between blue and red
    func distance(to other: SubstanceColor) -> Double {
        oklab.distance(to: other.oklab)
    }

    fileprivate var oklab: OKLab {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return OKLab(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

// A color that can be suggested: vivid hues at a few mid lightness levels, which read on light and dark backgrounds
private struct SuggestionCandidate {
    let color: SubstanceColor
    let lab: OKLab

    static let all: [SuggestionCandidate] = {
        let lightnesses = [0.68, 0.6, 0.76]
        // Starting at blue, the first suggestion when nothing is in use
        let hues = (0 ..< 60).map { (250 + Double($0) * 6).truncatingRemainder(dividingBy: 360) }
        return lightnesses.flatMap { lightness in
            hues.map { hue in
                let color = OKLab.inGamut(lightness: lightness, chroma: 0.16, hue: hue)
                return SuggestionCandidate(color: color, lab: color.oklab)
            }
        }
    }()
}

// The OKLab color space (https://bottosson.github.io/posts/oklab/), from and to sRGB
private struct OKLab {
    let lightness: Double
    let a: Double
    let b: Double

    init(red: Double, green: Double, blue: Double) {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let (red, green, blue) = (linear(red), linear(green), linear(blue))
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    func distance(to other: OKLab) -> Double {
        let dl = lightness - other.lightness
        let da = a - other.a
        let db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    // The color of the lightness and hue (in degrees) with at most the given chroma that sRGB can show
    static func inGamut(lightness: Double, chroma: Double, hue: Double) -> SubstanceColor {
        var chroma = chroma
        while true {
            if let rgb = sRGB(lightness: lightness, chroma: chroma, hue: hue) {
                let component = { (value: Double) in Int((value * 255).rounded()) }
                return SubstanceColor(hex: String(format: "%02X%02X%02X", component(rgb.0), component(rgb.1), component(rgb.2)))
                    ?? .fallback
            }
            chroma -= 0.005
        }
    }

    private static func sRGB(lightness: Double, chroma: Double, hue: Double) -> (Double, Double, Double)? {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        let linear = [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ]
        guard linear.allSatisfy({ (-0.0001 ... 1.0001).contains($0) }) else { return nil }
        let encoded = linear.map { value in
            let value = min(max(value, 0), 1)
            return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
        }
        return (encoded[0], encoded[1], encoded[2])
    }
}

// MARK: - PaletteColor

// The named colors stored before hex codes, each with its light and dark variants
// swiftlint:disable type_body_length
private enum PaletteColor: String, CaseIterable {
    case blue = "BLUE"
    case brown = "BROWN"
    case cyan = "CYAN"
    case green = "GREEN"
    case indigo = "INDIGO"
    case mint = "MINT"
    case orange = "ORANGE"
    case pink = "PINK"
    case purple = "PURPLE"
    case red = "RED"
    case teal = "TEAL"
    case yellow = "YELLOW"
    case fireEngineRed = "FIRE_ENGINE_RED"
    case coral = "CORAL"
    case tomato = "TOMATO"
    case cinnabar = "CINNABAR"
    case rust = "RUST"
    case orangeRed = "ORANGE_RED"
    case auburn = "AUBURN"
    case saddleBrown = "SADDLE_BROWN"
    case darkOrange = "DARK_ORANGE"
    case darkGold = "DARK_GOLD"
    case khaki = "KHAKI"
    case bronze = "BRONZE"
    case gold = "GOLD"
    case olive = "OLIVE"
    case oliveDrab = "OLIVE_DRAB"
    case darkOliveGreen = "DARK_OLIVE_GREEN"
    case mossGreen = "MOSS_GREEN"
    case limeGreen = "LIME_GREEN"
    case lime = "LIME"
    case forestGreen = "FOREST_GREEN"
    case seaGreen = "SEA_GREEN"
    case jungleGreen = "JUNGLE_GREEN"
    case lightSeaGreen = "LIGHT_SEA_GREEN"
    case darkTurquoise = "DARK_TURQUOISE"
    case dodgerBlue = "DODGER_BLUE"
    case royalBlue = "ROYAL_BLUE"
    case deepLavender = "DEEP_LAVENDER"
    case blueViolet = "BLUE_VIOLET"
    case darkViolet = "DARK_VIOLET"
    case heliotrope = "HELIOTROPE"
    case byzantium = "BYZANTIUM"
    case magenta = "MAGENTA"
    case darkMagenta = "DARK_MAGENTA"
    case fuchsia = "FUCHSIA"
    case deepPink = "DEEP_PINK"
    case grayishMagenta = "GRAYISH_MAGENTA"
    case hotPink = "HOT_PINK"
    case jazzberryJam = "JAZZBERRY_JAM"
    case maroon = "MAROON"

    static let byHex = Dictionary(uniqueKeysWithValues: allCases.map { ($0.hex, $0) })

    // The dark variant's code
    var hex: String {
        switch self {
        case .blue: "#0A84FF"
        case .brown: "#AC8E68"
        case .cyan: "#64D2FF"
        case .green: "#30D158"
        case .indigo: "#5E5CE6"
        case .mint: "#63E6E2"
        case .orange: "#FF9F0A"
        case .pink: "#FF375F"
        case .purple: "#BF5AF2"
        case .red: "#FF453A"
        case .teal: "#40C8E0"
        case .yellow: "#FFD60A"
        case .fireEngineRed: "#ED2B2A"
        case .coral: "#FF8379"
        case .tomato: "#FF6347"
        case .cinnabar: "#E32400"
        case .rust: "#C7513A"
        case .orangeRed: "#FF4500"
        case .auburn: "#D95000"
        case .saddleBrown: "#BF5F19"
        case .darkOrange: "#FF8C00"
        case .darkGold: "#A96800"
        case .khaki: "#CBB789"
        case .bronze: "#A77B00"
        case .gold: "#FFD700"
        case .olive: "#8D8600"
        case .oliveDrab: "#9AA60E"
        case .darkOliveGreen: "#69853A"
        case .mossGreen: "#669C35"
        case .limeGreen: "#00FF00"
        case .lime: "#32CD32"
        case .forestGreen: "#228B22"
        case .seaGreen: "#2E8B57"
        case .jungleGreen: "#038858"
        case .lightSeaGreen: "#20B2AA"
        case .darkTurquoise: "#00CED1"
        case .dodgerBlue: "#1E90FF"
        case .royalBlue: "#4875FB"
        case .deepLavender: "#874EFE"
        case .blueViolet: "#A649FC"
        case .darkViolet: "#A24CD2"
        case .heliotrope: "#975DAF"
        case .byzantium: "#BE38F3"
        case .magenta: "#FF00FF"
        case .darkMagenta: "#D900D9"
        case .fuchsia: "#D64492"
        case .deepPink: "#FF1493"
        case .grayishMagenta: "#A16080"
        case .hotPink: "#FF69B4"
        case .jazzberryJam: "#E63B7A"
        case .maroon: "#BB5263"
        }
    }

    // "FIRE_ENGINE_RED" → "fire engine red"
    var name: String {
        rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
    }

    var swiftUIColor: Color {
        switch self {
        case .blue:
            return Color.blue
        case .green:
            return Color.green
        case .orange:
            return Color.orange
        case .pink:
            return Color.pink
        case .purple:
            return Color.purple
        case .red:
            return Color.red
        case .yellow:
            return Color.yellow
        case .brown:
            return Color.brown
        case .cyan:
            return Color.cyan
        case .indigo:
            return Color.indigo
        case .mint:
            return Color.mint
        case .teal:
            return Color.teal
        case .fireEngineRed:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.9294117647058824, green: 0.16862745098039217, blue: 0.16470588235294117, alpha: 1) :
                    UIColor(red: 0.9294117647058824, green: 0.054901960784313725, blue: 0.023529411764705882, alpha: 1)
            }
            )
        case .coral:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 1.0, green: 0.5137254901960784, blue: 0.4745098039215686, alpha: 1) :
                    UIColor(red: 0.7058823529411765, green: 0.3607843137254902, blue: 0.3333333333333333, alpha: 1)
            }
            )
        case .tomato:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 1.0, green: 0.38823529411764707, blue: 0.2784313725490196, alpha: 1) :
                    UIColor(red: 0.7058823529411765, green: 0.27058823529411763, blue: 0.19607843137254902, alpha: 1)
            }
            )
        case .cinnabar:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.8901960784313725, green: 0.1411764705882353, blue: 0.0, alpha: 1) :
                    UIColor(red: 0.8901960784313725, green: 0.1411764705882353, blue: 0.0, alpha: 1)
            }
            )
        case .rust:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.7803921568627451, green: 0.3176470588235294, blue: 0.22745098039215686, alpha: 1) :
                    UIColor(red: 0.7803921568627451, green: 0.3176470588235294, blue: 0.22745098039215686, alpha: 1)
            }
            )
        case .orangeRed:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 1.0, green: 0.27058823529411763, blue: 0.0, alpha: 1) :
                    UIColor(red: 0.803921568627451, green: 0.21568627450980393, blue: 0.0, alpha: 1)
            }
            )
        case .auburn:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.8509803921568627, green: 0.3137254901960784, blue: 0.0, alpha: 1) :
                    UIColor(red: 0.6784313725490196, green: 0.24313725490196078, blue: 0.0, alpha: 1)
            }
            )
        case .saddleBrown:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.7490196078431373, green: 0.37254901960784315, blue: 0.09803921568627451, alpha: 1) :
                    UIColor(red: 0.5450980392156862, green: 0.27058823529411763, blue: 0.07450980392156863, alpha: 1)
            }
            )
        case .darkOrange:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 1.0, green: 0.5490196078431373, blue: 0.0, alpha: 1) :
                    UIColor(red: 0.6078431372549019, green: 0.32941176470588235, blue: 0.0, alpha: 1)
            }
            )
        case .darkGold:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.6627450980392157, green: 0.40784313725490196, blue: 0.0, alpha: 1) :
                    UIColor(red: 0.6627450980392157, green: 0.40784313725490196, blue: 0.0, alpha: 1)
            }
            )
        case .khaki:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.796078431372549, green: 0.7176470588235294, blue: 0.5372549019607843, alpha: 1) :
                    UIColor(red: 0.5019607843137255, green: 0.4470588235294118, blue: 0.33725490196078434, alpha: 1)
            }
            )
        case .bronze:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.6549019607843137, green: 0.4823529411764706, blue: 0.0, alpha: 1) :
                    UIColor(red: 0.47058823529411764, green: 0.3411764705882353, blue: 0.0, alpha: 1)
            }
            )
        case .gold:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 1.0, green: 0.8431372549019608, blue: 0.0, alpha: 1) :
                    UIColor(red: 0.5098039215686274, green: 0.42745098039215684, blue: 0.0, alpha: 1)
            }
            )
        case .olive:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.5529411764705883, green: 0.5254901960784314, blue: 0.0, alpha: 1) :
                    UIColor(red: 0.4, green: 0.3803921568627451, blue: 0.0, alpha: 1)
            }
            )
        case .oliveDrab:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.6039215686274509, green: 0.6509803921568628, blue: 0.054901960784313725, alpha: 1) :
                    UIColor(red: 0.43529411764705883, green: 0.4627450980392157, blue: 0.03137254901960784, alpha: 1)
            }
            )
        case .darkOliveGreen:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.4117647058823529, green: 0.5215686274509804, blue: 0.22745098039215686, alpha: 1) :
                    UIColor(red: 0.3333333333333333, green: 0.4196078431372549, blue: 0.1843137254901961, alpha: 1)
            }
            )
        case .mossGreen:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.4, green: 0.611764705882353, blue: 0.20784313725490197, alpha: 1) :
                    UIColor(red: 0.30980392156862746, green: 0.47843137254901963, blue: 0.1568627450980392, alpha: 1)
            }
            )
        case .limeGreen:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1) :
                    UIColor(red: 0.0, green: 0.5098039215686274, blue: 0.0, alpha: 1)
            }
            )
        case .lime:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.19607843137254902, green: 0.803921568627451, blue: 0.19607843137254902, alpha: 1) :
                    UIColor(red: 0.12549019607843137, green: 0.5098039215686274, blue: 0.12549019607843137, alpha: 1)
            }
            )
        case .forestGreen:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.13333333333333333, green: 0.5450980392156862, blue: 0.13333333333333333, alpha: 1) :
                    UIColor(red: 0.10980392156862745, green: 0.4470588235294118, blue: 0.10980392156862745, alpha: 1)
            }
            )
        case .seaGreen:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.1803921568627451, green: 0.5450980392156862, blue: 0.3411764705882353, alpha: 1) :
                    UIColor(red: 0.14901960784313725, green: 0.4470588235294118, blue: 0.2784313725490196, alpha: 1)
            }
            )
        case .jungleGreen:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.011764705882352941, green: 0.5333333333333333, blue: 0.34509803921568627, alpha: 1) :
                    UIColor(red: 0.011764705882352941, green: 0.5333333333333333, blue: 0.34509803921568627, alpha: 1)
            }
            )
        case .lightSeaGreen:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.12549019607843137, green: 0.6980392156862745, blue: 0.6666666666666666, alpha: 1) :
                    UIColor(red: 0.08627450980392157, green: 0.5019607843137255, blue: 0.47843137254901963, alpha: 1)
            }
            )
        case .darkTurquoise:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.0, green: 0.807843137254902, blue: 0.8196078431372549, alpha: 1) :
                    UIColor(red: 0.0, green: 0.5137254901960784, blue: 0.5254901960784314, alpha: 1)
            }
            )
        case .dodgerBlue:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.11764705882352941, green: 0.5647058823529412, blue: 1.0, alpha: 1) :
                    UIColor(red: 0.09411764705882353, green: 0.4549019607843137, blue: 0.803921568627451, alpha: 1)
            }
            )
        case .royalBlue:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.2823529411764706, green: 0.4588235294117647, blue: 0.984313725490196, alpha: 1) :
                    UIColor(red: 0.2549019607843137, green: 0.4117647058823529, blue: 0.8823529411764706, alpha: 1)
            }
            )
        case .deepLavender:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.5294117647058824, green: 0.3058823529411765, blue: 0.996078431372549, alpha: 1) :
                    UIColor(red: 0.5294117647058824, green: 0.3058823529411765, blue: 0.996078431372549, alpha: 1)
            }
            )
        case .blueViolet:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.6509803921568628, green: 0.28627450980392155, blue: 0.9882352941176471, alpha: 1) :
                    UIColor(red: 0.5411764705882353, green: 0.16862745098039217, blue: 0.8862745098039215, alpha: 1)
            }
            )
        case .darkViolet:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.6352941176470588, green: 0.2980392156862745, blue: 0.8235294117647058, alpha: 1) :
                    UIColor(red: 0.5803921568627451, green: 0.0, blue: 0.8274509803921568, alpha: 1)
            }
            )
        case .heliotrope:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.592156862745098, green: 0.36470588235294116, blue: 0.6862745098039216, alpha: 1) :
                    UIColor(red: 0.592156862745098, green: 0.36470588235294116, blue: 0.6862745098039216, alpha: 1)
            }
            )
        case .byzantium:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.7450980392156863, green: 0.2196078431372549, blue: 0.9529411764705882, alpha: 1) :
                    UIColor(red: 0.6, green: 0.1607843137254902, blue: 0.7411764705882353, alpha: 1)
            }
            )
        case .magenta:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1) :
                    UIColor(red: 0.803921568627451, green: 0.0, blue: 0.803921568627451, alpha: 1)
            }
            )
        case .darkMagenta:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.8509803921568627, green: 0.0, blue: 0.8509803921568627, alpha: 1) :
                    UIColor(red: 0.5450980392156862, green: 0.0, blue: 0.5450980392156862, alpha: 1)
            }
            )
        case .fuchsia:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.8392156862745098, green: 0.26666666666666666, blue: 0.5725490196078431, alpha: 1) :
                    UIColor(red: 0.7411764705882353, green: 0.23529411764705882, blue: 0.5058823529411764, alpha: 1)
            }
            )
        case .deepPink:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 1.0, green: 0.0784313725490196, blue: 0.5764705882352941, alpha: 1) :
                    UIColor(red: 0.803921568627451, green: 0.06274509803921569, blue: 0.4588235294117647, alpha: 1)
            }
            )
        case .grayishMagenta:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.6313725490196078, green: 0.3764705882352941, blue: 0.5019607843137255, alpha: 1) :
                    UIColor(red: 0.6313725490196078, green: 0.3764705882352941, blue: 0.5019607843137255, alpha: 1)
            }
            )
        case .hotPink:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 1.0, green: 0.4117647058823529, blue: 0.7058823529411765, alpha: 1) :
                    UIColor(red: 0.7058823529411765, green: 0.2901960784313726, blue: 0.49411764705882355, alpha: 1)
            }
            )
        case .jazzberryJam:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.9019607843137255, green: 0.23137254901960785, blue: 0.47843137254901963, alpha: 1) :
                    UIColor(red: 0.7254901960784313, green: 0.17647058823529413, blue: 0.36470588235294116, alpha: 1)
            }
            )
        case .maroon:
            return Color(uiColor: UIColor {
                $0.userInterfaceStyle == .dark ?
                    UIColor(red: 0.7333333333333333, green: 0.3215686274509804, blue: 0.38823529411764707, alpha: 1) :
                    UIColor(red: 0.7450980392156863, green: 0.19215686274509805, blue: 0.26666666666666666, alpha: 1)
            }
            )
        }
    }
}

// swiftlint:enable type_body_length file_length
