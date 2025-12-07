import SwiftUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ProfileEditViewModel
    
    init(profile: UserProfile) {
        _viewModel = StateObject(wrappedValue: ProfileEditViewModel(profile: profile))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        nameSection
                        roleSection
                        experienceLevelSection
                        skillsSection
                        locationSection
                    }
                    .padding(20)
                    .padding(.bottom, 80)
                }
                
                // Loading overlay
                if viewModel.isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .tint(.white)
                                Text("Saving changes...")
                                    .font(AppTheme.font(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.7))
                            )
                        }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .tint(AppTheme.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await viewModel.saveChanges(appState: appState)
                            if viewModel.saveError == nil {
                                dismiss()
                            }
                        }
                    }
                    .font(AppTheme.font(size: 16, weight: .semibold))
                    .tint(AppTheme.primary)
                    .disabled(!viewModel.canSave || viewModel.isSaving)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.saveError != nil },
                set: { if !$0 { viewModel.saveError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.saveError = nil
                }
            } message: {
                Text(viewModel.saveError ?? "Failed to save changes")
            }
        }
    }
    
    // MARK: - View Components
    
    private var nameSection: some View {
        EditSection(title: "Full Name", icon: "person.fill") {
            TextField("Your full name", text: $viewModel.fullName)
                .font(AppTheme.font(size: 16))
                .foregroundStyle(AppTheme.textPrimary)
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(12)
        }
    }
    
    private var roleSection: some View {
        EditSection(title: "Target Role", icon: "briefcase.fill") {
            TextField("e.g., Product Manager", text: $viewModel.targetRole)
                .font(AppTheme.font(size: 16))
                .foregroundStyle(AppTheme.textPrimary)
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(12)
                .onChange(of: viewModel.targetRole) { _, _ in
                    viewModel.validateTargetRole()
                }
            
            if let error = viewModel.roleValidationError {
                Text(error)
                    .font(AppTheme.font(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }
    
    private var experienceLevelSection: some View {
        EditSection(title: "Experience Level", icon: "chart.bar.fill") {
            VStack(spacing: 8) {
                ForEach(ProfileSetupViewModel.ExperienceLevel.allCases, id: \.self) { level in
                    experienceLevelButton(for: level)
                }
            }
        }
    }
    
    private func experienceLevelButton(for level: ProfileSetupViewModel.ExperienceLevel) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.experienceLevel = level
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack {
                Text(level.rawValue)
                    .font(AppTheme.font(size: 15, weight: .medium))
                    .foregroundStyle(viewModel.experienceLevel == level ? .white : AppTheme.textPrimary)
                
                Spacer()
                
                if viewModel.experienceLevel == level {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTheme.font(size: 20))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "circle")
                        .font(AppTheme.font(size: 20))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.3))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.experienceLevel == level ? AppTheme.primary : AppTheme.cardBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var skillsSection: some View {
        EditSection(title: "Skills", icon: "star.fill") {
            VStack(alignment: .leading, spacing: 12) {
                // Selected skills
                FlowLayout(spacing: 8) {
                    ForEach(Array(viewModel.selectedSkills), id: \.self) { skill in
                        SkillChip(skill: skill, isSelected: true) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.selectedSkills.remove(skill)
                            }
                        }
                    }
                }
                
                skillInputRow
                
                if let error = viewModel.customSkillValidationError {
                    Text(error)
                        .font(AppTheme.font(size: 12))
                        .foregroundStyle(.red)
                }
                
                Text("Select at least 3 skills")
                    .font(AppTheme.font(size: 12))
                    .foregroundStyle(viewModel.selectedSkills.count >= 3 ? AppTheme.primary : AppTheme.textSecondary)
            }
        }
    }
    
    private var skillInputRow: some View {
        HStack(spacing: 12) {
            TextField("Add a skill", text: $viewModel.customSkill)
                .font(AppTheme.font(size: 15))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(12)
                .background(AppTheme.cardBackground)
                .cornerRadius(8)
                .onChange(of: viewModel.customSkill) { _, newValue in
                    viewModel.validateCustomSkill()
                }
            
            Button {
                viewModel.addCustomSkill()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(AppTheme.font(size: 24))
                    .foregroundStyle(viewModel.canAddCustomSkill ? AppTheme.primary : AppTheme.textSecondary.opacity(0.3))
            }
            .disabled(!viewModel.canAddCustomSkill)
        }
    }
    
    private var locationSection: some View {
        EditSection(title: "Location", icon: "location.fill") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("City, Country", text: $viewModel.location)
                    .font(AppTheme.font(size: 16))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding()
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
                    .onChange(of: viewModel.location) { _, _ in
                        viewModel.validateLocation()
                    }
                
                if let error = viewModel.locationValidationError {
                    Text(error)
                        .font(AppTheme.font(size: 12))
                        .foregroundStyle(.red)
                }
                
                currencyPicker
            }
        }
    }
    
    private var currencyPicker: some View {
        HStack {
            Text("Preferred Currency")
                .font(AppTheme.font(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
            
            Spacer()
            
            Picker("Currency", selection: $viewModel.currency) {
                ForEach(CurrencyOption.allCases, id: \.self) { option in
                    Text("\(option.flag) \(option.code)").tag(option.code)
                }
            }
            .pickerStyle(.menu)
            .tint(AppTheme.primary)
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
}

struct EditSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(AppTheme.font(size: 14))
                    .foregroundStyle(AppTheme.primary)
                
                Text(title)
                    .font(AppTheme.font(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            
            content()
        }
    }
}

struct SkillChip: View {
    let skill: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(skill)
                    .font(AppTheme.font(size: 14, weight: .medium))
                
                if isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTheme.font(size: 14))
                }
            }
            .foregroundStyle(isSelected ? .white : AppTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? AppTheme.primary : AppTheme.cardBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

enum CurrencyOption: String, CaseIterable {
    case USD, EUR, GBP, INR, AUD, CAD, SGD, AED
    
    var flag: String {
        switch self {
        case .USD: return "🇺🇸"
        case .EUR: return "🇪🇺"
        case .GBP: return "🇬🇧"
        case .INR: return "🇮🇳"
        case .AUD: return "🇦🇺"
        case .CAD: return "🇨🇦"
        case .SGD: return "🇸🇬"
        case .AED: return "🇦🇪"
        }
    }
    
    var code: String {
        self.rawValue
    }
}

#Preview {
    ProfileEditView(profile: UserProfile(
        id: UUID(),
        fullName: "John Doe",
        targetRole: "Software Engineer",
        yearsOfExperience: "Mid Level",
        skills: ["Swift", "iOS", "SwiftUI"],
        avatarURL: nil,
        location: "San Francisco, USA",
        currency: "USD",
        updatedAt: Date()
    ))
}
