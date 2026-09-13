import SwiftUI
import UIKit

/// Shared colors for the child's screening room and the parent's workspace.
/// Keep the system appearance, text scaling and native controls intact.
enum AppTheme {
    static let canvas = color(0xF6F4ED, dark: 0x171F1B)
    static let surface = color(0xFFFEFA, dark: 0x242F29)
    static let ink = color(0x223F34, dark: 0xF0F4EE)
    static let muted = color(0x586B60, dark: 0xB9C7BC)
    static let accent = color(0x2D6651, dark: 0xA3D2B3)
    static let actionFill = color(0x2D6651, dark: 0xA3D2B3)
    static let actionText = color(0xFFFFFF, dark: 0x183827)
    static let sage = color(0xE6EFE7, dark: 0x2B4335)
    static let wheat = color(0xF4E9CE, dark: 0x453D2B)
    static let ochre = color(0x79572D, dark: 0xE9CB96)
    static let line = color(0xDAE1D8, dark: 0x425448)
    static let warning = color(0x93542C, dark: 0xEFBD87)

    private static func color(_ light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct SpringPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 24)
            .frame(minHeight: 60)
            .foregroundStyle(AppTheme.actionText)
            .background(AppTheme.actionFill, in: RoundedRectangle(cornerRadius: 18))
            .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct SpringPortrait: View {
    var body: some View {
        Image("PastoralPortrait")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension View {
    func springList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)
            .listSectionSpacing(24)
            .environment(\.defaultMinListRowHeight, 52)
    }

    func springSurface() -> some View {
        self
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppTheme.line.opacity(0.65), lineWidth: 1)
            }
    }
}
