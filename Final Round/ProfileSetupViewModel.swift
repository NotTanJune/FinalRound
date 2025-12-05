import SwiftUI
import Combine
import CoreLocation

@MainActor
class ProfileSetupViewModel: ObservableObject {
    @Published var currentStep: Step = .identity
    
    // Identity Step
    @Published var fullName = ""
    @Published var targetRole = ""
    @Published var experienceLevel: ExperienceLevel? = nil  // No default - user must select
    
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
    @Published var profileImage: UIImage?
    @Published var isLoadingPhoto = false
    @Published var photoLoadError: String?
    
    // Saving
    @Published var isSaving = false
    @Published var saveError: String?
    @Published var saveProgress: String = ""  // Progress message during save
    
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
        case beginner = "Beginner"
        case mid = "Mid Level"
        case senior = "Senior"
        case executive = "Executive"
        
        /// Returns the evaluation level (one level up for growth-oriented feedback)
        /// - Beginner → Evaluate as Mid Level (lenient, encouraging)
        /// - Mid Level → Evaluate as Senior (moderate growth focus)
        /// - Senior/Executive → Evaluate at their level (full scrutiny)
        var evaluationLevel: String {
            switch self {
            case .beginner: return "Mid Level"
            case .mid: return "Senior"
            case .senior: return "Senior"
            case .executive: return "Executive"
            }
        }
        
        /// Description of the grading approach for this level
        var gradingApproach: String {
            switch self {
            case .beginner:
                return "Be encouraging and focus on foundational skills. Highlight growth potential while noting specific areas for improvement."
            case .mid:
                return "Provide balanced feedback with moderate expectations. Focus on professional development and industry best practices."
            case .senior:
                return "Apply standard professional expectations. Evaluate depth of knowledge and strategic thinking."
            case .executive:
                return "Apply rigorous evaluation standards. Assess leadership insights, strategic vision, and executive presence."
            }
        }
        
        /// Initialize from stored string value (handles legacy "Entry Level" values)
        init?(storedValue: String) {
            switch storedValue {
            case "Beginner", "Entry Level":
                self = .beginner
            case "Mid Level":
                self = .mid
            case "Senior":
                self = .senior
            case "Executive":
                self = .executive
            default:
                return nil
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var canProceedFromIdentity: Bool {
        let trimmedRole = targetRole.trimmingCharacters(in: .whitespaces)
        return !trimmedRole.isEmpty && 
               trimmedRole.count <= InputSanitizer.Limits.role &&
               roleValidationError == nil &&
               experienceLevel != nil  // User must explicitly select experience level
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
                // Pre-warm connection when entering photo step
                Task {
                    await SupabaseService.shared.aggressiveWarmUp()
                }
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
        
        let levelText = experienceLevel?.rawValue ?? "Mid Level"
        
        do {
            let prompt = """
            Generate a list of 15 relevant hard and soft skills for a \(targetRole) with \(levelText) level experience.
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
    
    /// Called when profileImage changes to warm up connection for upload
    func onPhotoSelected() {
        guard profileImage != nil else { return }
        // Warm up connection for upcoming upload
            Task {
                await SupabaseService.shared.aggressiveWarmUp()
        }
    }
    
    // MARK: - Save Profile
    
    func saveProfile() async {
        isSaving = true
        saveError = nil
        saveProgress = "Preparing..."
        
        do {
            var avatarURL: String?
            
            // Upload photo if provided
            if let image = profileImage {
                await MainActor.run {
                    saveProgress = "Uploading photo..."
                }
                avatarURL = try await SupabaseService.shared.uploadAvatar(image: image)
            }
            
            await MainActor.run {
                saveProgress = "Saving profile..."
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
                yearsOfExperience: experienceLevel?.rawValue ?? "Mid Level",
                skills: sanitizedSkills,
                avatarURL: avatarURL,
                location: sanitizedLocation,
                currency: currency
            )
            
            SecureLogger.info("Profile saved successfully", category: .database)
            
            await MainActor.run {
                self.currentStep = .complete
                self.isSaving = false
                self.saveProgress = ""
            }
        } catch {
            SecureLogger.error("Failed to save profile", category: .database)
            await MainActor.run {
                // Provide user-friendly error message for timeout
                if error.localizedDescription.contains("timed out") {
                    self.saveError = "Upload timed out. Please try again - the image has been optimized for faster upload."
                } else {
                    self.saveError = error.localizedDescription
                }
                self.isSaving = false
                self.saveProgress = ""
            }
        }
    }
    
    func skipPhoto() {
        Task {
            await saveProfile()
        }
    }
}
