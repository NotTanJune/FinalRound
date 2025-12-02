import SwiftUI
import PhotosUI
import Combine

@MainActor
class ProfileSetupViewModel: ObservableObject {
    @Published var currentStep: Step = .identity
    
    // Identity Step
    @Published var fullName = ""
    @Published var targetRole = ""
    @Published var experienceLevel: ExperienceLevel = .mid
    
    // Skills Step
    @Published var generatedSkills: [String] = []
    @Published var selectedSkills: Set<String> = []
    @Published var customSkill = ""
    @Published var isLoadingSkills = false
    @Published var skillsError: String?
    
    // Location Step
    @Published var location = ""
    @Published var currency = "USD"
    @Published var isLoadingLocation = false
    
    // Photo Step
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var profileImage: UIImage?
    
    // Saving
    @Published var isSaving = false
    @Published var saveError: String?
    
    // Security: Input validation errors
    @Published var roleValidationError: String?
    @Published var locationValidationError: String?
    @Published var customSkillValidationError: String?
    
    init() {
        // Load existing full name from profile (set during account creation)
        Task {
            await loadExistingProfile()
        }
    }
    
    private func loadExistingProfile() async {
        do {
            if let profile = try await SupabaseService.shared.fetchProfile() {
                await MainActor.run {
                    self.fullName = profile.fullName
                }
            }
        } catch {
            SecureLogger.error("Failed to load existing profile", category: .database)
        }
    }
    
    enum Step {
        case identity
        case skills
        case location
        case photo
        case complete
    }
    
    enum ExperienceLevel: String, CaseIterable {
        case entry = "Entry Level"
        case mid = "Mid Level"
        case senior = "Senior"
        case executive = "Executive"
    }
    
    // MARK: - Computed Properties
    
    var canProceedFromIdentity: Bool {
        let trimmedRole = targetRole.trimmingCharacters(in: .whitespaces)
        return !trimmedRole.isEmpty && 
               trimmedRole.count <= InputSanitizer.Limits.role &&
               roleValidationError == nil
    }
    
    var canProceedFromSkills: Bool {
        selectedSkills.count >= 3 && selectedSkills.count <= InputSanitizer.Limits.skillCount
    }
    
    var canProceedFromLocation: Bool {
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        return !trimmedLocation.isEmpty && 
               trimmedLocation.count <= InputSanitizer.Limits.location &&
               locationValidationError == nil
    }
    
