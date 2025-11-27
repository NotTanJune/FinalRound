import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ProfileSetupViewModel()
    
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress Indicator
                StepProgressIndicator(
                    currentStep: stepNumber,
                    totalSteps: 4
                )
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
                
                // Content
                ZStack {
                    Group {
                        switch viewModel.currentStep {
                        case .identity:
                            IdentityStepView(viewModel: viewModel)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        case .skills:
                            SkillsStepView(viewModel: viewModel)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        case .location:
                            LocationStepView(viewModel: viewModel)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        case .photo:
                            PhotoStepView(viewModel: viewModel)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        case .complete:
                            CompleteStepView()
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: viewModel.selectedPhotoItem) { _, _ in
            Task {
                await viewModel.loadPhoto()
            }
        }
        .onChange(of: viewModel.currentStep) { _, newStep in
            if newStep == .complete {
                // Slight delay for animation to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appState.hasCompletedOnboarding = true
                    appState.hasProfileSetup = true
                }
            }
        }
    }
    
    private var stepNumber: Int {
        switch viewModel.currentStep {
        case .identity: return 0
        case .skills: return 1
        case .location: return 2
        case .photo: return 3
        case .complete: return 3
        }
    }
}

// MARK: - Identity Step
struct IdentityStepView: View {
    @ObservedObject var viewModel: ProfileSetupViewModel
    @FocusState private var focusedField: Field?
    
    enum Field {
        case role
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.bottom, 8)
                    
                    Text("Let's tailor your interview prep")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text("Tell us about your career goals so we can personalize your experience")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                
                // Form
                VStack(spacing: 24) {
                    // Target Role
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Role")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        
                        TextField("", text: $viewModel.targetRole, prompt: Text("Product Manager"))
                            .textFieldStyle(CustomTextFieldStyle())
                            .textContentType(.jobTitle)
                            .focused($focusedField, equals: .role)
                    }
                    
                    // Experience Level
                    ExperienceLevelSelector(selectedLevel: $viewModel.experienceLevel)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.cardBackground)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                )
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 120)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar(showsSeparator: false) {
                Button {
                    focusedField = nil
                    viewModel.goToNextStep()
                } label: {
                    Text("Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canProceedFromIdentity)
                .opacity(viewModel.canProceedFromIdentity ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.2), value: viewModel.canProceedFromIdentity)
            }
        }
        .onTapGesture {
            focusedField = nil
        }
    }
}

// MARK: - Skills Step
struct SkillsStepView: View {
    @ObservedObject var viewModel: ProfileSetupViewModel
    @FocusState private var isCustomSkillFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.primary)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.bottom, 8)
                    
                    Text(viewModel.isLoadingSkills ? "Analyzing industry requirements..." : "Select your skills")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text("Choose at least 3 skills that best represent your expertise")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                
                if viewModel.isLoadingSkills {
                    LoadingView(message: "Generating personalized skills...", size: 120)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    // Skills Grid
                    VStack(spacing: 24) {
                        FlowLayout(spacing: 10) {
                            ForEach(viewModel.generatedSkills, id: \.self) { skill in
                                SkillTag(
                                    text: skill,
                                    isSelected: viewModel.selectedSkills.contains(skill)
                                ) {
                                    viewModel.toggleSkill(skill)
                                }
                            }
                        }
                        
                        // Add Custom Skill
                        HStack(spacing: 12) {
                            TextField("", text: $viewModel.customSkill, prompt: Text("Add custom skill..."))
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(AppTheme.controlBackground)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .strokeBorder(AppTheme.border, lineWidth: 1)
                                        )
                                )
                                .focused($isCustomSkillFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    viewModel.addCustomSkill()
                                }
                            
                            Button {
                                viewModel.addCustomSkill()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(AppTheme.primary)
                            }
                            .disabled(viewModel.customSkill.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(viewModel.customSkill.trimmingCharacters(in: .whitespaces).isEmpty ? 0.3 : 1)
                        }
                        
                        // Selection Counter
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(viewModel.selectedSkills.count >= 3 ? AppTheme.primary : AppTheme.textSecondary)
                            
                            Text("\(viewModel.selectedSkills.count) skills selected")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                            
                            Spacer()
                        }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppTheme.cardBackground)
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                    )
                }
                
                if let error = viewModel.skillsError {
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.softRed)
                        .padding(.horizontal, 16)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 120)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar(showsSeparator: false) {
                HStack(spacing: 12) {
                    Button {
                        viewModel.goToPreviousStep()
                    } label: {
                        Text("Back")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    
                    Button {
                        isCustomSkillFocused = false
                        viewModel.goToNextStep()
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!viewModel.canProceedFromSkills)
                    .opacity(viewModel.canProceedFromSkills ? 1 : 0.5)
                }
            }
        }
        .onTapGesture {
            isCustomSkillFocused = false
        }
    }
}

