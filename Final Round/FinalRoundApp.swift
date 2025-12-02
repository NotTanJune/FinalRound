import SwiftUI
import Combine

@main
struct FinalRoundApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
    }
}

class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    @Published var isLoggedIn: Bool {
        didSet {
            UserDefaults.standard.set(isLoggedIn, forKey: "isLoggedIn")
        }
    }
    @Published var hasProfileSetup: Bool {
        didSet {
            UserDefaults.standard.set(hasProfileSetup, forKey: "hasProfileSetup")
        }
    }
    @Published var isCheckingProfile = true
    @Published var showMinimumLoadingAnimation = false
    @Published var currentOnboardingPage = 0
    // Global navigation state
    @Published var selectedTab = 0
    // Signal to dismiss overlays (e.g., setup/session fullScreenCovers)
    @Published var overlayDismissToken = 0
    
    // Preloaded data
    @Published var preloadedProfile: UserProfile?
    @Published var preloadedProfileImage: UIImage?
    @Published var preloadedRecommendedJobs: [JobPost] = []
    @Published var preloadedSessions: [InterviewSession] = []
    
    // Login view state
    @Published var justSignedOut = false
    @Published var justDeletedAccount = false
    
    init() {
        // Load persisted values
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
        self.hasProfileSetup = UserDefaults.standard.bool(forKey: "hasProfileSetup")
        
        // Check if user has a valid Supabase session
        Task {
            await checkSupabaseSession()
        }
    }
    
    @MainActor
    private func checkSupabaseSession() async {
        let supabase = SupabaseService.shared
        await supabase.checkSession()
        
        if supabase.isAuthenticated {
            self.isLoggedIn = true
            self.hasCompletedOnboarding = true
            
            // Check if profile exists and is complete
            do {
                let profileExists = try await supabase.checkProfileExists()
                
                if profileExists, let profile = try? await supabase.fetchProfile() {
                    // Profile is complete if it has targetRole and skills
                    let hasCompleteProfile = !profile.targetRole.isEmpty && !profile.skills.isEmpty
                    self.hasProfileSetup = hasCompleteProfile
                    
                    // If profile is complete, preload all data in the background
                    if hasCompleteProfile {
                        await preloadAppData()
                    }
                } else {
                    self.hasProfileSetup = false
                }
            } catch {
                print("❌ Error checking profile: \(error)")
                self.hasProfileSetup = false
            }
        } else if self.isLoggedIn {
            // Clear stale login state if Supabase session is invalid
            self.isLoggedIn = false
            self.hasProfileSetup = false
        }
        
        // Ensure minimum loading animation time (3 seconds for one full loop)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        self.isCheckingProfile = false
    }
    
    @MainActor
    private func preloadAppData() async {
        let supabase = SupabaseService.shared
        
        print("🔄 Preloading app data...")
        
        // Load all data in parallel using async let
        async let profileTask = loadProfile(supabase: supabase)
        async let sessionsTask = loadSessions(supabase: supabase)
        
        // Wait for all tasks to complete
        let (profile, sessions) = await (profileTask, sessionsTask)
        
        // Store the results
        self.preloadedProfile = profile
        self.preloadedSessions = sessions
        
        // Load recommended jobs from cache if profile is available
        if let profile = profile {
            await loadRecommendedJobsFromCache(profile: profile)
        }
        
        print("✅ App data preloaded successfully")
    }
    
    private func loadProfile(supabase: SupabaseService) async -> UserProfile? {
        do {
            guard let profile = try await supabase.fetchProfile() else { return nil }
            
            // Load avatar image if available
            if let avatarURL = profile.avatarURL,
               let url = URL(string: avatarURL),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.preloadedProfileImage = image
                }
            }
            
            return profile
        } catch {
            print("❌ Failed to preload profile: \(error)")
            return nil
        }
    }
    
    private func loadSessions(supabase: SupabaseService) async -> [InterviewSession] {
        do {
            let sessions = try await supabase.fetchInterviewSessions()
            print("✅ Preloaded \(sessions.count) interview sessions")
            return sessions
        } catch {
            print("❌ Failed to preload sessions: \(error)")
            return []
        }
    }
    
    private func loadRecommendedJobsFromCache(profile: UserProfile) async {
        // Check cache first
        if let cached = JobCache.shared.getCachedJobs(for: profile.id) {
            await MainActor.run {
                self.preloadedRecommendedJobs = cached
            }
            print("✅ Preloaded \(cached.count) recommended jobs from cache")
        } else {
            print("ℹ️ No cached jobs available, will load on demand")
        }
    }
    
    func signOut() {
        self.showMinimumLoadingAnimation = true
        Task {
            await MainActor.run {
                self.isLoggedIn = false
                self.hasProfileSetup = false
                self.selectedTab = 0 // Reset to home tab
                self.justSignedOut = true // Show sign in view on next login screen
                // Keep hasCompletedOnboarding = true so returning users go to login, not onboarding
                
                // Clear preloaded data
                self.preloadedProfile = nil
                self.preloadedProfileImage = nil
                self.preloadedRecommendedJobs = []
                self.preloadedSessions = []
            }
            try? await SupabaseService.shared.signOut()
            // Clear job cache
            JobCache.shared.clearCache()
            // Ensure minimum loading animation time (3 seconds for one full loop)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self.showMinimumLoadingAnimation = false
            }
        }
    }
    
    func deleteAccount() {
        self.justDeletedAccount = true // Show create account view on next login screen
        self.justSignedOut = false
        UserDefaults.standard.set(false, forKey: "hasEverSignedIn") // Reset so create account is shown
        
        // Clear all app state completely
        clearAllAppState()
        
        // Sign out (which clears the session)
        signOut()
    }
    
    /// Completely clears all app state - used after account deletion
    private func clearAllAppState() {
        // Clear preloaded data
        self.preloadedProfile = nil
        self.preloadedProfileImage = nil
        self.preloadedRecommendedJobs = []
        self.preloadedSessions = []
        
        // Clear job cache
        JobCache.shared.clearCache()
        
        // Reset profile setup state
        self.hasProfileSetup = false
        
        // Reset tab selection
        self.selectedTab = 0
        
        // Clear any rate limiter state to allow fresh requests
        RateLimiter.shared.reset()
    }
    
    func completeSignIn() {
        self.showMinimumLoadingAnimation = true
        self.selectedTab = 0 // Reset to home tab
        Task {
            // Authentication already complete, just ensure animation plays
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self.showMinimumLoadingAnimation = false
            }
        }
    }
}
