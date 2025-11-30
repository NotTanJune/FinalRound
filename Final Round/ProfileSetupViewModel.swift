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
            print("Failed to load existing profile: \(error)")
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
        !targetRole.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var canProceedFromSkills: Bool {
        selectedSkills.count >= 3
    }
    
    var canProceedFromLocation: Bool {
        !location.trimmingCharacters(in: .whitespaces).isEmpty
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
            selectedSkills.insert(skill)
        }
    }
    
    func addCustomSkill() {
        let trimmed = customSkill.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !generatedSkills.contains(trimmed) else { return }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        generatedSkills.append(trimmed)
        selectedSkills.insert(trimmed)
        customSkill = ""
    }
    
    // MARK: - Photo Handling
    
    func loadPhoto() async {
        guard let item = selectedPhotoItem else { return }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                return
            }
            
            await MainActor.run {
                self.profileImage = image
            }
        } catch {
            print("Failed to load image: \(error)")
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
            
            // Save profile data
            try await SupabaseService.shared.saveProfile(
                fullName: fullName,
                targetRole: targetRole,
                yearsOfExperience: experienceLevel.rawValue,
                skills: Array(selectedSkills),
                avatarURL: avatarURL,
                location: location.isEmpty ? nil : location,
                currency: currency
            )
            
            await MainActor.run {
                self.currentStep = .complete
                self.isSaving = false
            }
        } catch {
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