    // MARK: - Security: Input Validation
    
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
        } else if selectedSkills.count >= InputSanitizer.Limits.skillCount {
            customSkillValidationError = "Maximum \(InputSanitizer.Limits.skillCount) skills allowed"
        } else {
            customSkillValidationError = nil
        }
    }
    
    // Security: Sanitize and enforce character limits
    func sanitizeTargetRole(_ value: String) -> String {
        if value.count > InputSanitizer.Limits.role {
            return String(value.prefix(InputSanitizer.Limits.role))
        }
        return value
    }
    
    func sanitizeLocation(_ value: String) -> String {
        if value.count > InputSanitizer.Limits.location {
            return String(value.prefix(InputSanitizer.Limits.location))
        }
        return value
    }
    
    func sanitizeCustomSkill(_ value: String) -> String {
        if value.count > InputSanitizer.Limits.skill {
            return String(value.prefix(InputSanitizer.Limits.skill))
        }
        return value
    }
    
    // MARK: - Navigation
    
    func goToNextStep() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch currentStep {
            case .identity:
                currentStep = .skills
                Task {
                    await fetchAIRecommendations()
                }
            case .skills:
                currentStep = .location
            case .location:
                currentStep = .photo
            case .photo:
                Task {
                    await saveProfile()
                }
            case .complete:
                break
            }
        }
    }
    
    func goToPreviousStep() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch currentStep {
            case .identity:
                break
            case .skills:
                currentStep = .identity
            case .location:
                currentStep = .skills
            case .photo:
                currentStep = .location
            case .complete:
                break
            }
        }
    }
    
    // MARK: - Location
    
    func requestDeviceLocation() async {
        isLoadingLocation = true
        
        let initialStatus = LocationManager.shared.authorizationStatus
        
        // If already authorized, just fetch the location
        if initialStatus == .authorizedWhenInUse || initialStatus == .authorizedAlways {
            await fetchAndSetLocation()
            return
        }
        
        // If denied or restricted, stop loading
        if initialStatus == .denied || initialStatus == .restricted {
            await MainActor.run {
                self.isLoadingLocation = false
            }
            return
        }
        
        // Status is .notDetermined - request permission and poll for response
        await MainActor.run {
            LocationManager.shared.requestLocationPermission()
        }
        
        // Poll for authorization status change (up to 60 seconds for user to respond)
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5 seconds
            
            let currentStatus = LocationManager.shared.authorizationStatus
            
            // User granted permission
            if currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways {
                await fetchAndSetLocation()
                return
            }
            
            // User denied permission or status changed to restricted
            if currentStatus == .denied || currentStatus == .restricted {
                await MainActor.run {
                    self.isLoadingLocation = false
                }
                return
            }
            
            // Still .notDetermined - keep polling
        }
        
        // Timeout after 60 seconds
        await MainActor.run {
            self.isLoadingLocation = false
        }
    }
    
    private func fetchAndSetLocation() async {
        LocationManager.shared.fetchCurrentLocation()
        
        // Wait for location to be fetched (up to 10 seconds)
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let detectedLocation = LocationManager.shared.currentLocation {
                await MainActor.run {
                    self.location = detectedLocation
                    self.currency = LocationManager.shared.currentCurrency ?? "USD"
                    self.isLoadingLocation = false
                }
                return
            }
        }
        
        await MainActor.run {
            self.isLoadingLocation = false
        }
    }
    
    func updateCurrencyFromLocation() {
        currency = LocationManager.shared.inferCurrencyFromLocation(location)
    }
    
    // MARK: - AI Skill Generation
    
    func fetchAIRecommendations() async {
        isLoadingSkills = true
        skillsError = nil
        
        do {
            let prompt = """
            Generate a list of 15 relevant hard and soft skills for a \(targetRole) with \(experienceLevel.rawValue) level experience.
            Return strictly a JSON array of strings, e.g., ["Swift", "Leadership", "System Design"].
            Do not include markdown formatting, code blocks, or extra text. Only return the JSON array.
            """
            
            let skills = try await GroqService.shared.generateSkills(prompt: prompt)
            
            await MainActor.run {
                self.generatedSkills = skills
                self.isLoadingSkills = false
            }
        } catch {
            await MainActor.run {
                self.skillsError = "Failed to generate skills. Please try again."
                self.isLoadingSkills = false
                // Provide fallback skills
                self.generatedSkills = generateFallbackSkills()
            }
        }
    }
    
    private func generateFallbackSkills() -> [String] {
        ["Communication", "Problem Solving", "Leadership", "Teamwork", "Time Management",
         "Critical Thinking", "Adaptability", "Creativity", "Analytical Skills", "Project Management",
         "Strategic Planning", "Decision Making", "Collaboration", "Innovation", "Technical Writing"]
    }
    
    // MARK: - Skill Management
    
    func toggleSkill(_ skill: String) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        if selectedSkills.contains(skill) {
            selectedSkills.remove(skill)
        } else {
            // Security: Enforce skill count limit
            guard selectedSkills.count < InputSanitizer.Limits.skillCount else { return }
            selectedSkills.insert(skill)
        }
    }
    
    func addCustomSkill() {
        // Security: Sanitize and validate
        let sanitized = InputSanitizer.sanitizeSkill(customSkill)
        guard !sanitized.isEmpty, !generatedSkills.contains(sanitized) else { return }
        
        // Security: Check skill count limit
        guard selectedSkills.count < InputSanitizer.Limits.skillCount else {
            customSkillValidationError = "Maximum \(InputSanitizer.Limits.skillCount) skills allowed"
            return
        }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        generatedSkills.append(sanitized)
        selectedSkills.insert(sanitized)
        customSkill = ""
        customSkillValidationError = nil
    }
    
    // MARK: - Photo Handling
    
    func loadPhoto() async {
        guard let item = selectedPhotoItem else { return }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                return
            }
            
            // Security: Validate image size
            if let jpegData = image.jpegData(compressionQuality: 0.7),
               jpegData.count > 5 * 1024 * 1024 {
                await MainActor.run {
                    self.saveError = "Image is too large. Please select a smaller image."
                }
                return
            }
            
            await MainActor.run {
                self.profileImage = image
            }
        } catch {
            SecureLogger.error("Failed to load image", category: .general)
        }
    }
    
    // MARK: - Save Profile
    
    func saveProfile() async {
        isSaving = true
        saveError = nil
        
        do {
            var avatarURL: String?
            
            // Upload photo if provided
            if let image = profileImage {
                avatarURL = try await SupabaseService.shared.uploadAvatar(image: image)
            }
            
            // Security: Sanitize all inputs before saving
            let sanitizedName = InputSanitizer.sanitizeName(fullName)
            let sanitizedRole = InputSanitizer.sanitizeRole(targetRole)
            let sanitizedSkills = InputSanitizer.sanitizeSkills(Array(selectedSkills))
            let sanitizedLocation = location.isEmpty ? nil : InputSanitizer.sanitizeLocation(location)
            
            // Save profile data with sanitized inputs
            try await SupabaseService.shared.saveProfile(
                fullName: sanitizedName,
                targetRole: sanitizedRole,
                yearsOfExperience: experienceLevel.rawValue,
                skills: sanitizedSkills,
                avatarURL: avatarURL,
                location: sanitizedLocation,
                currency: currency
            )
            
            SecureLogger.info("Profile saved successfully", category: .database)
            
            await MainActor.run {
                self.currentStep = .complete
                self.isSaving = false
            }
        } catch {
            SecureLogger.error("Failed to save profile", category: .database)
            await MainActor.run {
                self.saveError = error.localizedDescription
                self.isSaving = false
            }
        }
    }
    
    func skipPhoto() {
        Task {
            await saveProfile()
        }
    }
}
