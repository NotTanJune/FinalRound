import SwiftUI

enum AppTheme {
    // Primary Colors
    static let primary = Color(hex: "0F8A4A")
    static let lightGreen = Color(hex: "CFF9D8")
    
    // Accent Colors
    static let ratingYellow = Color(hex: "F7D44C")
    static let accentBlue = Color(hex: "4285F4")
    static let accentViolet = Color(hex: "A788FF")
    static let softRed = Color(hex: "E4574D")
    
    // Backgrounds
    static let background = Color(hex: "F7F7F7")
    static let cardBackground = Color(hex: "FFFFFF")
    static let border = Color(hex: "E4E4E4")
    
    // Text
    static let textPrimary = Color(hex: "1A1A1A")
    static let textSecondary = Color(hex: "6B6B6B")
    
    // Legacy support (mapping to new colors)
    static let accent = primary
    static let softAccent = lightGreen
    static let controlBackground = cardBackground
    static let separator = border
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers
struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
            )
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.primary)
                    .opacity(configuration.isPressed ? 0.9 : 1)
            )
            .shadow(color: AppTheme.primary.opacity(0.2), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(AppTheme.primary)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.lightGreen)
                    .opacity(configuration.isPressed ? 0.9 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct BottomActionBar<Content: View>: View {
    private let showsSeparator: Bool
    @ViewBuilder private let content: () -> Content

    init(showsSeparator: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.showsSeparator = showsSeparator
        self.content = content
    }

    var body: some View {
        VStack(spacing: 16) {
            if showsSeparator {
                Divider()
                    .overlay(AppTheme.border)
            }
            content()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background(AppTheme.cardBackground)
    }
}