// MARK: - Photo Step
struct PhotoStepView: View {
    @ObservedObject var viewModel: ProfileSetupViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.bottom, 8)
                    
                    Text("Put a face to the name")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text("Add a profile photo to personalize your experience")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                
                // Photo Picker
                VStack(spacing: 16) {
                    ProfilePhotoPicker(
                        selectedItem: $viewModel.selectedPhotoItem,
                        image: viewModel.profileImage,
                        initials: String(viewModel.fullName.prefix(1))
                    )
                    
                    Text(viewModel.profileImage == nil ? "Tap to add photo" : "Tap to change photo")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.cardBackground)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                )
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 120)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar(showsSeparator: false) {
                VStack(spacing: 12) {
                    Button {
                        viewModel.goToNextStep()
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Complete Setup")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isSaving)
                    
                    Button {
                        viewModel.skipPhoto()
                    } label: {
                        Text("Skip for now")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .alert("Error", isPresented: .constant(viewModel.saveError != nil)) {
            Button("OK") {
                viewModel.saveError = nil
            }
        } message: {
            if let error = viewModel.saveError {
                Text(error)
            }
        }
    }
}

// MARK: - Location Step
struct LocationStepView: View {
    @ObservedObject var viewModel: ProfileSetupViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Where are you located?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text("We'll show you relevant jobs in your area with local currency")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)
                
                VStack(alignment: .leading, spacing: 16) {
                    // Auto-detect location button
                    Button {
                        Task {
                            await viewModel.requestDeviceLocation()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if viewModel.isLoadingLocation {
                                ProgressView()
                                    .tint(AppTheme.primary)
                            } else {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(AppTheme.primary)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Use Current Location")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppTheme.textPrimary)
                                
                                Text("Automatically detect your location")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(16)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel.isLoadingLocation)
                    
                    HStack {
                        Rectangle()
                            .fill(AppTheme.border)
                            .frame(height: 1)
                        
                        Text("OR")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 12)
                        
                        Rectangle()
                            .fill(AppTheme.border)
                            .frame(height: 1)
                    }
                    .padding(.vertical, 8)
                    
                    // Manual location input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter Location")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        
                        TextField("e.g., San Francisco, USA", text: $viewModel.location)
                            .textFieldStyle(CustomTextFieldStyle())
                            .autocorrectionDisabled()
                            .onChange(of: viewModel.location) { _, _ in
                                viewModel.updateCurrencyFromLocation()
                            }
                    }
                    
                    // Currency display
                    if !viewModel.location.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Detected Currency")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                            
                            HStack {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(AppTheme.primary)
                                
                                Text(viewModel.currency)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppTheme.textPrimary)
                                
                                Spacer()
                            }
                            .padding(16)
                            .background(AppTheme.lightGreen.opacity(0.3))
                            .cornerRadius(12)
                        }
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    viewModel.goToNextStep()
                } label: {
                    Text("Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canProceedFromLocation)
                
                Button {
                    viewModel.goToPreviousStep()
                } label: {
                    Text("Back")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

// MARK: - Complete Step
struct CompleteStepView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(AppTheme.primary)
                    .symbolEffect(.bounce, value: true)
                
                VStack(spacing: 12) {
                    Text("All Set!")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text("Your profile is ready. Let's start practicing!")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Custom Text Field Style
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.controlBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.border, lineWidth: 1)
                    )
            )
    }
}

#Preview {
    ProfileSetupView()
        .environmentObject(AppState())
}
