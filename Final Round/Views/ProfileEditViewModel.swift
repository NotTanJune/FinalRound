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
    
    // Location suggestions
    @Published var locationSuggestions: [LocationService.LocationInfo] = []
    @Published var showLocationSuggestions = false
    @Published var isSearchingLocation = false
    @Published var isLocationLocked = false  // True after a location is selected, prevents further suggestions
    
    // Track if a job cache refresh is needed
    @Published var needsJobCacheRefresh = false
    
    private let locationService = LocationService.shared
    private var locationDebounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    init(profile: UserProfile) {
        self.originalProfile = profile
        self.fullName = profile.fullName
        self.targetRole = profile.targetRole
        self.experienceLevel = ProfileSetupViewModel.ExperienceLevel(storedValue: profile.yearsOfExperience)
        self.selectedSkills = Set(profile.skills)
        self.location = profile.location ?? ""
        self.currency = profile.currency ?? "USD"
        
        // Lock location if it's already set (user has previously selected one)
        self.isLocationLocked = !(profile.location ?? "").isEmpty
        
        // Observe LocationService updates
        setupLocationObservers()
    }
    
    private func setupLocationObservers() {
        // Observe suggestions from LocationService
        locationService.$suggestions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] suggestions in
                guard let self = self else { return }
                // Only show suggestions if location is not locked
                guard !self.isLocationLocked else {
                    self.locationSuggestions = []
                    self.showLocationSuggestions = false
                    return
                }
                self.locationSuggestions = suggestions
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.showLocationSuggestions = !suggestions.isEmpty
                }
            }
            .store(in: &cancellables)
        
        // Observe search state
        locationService.$isSearching
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSearchingLocation)
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
    
    /// Check if changes affect job recommendations (location, role, experience, skills, currency)
    var hasJobRelevantChanges: Bool {
        let trimmedRole = targetRole.trimmingCharacters(in: .whitespaces)
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        
        return trimmedRole != originalProfile.targetRole ||
               experienceLevel?.rawValue != originalProfile.yearsOfExperience ||
               trimmedLocation != (originalProfile.location ?? "") ||
               currency != (originalProfile.currency ?? "USD") ||
               selectedSkills != Set(originalProfile.skills)
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
        
        withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedSkills.insert(trimmed)
            customSkill = ""
            customSkillValidationError = nil
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    // MARK: - Location Auto-Complete
    
    /// Called when location text changes - debounces and fetches suggestions
    func onLocationChanged() {
        validateLocation()
        
        // If location is locked, don't search for suggestions
        // This happens after a location is selected
        guard !isLocationLocked else {
            return
        }
        
        // Cancel existing debounce task
        locationDebounceTask?.cancel()
        
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        
        // Hide suggestions and clear if empty
        guard !trimmed.isEmpty else {
            locationService.clearSuggestions()
            showLocationSuggestions = false
            return
        }
        
        // Debounce for 400ms to avoid too many API calls
        locationDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
            
            guard !Task.isCancelled else { return }
            
            await locationService.searchLocations(query: trimmed)
        }
    }
    
    /// Select a location from suggestions - this locks the location input
    func selectLocation(_ locationInfo: LocationService.LocationInfo) {
        // Cancel any pending searches
        locationDebounceTask?.cancel()
        locationService.clearSuggestions()
        
        withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.7)) {
            self.location = locationInfo.fullLocation
            self.currency = locationInfo.currency  // Use the actual currency from the country
            self.showLocationSuggestions = false
            self.locationSuggestions = []
            self.isLocationLocked = true  // Lock to prevent further suggestions
        }
        
        validateLocation()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        SecureLogger.info("Selected location: \(locationInfo.fullLocation), currency: \(currency)", category: .database)
    }
    
    /// Unlock the location field to allow editing again
    func unlockLocation() {
        isLocationLocked = false
        location = ""  // Clear to start fresh
        currency = "USD"  // Reset to default
        locationService.clearSuggestions()
    }
    
    /// Try to infer country and currency from current location input
    func inferLocationDetails() {
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        Task {
            if let locationInfo = await locationService.inferLocation(from: trimmed) {
                await MainActor.run {
                    withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.7)) {
                        self.location = locationInfo.fullLocation
                        self.currency = locationInfo.currency  // Use the actual currency
                    }
                }
                
                SecureLogger.info("Inferred location: \(locationInfo.fullLocation), currency: \(currency)", category: .database)
            }
        }
    }
    
    /// Hide location suggestions (e.g., when tapping outside)
    func hideLocationSuggestions() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showLocationSuggestions = false
        }
        locationService.clearSuggestions()
    }
    
    // MARK: - Save
    
    func saveChanges(appState: AppState? = nil) async {
        guard canSave else { return }
        
        isSaving = true
        saveError = nil
        
        // Determine if we need to refresh job cache before saving
        let shouldRefreshJobs = hasJobRelevantChanges
        
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
            if let appState = appState, let existingProfile = appState.preloadedProfile {
                let updatedProfile = UserProfile(
                    id: existingProfile.id,
                    fullName: sanitizedName,
                    targetRole: sanitizedRole,
                    yearsOfExperience: experienceLevel?.rawValue ?? "Mid Level",
                    skills: sanitizedSkills,
                    avatarURL: existingProfile.avatarURL,
                    location: sanitizedLocation,
                    currency: currency,
                    updatedAt: Date()
                )
                appState.preloadedProfile = updatedProfile
                
                // If job-relevant fields changed, clear the job cache and trigger refresh
                if shouldRefreshJobs {
                    SecureLogger.info("Job-relevant profile changes detected, invalidating job cache", category: .database)
                    
                    // Clear cached jobs for this user
                    JobCache.shared.clearCache(for: existingProfile.id)
                    
                    // Clear preloaded jobs to trigger refresh on HomeView
                    appState.preloadedRecommendedJobs = []
                    
                    // Set flag to indicate cache was invalidated
                    self.needsJobCacheRefresh = true
                }
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
