import SwiftUI

enum AppTheme {
    // MARK: - Adaptive Colors (Light/Dark Mode)
    
    // Primary Brand Colors (consistent across modes)
    static let primary = Color(hex: "0F8A4A")
    
    // Adaptive Background Colors
    static var background: Color { Color("BackgroundPrimary") }
    static var cardBackground: Color { Color("CardBackground") }
    static var elevatedSurface: Color { Color("ElevatedSurface") }
    static var inputBackground: Color { Color("InputBackground") }
    
    // Adaptive Text Colors
    static var textPrimary: Color { Color("TextPrimary") }
    static var textSecondary: Color { Color("TextSecondary") }
    static var textTertiary: Color { Color("TextTertiary") }
    
    // Adaptive UI Colors
    static var border: Color { Color("Border") }
    static var lightGreen: Color { Color("LightGreen") }
    static var shadowColor: Color { Color("ShadowColor") }
    
    // Accent Colors (slightly adjusted for dark mode vibrancy)
    static let ratingYellow = Color(hex: "F7D44C")
    static let accentBlue = Color(hex: "4285F4")
    static let accentViolet = Color(hex: "A788FF")
    static let softRed = Color(hex: "E4574D")
    
    // Status Colors
    static let success = Color(hex: "34C759")
    static let warning = Color(hex: "FF9500")
    static let error = Color(hex: "FF3B30")
    
    // Legacy support (mapping to new colors)
    static var accent: Color { primary }
    static var softAccent: Color { lightGreen }
    static var controlBackground: Color { cardBackground }
    static var separator: Color { border }
    
    // MARK: - Typography (Nohemi Font Family)
    
    /// Font family name prefix
    private static let fontFamily = "Nohemi"
    
    /// Maps Font.Weight to the appropriate Nohemi font variant
    private static func fontName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin:
            return "\(fontFamily)-Thin"
        case .light:
            return "\(fontFamily)-Light"
        case .regular:
            return "\(fontFamily)-Regular"
        case .medium:
            return "\(fontFamily)-Medium"
        case .semibold:
            return "\(fontFamily)-SemiBold"
        case .bold:
            return "\(fontFamily)-Bold"
        case .heavy:
            return "\(fontFamily)-ExtraBold"
        case .black:
            return "\(fontFamily)-Black"
        default:
            return "\(fontFamily)-Regular"
        }
    }
    
    /// Creates a Nohemi font with the specified size (regular weight)
    static func font(size: CGFloat) -> Font {
        .custom(fontName(for: .regular), size: size)
    }
    
    /// Creates a Nohemi font with size and weight
    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        .custom(fontName(for: weight), size: size)
    }
    
    // MARK: - Semantic Font Styles
    static let largeTitle = Font.custom(fontName(for: .bold), size: 34)
    static let title = Font.custom(fontName(for: .bold), size: 28)
    static let title2 = Font.custom(fontName(for: .semibold), size: 24)
    static let title3 = Font.custom(fontName(for: .semibold), size: 20)
    static let headline = Font.custom(fontName(for: .semibold), size: 18)
    static let body = Font.custom(fontName(for: .regular), size: 16)
    static let callout = Font.custom(fontName(for: .regular), size: 15)
    static let subheadline = Font.custom(fontName(for: .regular), size: 14)
    static let footnote = Font.custom(fontName(for: .regular), size: 13)
    static let caption = Font.custom(fontName(for: .regular), size: 12)
    static let caption2 = Font.custom(fontName(for: .regular), size: 10)
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
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .shadow(color: AppTheme.shadowColor, radius: 10, x: 0, y: 4)
            )
            .overlay(
                // Subtle border in dark mode for better card definition
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? AppTheme.border : Color.clear, lineWidth: 1)
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
            .font(AppTheme.font(size: 16, weight: .semibold))
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
            .font(AppTheme.font(size: 16, weight: .semibold))
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

    init(showsSeparator: Bool = false, @ViewBuilder content: @escaping () -> Content) {
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
