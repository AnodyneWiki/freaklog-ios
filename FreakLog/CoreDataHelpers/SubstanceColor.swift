import SwiftUI

// swiftlint:disable type_body_length file_length
enum SubstanceColor: String, CaseIterable, Identifiable, Codable, Comparable {
    static func < (lhs: SubstanceColor, rhs: SubstanceColor) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

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

    var id: SubstanceColor {
        self
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

    // Shown for a substance that has no color assigned
    static let fallback = SubstanceColor.purple

    // Colors not in `used`, in sort order
    static func unused(avoiding used: some Sequence<SubstanceColor>) -> [SubstanceColor] {
        let used = Set(used)
        return allCases.filter { !used.contains($0) }
    }

    // A color for something new: the first unused one, preferred colors first
    static func suggested(avoiding used: some Sequence<SubstanceColor>) -> SubstanceColor {
        unused(avoiding: used).first ?? allCases.randomElement() ?? .blue
    }

    // "FIRE_ENGINE_RED" → "fire engine red"
    var name: String {
        rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
    }

    // The basic system colors, declared first, are suggested before the others
    var isPreferred: Bool {
        sortIndex < 12
    }

    // Colors sort in declaration order
    private var sortIndex: Int {
        Self.sortIndices[self] ?? 0
    }

    private static let sortIndices = Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })
}

// swiftlint:enable type_body_length file_length
