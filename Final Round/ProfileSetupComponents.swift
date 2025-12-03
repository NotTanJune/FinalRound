import SwiftUI
import PhotosUI

// Temporary stand-in to unblock compilation until ProfileSetupViewModel.ExperienceLevel exists.
// If you later provide ProfileSetupViewModel with a nested ExperienceLevel, you can:
// 1) delete this enum, and
// 2) change ExperienceLevelSelector to use ProfileSetupViewModel.ExperienceLevel again.
enum ExperienceLevel: String, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case expert = "Expert"
}

// MARK: - Skill Tag Component
struct SkillTag: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : AppTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.primary : AppTheme.controlBackground)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(AppTheme.border, lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// NOTE: FlowLayout is already defined in MainTabView.swift.
// To avoid "Invalid redeclaration of 'FlowLayout'", we remove the duplicate here.

// MARK: - Experience Level Selector
struct ExperienceLevelSelector: View {
    @Binding var selectedLevel: ProfileSetupViewModel.ExperienceLevel?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Experience Level")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                
                if selectedLevel == nil {
                    Text("(Required)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.softRed.opacity(0.8))
                }
            }
            
            VStack(spacing: 8) {
                ForEach(ProfileSetupViewModel.ExperienceLevel.allCases, id: \.self) { level in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedLevel = level
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text(level.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(selectedLevel == level ? .white : AppTheme.textPrimary)
                            
                            Spacer()
                            
                            if selectedLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                            } else {
                                Image(systemName: "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.3))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedLevel == level ? AppTheme.primary : AppTheme.controlBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selectedLevel == level ? Color.clear : AppTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

// MARK: - Progress Indicator
struct StepProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= currentStep ? AppTheme.primary : AppTheme.border)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentStep)
    }
}

// MARK: - Profile Photo Picker
struct ProfilePhotoPicker: View {
    @Binding var selectedItem: PhotosPickerItem?
    let image: UIImage?
    let initials: String
    
    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ZStack {
                Circle()
                    .fill(AppTheme.lightGreen)
                    .frame(width: 140, height: 140)
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(AppTheme.border, lineWidth: 3)
                        )
                        .transition(.scale.combined(with: .opacity))
                } else {
                    VStack(spacing: 8) {
                        Text(initials)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .scaleEffect(selectedItem != nil ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedItem)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        SkillTag(text: "Swift", isSelected: true) {}
        SkillTag(text: "Leadership", isSelected: false) {}
        
        // Uses FlowLayout from MainTabView.swift
        FlowLayout(spacing: 8) {
            SkillTag(text: "Swift", isSelected: true) {}
            SkillTag(text: "Leadership", isSelected: false) {}
            SkillTag(text: "System Design", isSelected: true) {}
            SkillTag(text: "Communication", isSelected: false) {}
        }
        .padding()
        
        StepProgressIndicator(currentStep: 1, totalSteps: 3)
            .padding()
    }
}

