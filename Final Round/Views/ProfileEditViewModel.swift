import SwiftUI
import Combine

@MainActor
class ProfileEditViewModel: ObservableObject {
    private let originalProfile: UserProfile
    
    @Published var fullName: String
    @Published var targetRole: String
    @Published var experienceLevel: ProfileSetupViewModel.ExperienceLevel?
    @Published var selectedSkills: Set<String>
    @Published var customSkill = ""
    @Published var location: String
    @Published var currency: String
    
    @Published var isSaving = false
    @Published var saveError: String?
    
    // Validation errors
    @Published var roleValidationError: String?
    @Published var locationValidationError: String?
    @Published var customSkillValidationError: String?
    
    init(profile: UserProfile) {
        self.originalProfile = profile
        self.fullName = profile.fullName
        self.targetRole = profile.targetRole
        self.experienceLevel = ProfileSetupViewModel.ExperienceLevel(storedValue: profile.yearsOfExperience)
        self.selectedSkills = Set(profile.skills)
        self.location = profile.location ?? ""
        self.currency = profile.currency ?? "USD"
    }
    
    var canSave: Bool {
        let trimmedName = fullName.trimmingCharacters(in: .whitespaces)
        let trimmedRole = targetRole.trimmingCharacters(in: .whitespaces)
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        
        return !trimmedName.isEmpty &&
               !trimmedRole.isEmpty &&
               trimmedRole.count <= InputSanitizer.Limits.role &&
               roleValidationError == nil &&
               experienceLevel != nil &&
               selectedSkills.count >= 3 &&
               selectedSkills.count <= InputSanitizer.Limits.skillCount &&
               !trimmedLocation.isEmpty &&
               trimmedLocation.count <= InputSanitizer.Limits.location &&
               locationValidationError == nil &&
               hasChanges
    }
    
    var hasChanges: Bool {
        let trimmedName = fullName.trimmingCharacters(in: .whitespaces)
        let trimmedRole = targetRole.trimmingCharacters(in: .whitespaces)
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        
        return trimmedName != originalProfile.fullName ||
               trimmedRole != originalProfile.targetRole ||
               experienceLevel?.rawValue != originalProfile.yearsOfExperience ||
               selectedSkills != Set(originalProfile.skills) ||
               trimmedLocation != (originalProfile.location ?? "") ||
               currency != (originalProfile.currency ?? "USD")
    }
    
    var canAddCustomSkill: Bool {
        let trimmed = customSkill.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty &&
               customSkillValidationError == nil &&
               selectedSkills.count < InputSanitizer.Limits.skillCount &&
               !selectedSkills.contains(trimmed)
    }
    
    // MARK: - Validation
    
    func validateTargetRole() {
        let trimmed = targetRole.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            roleValidationError = nil
        } else if trimmed.count > InputSanitizer.Limits.role {
            roleValidationError = "Role name is too long (max \(InputSanitizer.Limits.role) characters)"
        } else if InputSanitizer.containsInjectionPatterns(trimmed) {
            roleValidationError = "Invalid characters detected"
            SecureLogger.security("Potential injection in role input", category: .security)
        } else {
            roleValidationError = nil
        }
    }
    
    func validateLocation() {
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            locationValidationError = nil
        } else if trimmed.count > InputSanitizer.Limits.location {
            locationValidationError = "Location is too long (max \(InputSanitizer.Limits.location) characters)"
        } else if InputSanitizer.containsInjectionPatterns(trimmed) {
            locationValidationError = "Invalid characters detected"
            SecureLogger.security("Potential injection in location input", category: .security)
        } else {
            locationValidationError = nil
        }
    }
    
    func validateCustomSkill() {
        let trimmed = customSkill.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            customSkillValidationError = nil
        } else if trimmed.count > InputSanitizer.Limits.skill {
            customSkillValidationError = "Skill name is too long (max \(InputSanitizer.Limits.skill) characters)"
        } else if InputSanitizer.containsInjectionPatterns(trimmed) {
            customSkillValidationError = "Invalid characters detected"
            SecureLogger.security("Potential injection in skill input", category: .security)
        } else if selectedSkills.contains(trimmed) {
            customSkillValidationError = "Skill already added"
        } else {
            customSkillValidationError = nil
        }
    }
    
    func addCustomSkill() {
        let trimmed = customSkill.trimmingCharacters(in: .whitespaces)
        guard canAddCustomSkill else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedSkills.insert(trimmed)
            customSkill = ""
            customSkillValidationError = nil
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    // MARK: - Save
    
    func saveChanges(appState: AppState? = nil) async {
        guard canSave else { return }
        
        isSaving = true
        saveError = nil
        
        do {
            // Sanitize inputs
            let sanitizedName = InputSanitizer.sanitizeName(fullName)
            let sanitizedRole = InputSanitizer.sanitizeRole(targetRole)
            let sanitizedSkills = InputSanitizer.sanitizeSkills(Array(selectedSkills))
            let sanitizedLocation = location.isEmpty ? nil : InputSanitizer.sanitizeLocation(location)
            
            // Save profile with sanitized inputs
            try await SupabaseService.shared.saveProfile(
                fullName: sanitizedName,
                targetRole: sanitizedRole,
                yearsOfExperience: experienceLevel?.rawValue ?? "Mid Level",
                skills: sanitizedSkills,
                avatarURL: originalProfile.avatarURL, // Keep existing avatar
                location: sanitizedLocation,
                currency: currency
            )
            
            SecureLogger.info("Profile updated successfully", category: .database)
            
            // Update AppState preloaded profile to reflect changes
            if let appState = appState, var preloadedProfile = appState.preloadedProfile {
                self.preloadedProfile.fullName = sanitizedName
                self.preloadedProfile.targetRole = sanitizedRole
                self.preloadedProfile.yearsOfExperience = experienceLevel?.rawValue ?? "Mid Level"
                self.preloadedProfile.skills = sanitizedSkills
                self.preloadedProfile.location = sanitizedLocation
                self.preloadedProfile.currency = currency
                self.preloadedProfile.updatedAt = Date()
                appState.preloadedProfile = preloadedProfile
            }
            
            await MainActor.run {
                self.isSaving = false
            }
        } catch {
            SecureLogger.error("Failed to update profile: \(error)", category: .database)
            await MainActor.run {
                self.saveError = error.localizedDescription
                self.isSaving = false
            }
        }
    }
}
