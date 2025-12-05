import SwiftUI

struct CategoryChip: View {
    let icon: String
    let text: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(AppTheme.font(size: 14, weight: .semibold))
            Text(text)
                .font(AppTheme.font(size: 14, weight: .semibold))
        }
        .foregroundStyle(isSelected ? Color.white : AppTheme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? AppTheme.primary : AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? AppTheme.primary : AppTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.0), radius: 8, x: 0, y: 4)
    }
}
