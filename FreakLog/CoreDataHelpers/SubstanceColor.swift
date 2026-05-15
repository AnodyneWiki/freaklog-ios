import SwiftUI

// swiftlint:disable type_body_length file_length
enum SubstanceColor: String, CaseIterable, Identifiable, Codable, Comparable {
    static func < (lhs: SubstanceColor, rhs: SubstanceColor) -> Bool {
        lhs.sortValue < rhs.sortValue
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
            return Color(red: 0.9294117647058824, green: 0.16862745098039217, blue: 0.16470588235294117).opacity(1)
        case .coral:
            return Color(red: 1.0, green: 0.5137254901960784, blue: 0.4745098039215686).opacity(1)
        case .tomato:
            return Color(red: 1.0, green: 0.38823529411764707, blue: 0.2784313725490196).opacity(1)
        case .cinnabar:
            return Color(red: 0.8901960784313725, green: 0.1411764705882353, blue: 0.0).opacity(1)
        case .rust:
            return Color(red: 0.7803921568627451, green: 0.3176470588235294, blue: 0.22745098039215686).opacity(1)
        case .orangeRed:
            return Color(red: 1.0, green: 0.27058823529411763, blue: 0.0).opacity(1)
        case .auburn:
            return Color(red: 0.8509803921568627, green: 0.3137254901960784, blue: 0.0).opacity(1)
        case .saddleBrown:
            return Color(red: 0.7490196078431373, green: 0.37254901960784315, blue: 0.09803921568627451).opacity(1)
        case .darkOrange:
            return Color(red: 1.0, green: 0.5490196078431373, blue: 0.0).opacity(1)
        case .darkGold:
            return Color(red: 0.6627450980392157, green: 0.40784313725490196, blue: 0.0).opacity(1)
        case .khaki:
            return Color(red: 0.796078431372549, green: 0.7176470588235294, blue: 0.5372549019607843).opacity(1)
        case .bronze:
            return Color(red: 0.6549019607843137, green: 0.4823529411764706, blue: 0.0).opacity(1)
        case .gold:
            return Color(red: 1.0, green: 0.8431372549019608, blue: 0.0).opacity(1)
        case .olive:
            return Color(red: 0.5529411764705883, green: 0.5254901960784314, blue: 0.0).opacity(1)
        case .oliveDrab:
            return Color(red: 0.6039215686274509, green: 0.6509803921568628, blue: 0.054901960784313725).opacity(1)
        case .darkOliveGreen:
            return Color(red: 0.4117647058823529, green: 0.5215686274509804, blue: 0.22745098039215686).opacity(1)
        case .mossGreen:
            return Color(red: 0.4, green: 0.611764705882353, blue: 0.20784313725490197).opacity(1)
        case .limeGreen:
            return Color(red: 0.0, green: 1.0, blue: 0.0).opacity(1)
        case .lime:
            return Color(red: 0.19607843137254902, green: 0.803921568627451, blue: 0.19607843137254902).opacity(1)
        case .forestGreen:
            return Color(red: 0.13333333333333333, green: 0.5450980392156862, blue: 0.13333333333333333).opacity(1)
        case .seaGreen:
            return Color(red: 0.1803921568627451, green: 0.5450980392156862, blue: 0.3411764705882353).opacity(1)
        case .jungleGreen:
            return Color(red: 0.011764705882352941, green: 0.5333333333333333, blue: 0.34509803921568627).opacity(1)
        case .lightSeaGreen:
            return Color(red: 0.12549019607843137, green: 0.6980392156862745, blue: 0.6666666666666666).opacity(1)
        case .darkTurquoise:
            return Color(red: 0.0, green: 0.807843137254902, blue: 0.8196078431372549).opacity(1)
        case .dodgerBlue:
            return Color(red: 0.11764705882352941, green: 0.5647058823529412, blue: 1.0).opacity(1)
        case .royalBlue:
            return Color(red: 0.2823529411764706, green: 0.4588235294117647, blue: 0.984313725490196).opacity(1)
        case .deepLavender:
            return Color(red: 0.5294117647058824, green: 0.3058823529411765, blue: 0.996078431372549).opacity(1)
        case .blueViolet:
            return Color(red: 0.6509803921568628, green: 0.28627450980392155, blue: 0.9882352941176471).opacity(1)
        case .darkViolet:
            return Color(red: 0.6352941176470588, green: 0.2980392156862745, blue: 0.8235294117647058).opacity(1)
        case .heliotrope:
            return Color(red: 0.592156862745098, green: 0.36470588235294116, blue: 0.6862745098039216).opacity(1)
        case .byzantium:
            return Color(red: 0.7450980392156863, green: 0.2196078431372549, blue: 0.9529411764705882).opacity(1)
        case .magenta:
            return Color(red: 1.0, green: 0.0, blue: 1.0).opacity(1)
        case .darkMagenta:
            return Color(red: 0.8509803921568627, green: 0.0, blue: 0.8509803921568627).opacity(1)
        case .fuchsia:
            return Color(red: 0.8392156862745098, green: 0.26666666666666666, blue: 0.5725490196078431).opacity(1)
        case .deepPink:
            return Color(red: 1.0, green: 0.0784313725490196, blue: 0.5764705882352941).opacity(1)
        case .grayishMagenta:
            return Color(red: 0.6313725490196078, green: 0.3764705882352941, blue: 0.5019607843137255).opacity(1)
        case .hotPink:
            return Color(red: 1.0, green: 0.4117647058823529, blue: 0.7058823529411765).opacity(1)
        case .jazzberryJam:
            return Color(red: 0.9019607843137255, green: 0.23137254901960785, blue: 0.47843137254901963).opacity(1)
        case .maroon:
            return Color(red: 0.7333333333333333, green: 0.3215686274509804, blue: 0.38823529411764707).opacity(1)
        }
    }

    var name: String {
        switch self {
        case .blue:
            return "blue"
        case .brown:
            return "brown"
        case .cyan:
            return "cyan"
        case .green:
            return "green"
        case .indigo:
            return "indigo"
        case .mint:
            return "mint"
        case .orange:
            return "orange"
        case .pink:
            return "pink"
        case .purple:
            return "purple"
        case .red:
            return "red"
        case .teal:
            return "teal"
        case .yellow:
            return "yellow"
        case .fireEngineRed:
            return "fire engine red"
        case .coral:
            return "coral"
        case .tomato:
            return "tomato"
        case .cinnabar:
            return "cinnabar"
        case .rust:
            return "rust"
        case .orangeRed:
            return "orange red"
        case .auburn:
            return "auburn"
        case .saddleBrown:
            return "saddle brown"
        case .darkOrange:
            return "dark orange"
        case .darkGold:
            return "dark gold"
        case .khaki:
            return "khaki"
        case .bronze:
            return "bronze"
        case .gold:
            return "gold"
        case .olive:
            return "olive"
        case .oliveDrab:
            return "olive drab"
        case .darkOliveGreen:
            return "dark olive green"
        case .mossGreen:
            return "moss green"
        case .limeGreen:
            return "lime green"
        case .lime:
            return "lime"
        case .forestGreen:
            return "forest green"
        case .seaGreen:
            return "sea green"
        case .jungleGreen:
            return "jungle green"
        case .lightSeaGreen:
            return "light sea green"
        case .darkTurquoise:
            return "dark turquoise"
        case .dodgerBlue:
            return "dodger blue"
        case .royalBlue:
            return "royal blue"
        case .deepLavender:
            return "deep lavender"
        case .blueViolet:
            return "blue violet"
        case .darkViolet:
            return "dark violet"
        case .heliotrope:
            return "heliotrope"
        case .byzantium:
            return "byzantium"
        case .magenta:
            return "magenta"
        case .darkMagenta:
            return "dark magenta"
        case .fuchsia:
            return "fuchsia"
        case .deepPink:
            return "deep pink"
        case .grayishMagenta:
            return "grayish magenta"
        case .hotPink:
            return "hot pink"
        case .jazzberryJam:
            return "jazzberry jam"
        case .maroon:
            return "maroon"
        }
    }

    var isPreferred: Bool {
        switch self {
        case .blue:
            return true
        case .brown:
            return true
        case .cyan:
            return true
        case .green:
            return true
        case .indigo:
            return true
        case .mint:
            return true
        case .orange:
            return true
        case .pink:
            return true
        case .purple:
            return true
        case .red:
            return true
        case .teal:
            return true
        case .yellow:
            return true
        case .fireEngineRed:
            return false
        case .coral:
            return false
        case .tomato:
            return false
        case .cinnabar:
            return false
        case .rust:
            return false
        case .orangeRed:
            return false
        case .auburn:
            return false
        case .saddleBrown:
            return false
        case .darkOrange:
            return false
        case .darkGold:
            return false
        case .khaki:
            return false
        case .bronze:
            return false
        case .gold:
            return false
        case .olive:
            return false
        case .oliveDrab:
            return false
        case .darkOliveGreen:
            return false
        case .mossGreen:
            return false
        case .limeGreen:
            return false
        case .lime:
            return false
        case .forestGreen:
            return false
        case .seaGreen:
            return false
        case .jungleGreen:
            return false
        case .lightSeaGreen:
            return false
        case .darkTurquoise:
            return false
        case .dodgerBlue:
            return false
        case .royalBlue:
            return false
        case .deepLavender:
            return false
        case .blueViolet:
            return false
        case .darkViolet:
            return false
        case .heliotrope:
            return false
        case .byzantium:
            return false
        case .magenta:
            return false
        case .darkMagenta:
            return false
        case .fuchsia:
            return false
        case .deepPink:
            return false
        case .grayishMagenta:
            return false
        case .hotPink:
            return false
        case .jazzberryJam:
            return false
        case .maroon:
            return false
        }
    }

    var sortValue: Int {
        switch self {
        case .blue:
            return 0
        case .brown:
            return 1
        case .cyan:
            return 2
        case .green:
            return 3
        case .indigo:
            return 4
        case .mint:
            return 5
        case .orange:
            return 6
        case .pink:
            return 7
        case .purple:
            return 8
        case .red:
            return 9
        case .teal:
            return 10
        case .yellow:
            return 11
        case .fireEngineRed:
            return 22
        case .coral:
            return 13
        case .tomato:
            return 14
        case .cinnabar:
            return 15
        case .rust:
            return 16
        case .orangeRed:
            return 17
        case .auburn:
            return 18
        case .saddleBrown:
            return 19
        case .darkOrange:
            return 20
        case .darkGold:
            return 21
        case .khaki:
            return 22
        case .bronze:
            return 23
        case .gold:
            return 24
        case .olive:
            return 25
        case .oliveDrab:
            return 26
        case .darkOliveGreen:
            return 27
        case .mossGreen:
            return 28
        case .limeGreen:
            return 29
        case .lime:
            return 30
        case .forestGreen:
            return 31
        case .seaGreen:
            return 32
        case .jungleGreen:
            return 33
        case .lightSeaGreen:
            return 34
        case .darkTurquoise:
            return 35
        case .dodgerBlue:
            return 36
        case .royalBlue:
            return 37
        case .deepLavender:
            return 38
        case .blueViolet:
            return 39
        case .darkViolet:
            return 40
        case .heliotrope:
            return 41
        case .byzantium:
            return 42
        case .magenta:
            return 43
        case .darkMagenta:
            return 44
        case .fuchsia:
            return 45
        case .deepPink:
            return 46
        case .grayishMagenta:
            return 47
        case .hotPink:
            return 48
        case .jazzberryJam:
            return 49
        case .maroon:
            return 50
        }
    }
}

// swiftlint:enable type_body_length file_length
