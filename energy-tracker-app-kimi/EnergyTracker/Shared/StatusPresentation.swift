import SwiftUI

enum DisplayStatus: String, CaseIterable, Sendable {
    case withinrange
    case belowbaseline
    case trending

    var label: String {
        switch self {
        case .withinrange: String(localized: "Within range")
        case .belowbaseline: String(localized: "Below baseline")
        case .trending: String(localized: "Trending")
        }
    }

    var symbol: String {
        switch self {
        case .withinrange: "checkmark.circle"
        case .belowbaseline: "arrow.down.circle"
        case .trending: "arrow.up.right.circle"
        }
    }

    var color: Color {
        switch self {
        case .withinrange: Color.dynamic(light: 0x6B8656, dark: 0x9FBB8A)
        case .belowbaseline: Color.dynamic(light: 0x2F9E52, dark: 0x4FCA72)
        case .trending: Color.dynamic(light: 0xB87A1E, dark: 0xE2A542)
        }
    }

    var labelColor: Color {
        switch self {
        case .withinrange: Color.dynamic(light: 0x41603A, dark: 0xC7DCBB)
        case .belowbaseline: Color.dynamic(light: 0x1F7038, dark: 0xB9EFC7)
        case .trending: Color.dynamic(light: 0x8A5A14, dark: 0xF5CE93)
        }
    }
}

struct StatusBadge: View {
    let status: DisplayStatus
    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(status.labelColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(status.color.opacity(0.15), in: Capsule())
            .accessibilityLabel(status.label)
    }
}

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct GlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.16)))
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCardModifier()) }
}
