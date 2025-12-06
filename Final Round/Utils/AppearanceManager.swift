import SwiftUI
import Combine

// MARK: - Appearance Mode
enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Appearance Manager
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()
    
    private let appearanceKey = "userAppearanceMode"
    
    @Published var currentMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: appearanceKey)
        }
    }
    
    var colorScheme: ColorScheme? {
        currentMode.colorScheme
    }
    
    private init() {
        let savedValue = UserDefaults.standard.integer(forKey: appearanceKey)
        self.currentMode = AppearanceMode(rawValue: savedValue) ?? .system
    }
    
    func setMode(_ mode: AppearanceMode) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentMode = mode
        }
    }
}

// MARK: - View Modifier for Appearance
struct AppearanceModifier: ViewModifier {
    @ObservedObject var manager = AppearanceManager.shared
    
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(manager.colorScheme)
    }
}

extension View {
    func withAppearanceManager() -> some View {
        modifier(AppearanceModifier())
    }
}

// MARK: - Appearance Picker View
struct AppearancePicker: View {
    @ObservedObject var manager = AppearanceManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(AppTheme.font(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            
            HStack(spacing: 12) {
                ForEach(AppearanceMode.allCases) { mode in
                    AppearanceOptionButton(
                        mode: mode,
                        isSelected: manager.currentMode == mode
                    ) {
                        manager.setMode(mode)
                    }
                }
            }
        }
    }
}

struct AppearanceOptionButton: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AppTheme.primary.opacity(0.1) : AppTheme.cardBackground)
                        .frame(width: 60, height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isSelected ? AppTheme.primary : AppTheme.border, lineWidth: isSelected ? 2 : 1)
                        )
                    
                    Image(systemName: mode.icon)
                        .font(AppTheme.font(size: 24))
                        .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textSecondary)
                }
                
                Text(mode.title)
                    .font(AppTheme.font(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Full Appearance Settings Section
struct AppearanceSettingsSection: View {
    @ObservedObject var manager = AppearanceManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "paintbrush.fill")
                    .font(AppTheme.font(size: 20))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.lightGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                Text("Appearance")
                    .font(AppTheme.font(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Spacer()
            }
            
            Text("Choose how Final Round looks on your device")
                .font(AppTheme.font(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
            
            ZStack(alignment: .leading) {
                // Animated sliding pill indicator
                GeometryReader { geometry in
                    let buttonWidth = geometry.size.width / 3
                    let selectedIndex = CGFloat(manager.currentMode.rawValue)
                    
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.primary.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(AppTheme.primary.opacity(0.3), lineWidth: 1)
                        )
                        .frame(width: buttonWidth - 6, height: geometry.size.height - 6)
                        .offset(x: selectedIndex * buttonWidth + 3, y: 3)
                        .animation(.smooth(duration: 0.3, extraBounce: 0.1), value: manager.currentMode)
                }
                
                HStack(spacing: 0) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Button {
                            manager.currentMode = mode
                        } label: {
                            Image(systemName: mode.icon)
                                .font(AppTheme.font(size: 18, weight: .medium))
                                .foregroundStyle(manager.currentMode == mode ? AppTheme.primary : AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.elevatedSurface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.border.opacity(0.5), lineWidth: 0.5)
                    )
            )
            .shadow(color: AppTheme.shadowColor.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cardBackground)
                .shadow(color: AppTheme.shadowColor, radius: 10, x: 0, y: 4)
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        AppearancePicker()
        AppearanceSettingsSection()
    }
    .padding()
    .background(AppTheme.background)
    .withAppearanceManager()
}
