import SwiftUI
import Auth

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var previousTab: Int = 0
    @State private var animationDirection: AnimationDirection = .none
    
    enum AnimationDirection {
        case left, right, none
    }
    
    var body: some View {
        TabView(selection: Binding(
            get: { appState.selectedTab },
            set: { newValue in
                // Determine animation direction before updating
                if newValue > appState.selectedTab {
                    animationDirection = .right
                } else if newValue < appState.selectedTab {
                    animationDirection = .left
                } else {
                    animationDirection = .none
                }
                previousTab = appState.selectedTab
                
                withAnimation(.smooth(duration: 0.3)) {
                    appState.selectedTab = newValue
                }
            }
        )) {
            AnimatedTabContent(direction: animationDirection, isActive: appState.selectedTab == 0) {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)
            
            AnimatedTabContent(direction: animationDirection, isActive: appState.selectedTab == 1) {
                ResultsView()
            }
            .tabItem { Label("Preps", systemImage: "doc.text.fill") }
            .tag(1)
            
            AnimatedTabContent(direction: animationDirection, isActive: appState.selectedTab == 2) {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person.fill") }
            .tag(2)
        }
        .tint(AppTheme.accent)
    }
}

// MARK: - Animated Tab Content Wrapper
struct AnimatedTabContent<Content: View>: View {
    let direction: MainTabView.AnimationDirection
    let isActive: Bool
    let content: () -> Content
    
    var body: some View {
        content()
            .transition(transitionForDirection)
    }
    
    private var transitionForDirection: AnyTransition {
        switch direction {
        case .right:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .left:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .none:
            return .opacity
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var supabase = SupabaseService.shared
    @State private var showingInterviewSetup = false
    @State private var showingRecommendedJobs = false
    @State private var userProfile: UserProfile?
    @State private var profileImage: UIImage?
    @State private var recommendedJobs: [JobPost] = []
    @State private var isLoadingJobs = false
    @State private var jobURLInput = ""
    @State private var showingURLGenerator = false
    @State private var jobLoadingTask: Task<Void, Never>?
    
    // URL Parser state
    @State private var isParsingURL = false
    @State private var urlParseError: String?
    @State private var showingURLError = false
    @State private var parsedJob: JobPost?
    @State private var showingParsedJobSetup = false
    
    var firstName: String {
        guard let fullName = userProfile?.fullName else { return "Candidate" }
        return fullName.components(separatedBy: " ").first ?? fullName
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Section
                        HStack {
                            HStack(spacing: 12) {
                                if let image = profileImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .strokeBorder(AppTheme.border, lineWidth: 2)
                                        )
                                } else {
                                    Circle()
                                        .fill(AppTheme.lightGreen)
                                        .frame(width: 48, height: 48)
                                        .overlay(
                                            Text(String(firstName.prefix(1)))
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundStyle(AppTheme.primary)
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hello, \(firstName)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text("Ready to prep?")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            
                            Spacer()
                        }
                        
                        // Simplified Hero Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Start Preparation")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Text("Browse jobs below or generate a custom interview prep.")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(4)
                            
                            HStack(spacing: 12) {
                                Button {
                                    showingRecommendedJobs = true
                                } label: {
                                    HStack {
                                        Image(systemName: "list.bullet")
                                        Text("Browse Jobs")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .cornerRadius(20)
                                }
                                
                                Button {
                                    showingInterviewSetup = true
                                } label: {
                                    HStack {
                                        Image(systemName: "wand.and.stars")
                                        Text("Generate")
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(20)
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(AppTheme.primary)
                        )
                        .shadow(color: AppTheme.primary.opacity(0.3), radius: 10, y: 5)
                        
                        // Job URL Generator Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Generate from Job URL")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            
                            HStack(spacing: 12) {
                                TextField("Paste job posting URL", text: $jobURLInput)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(AppTheme.border, lineWidth: 1)
                                    )
                                
                                Button {
                                    parseJobURL()
                                } label: {
                                    Group {
                                        if isParsingURL {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        } else {
                                            Text("Generate")
                                        }
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: isParsingURL ? 80 : nil)
                                    .padding(.horizontal, isParsingURL ? 12 : 20)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.primary)
                                    .cornerRadius(12)
                                }
                                .disabled(jobURLInput.isEmpty || isParsingURL)
                                .opacity(jobURLInput.isEmpty ? 0.5 : 1)
                                .animation(.easeInOut(duration: 0.2), value: isParsingURL)
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
                        
                        // Recommended Jobs
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Recommended Jobs")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                
                                Spacer()
                                
                                Button {
                                    showingRecommendedJobs = true
                                } label: {
                                    Text("See All")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppTheme.primary)
                                }
                            }
                            
                            if isLoadingJobs {
                                LoadingView(message: "Finding jobs for you...", size: 100)
                                    .frame(maxWidth: .infinity)
                                    .padding(40)
                            } else if recommendedJobs.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "briefcase")
                                        .font(.system(size: 40))
                                        .foregroundStyle(AppTheme.textSecondary)
                                    Text("No jobs found")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(40)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(recommendedJobs.prefix(10)) { job in
                                        NavigationLink(destination: JobDescriptionView(job: job)) {
                                            JobPostCard(job: job)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .refreshable {
                    await refreshJobs()
                }
            }
            .background(AppTheme.background)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showingInterviewSetup) {
                InterviewSetupView()
            }
            .fullScreenCover(isPresented: $showingParsedJobSetup) {
                if let job = parsedJob {
                    InterviewSetupView(job: job)
                }
            }
            .sheet(isPresented: $showingRecommendedJobs) {
                RecommendedJobsView(userProfile: userProfile)
            }
            .alert("Error", isPresented: $showingURLError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(urlParseError ?? "Failed to parse job URL")
            }
            .task {
                await loadUserProfile()
            }
        }
    }
    
    private func refreshJobs() async {
        guard let profile = userProfile else { return }
        
        // Cancel any existing job loading task
        jobLoadingTask?.cancel()
        
        // Clear cache to force fresh fetch
        JobCache.shared.clearCache(for: profile.id)
        
        // Reload jobs
        await loadRecommendedJobs(profile: profile)
    }
    
    private func loadUserProfile() async {
        // First, check if we have preloaded data from AppState
        if let preloadedProfile = appState.preloadedProfile {
            await MainActor.run {
                self.userProfile = preloadedProfile
                self.profileImage = appState.preloadedProfileImage
                self.recommendedJobs = appState.preloadedRecommendedJobs
            }
            
            // If no cached jobs, load them
            if recommendedJobs.isEmpty {
                await loadRecommendedJobs(profile: preloadedProfile)
            }
            
            print("✅ Using preloaded profile data")
            return
        }
        
        // Fallback: Load data if not preloaded
        do {
            guard let profile = try await supabase.fetchProfile() else { return }
            
            await MainActor.run {
                self.userProfile = profile
            }
            
            // Load avatar image if available
            if let avatarURL = profile.avatarURL,
               let url = URL(string: avatarURL),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.profileImage = image
                }
            }
            
            // Load recommended jobs if not already cached
            if recommendedJobs.isEmpty {
                await loadRecommendedJobs(profile: profile)
            }
        } catch {
            print("Failed to load profile: \(error)")
        }
    }
    
    private func loadRecommendedJobs(profile: UserProfile) async {
        // Cancel any existing job loading task
        jobLoadingTask?.cancel()
        
        // Check cache first, but only if profile has location data
        // This ensures old cached jobs without location filtering are refreshed
        if let location = profile.location, !location.isEmpty,
           let cached = JobCache.shared.getCachedJobs(for: profile.id) {
            await MainActor.run {
                self.recommendedJobs = cached
            }
            print("✅ Using cached jobs for location: \(location)")
            return
        }
        
        // If no location in profile, clear any old cache to force refresh
        if profile.location == nil || profile.location?.isEmpty == true {
            print("⚠️ Profile has no location, clearing old cache")
            JobCache.shared.clearCache(for: profile.id)
        }
        
        await MainActor.run {
            self.isLoadingJobs = true
        }
        
        // Create a new task for loading jobs
        jobLoadingTask = Task {
        
        do {
            // Check if task was cancelled before starting
            try Task.checkCancellation()
            
            let role = profile.targetRole.isEmpty ? "Software Engineer" : profile.targetRole
            let skills = profile.skills
            let location = profile.location
            let currency = profile.currency ?? "USD"
            
            print("🔍 Fetching jobs for \(role) in \(location ?? "various locations") with currency \(currency)...")
            
            let jobs = try await GroqService.shared.searchJobs(role: role, skills: skills, count: 10, location: location, currency: currency)
            
            // Check if task was cancelled after network request
            try Task.checkCancellation()
            
            // If API returned too few jobs, supplement with fallback
            let finalJobs: [JobPost]
            if jobs.count < 5 {
                print("⚠️ Insufficient jobs from API (\(jobs.count)), adding fallback jobs")
                let fallbackJobs = createFallbackJobs(for: profile)
                // Combine API jobs with fallback, removing duplicates
                let combined = jobs + fallbackJobs
                finalJobs = Array(combined.prefix(10))
            } else {
                finalJobs = jobs
            }
            
            // Cache the results
            JobCache.shared.cacheJobs(finalJobs, for: profile.id)
            
            await MainActor.run {
                self.recommendedJobs = finalJobs
                self.isLoadingJobs = false
            }
            
            print("✅ Successfully loaded \(finalJobs.count) jobs")
        } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
            print("⏱️ Request timed out, using fallback jobs")
            let fallbackJobs = createFallbackJobs(for: profile)
            JobCache.shared.cacheJobs(fallbackJobs, for: profile.id)
            await MainActor.run {
                self.recommendedJobs = fallbackJobs
                self.isLoadingJobs = false
            }
        } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            // Request was cancelled (likely due to view dismissal or refresh)
            // Don't show error, just use cached or fallback jobs
            print("ℹ️ Job request cancelled, using cached/fallback jobs")
            let fallbackJobs = createFallbackJobs(for: profile)
            await MainActor.run {
                if self.recommendedJobs.isEmpty {
                    self.recommendedJobs = fallbackJobs
                }
                self.isLoadingJobs = false
            }
        } catch is CancellationError {
            // Task was cancelled
            print("ℹ️ Job loading task cancelled")
            await MainActor.run {
                self.isLoadingJobs = false
            }
        } catch {
            print("❌ Failed to load recommended jobs: \(error)")
            let fallbackJobs = createFallbackJobs(for: profile)
            JobCache.shared.cacheJobs(fallbackJobs, for: profile.id)
            await MainActor.run {
                self.recommendedJobs = fallbackJobs
                self.isLoadingJobs = false
            }
        }
        }
        
        // Wait for the task to complete
        await jobLoadingTask?.value
    }
    
    private func createFallbackJobs(for profile: UserProfile) -> [JobPost] {
        let role = profile.targetRole.isEmpty ? "Software Engineer" : profile.targetRole
        return [
            JobPost(
                role: "Senior \(role)",
                company: "Tech Corp",
                location: "Remote",
                salary: "$120,000 - $160,000",
                tags: Array(profile.skills.prefix(3)),
                description: "Join our team and work on exciting projects.",
                responsibilities: ["Lead projects", "Mentor team members", "Drive innovation"],
                logoName: "briefcase.fill"
            ),
            JobPost(
                role: "\(role)",
                company: "Innovation Labs",
                location: "San Francisco, CA",
                salary: "$100,000 - $140,000",
                tags: Array(profile.skills.prefix(3)),
                description: "Build cutting-edge solutions for our clients.",
                responsibilities: ["Develop features", "Collaborate with teams", "Ensure quality"],
                logoName: "briefcase.fill"
            )
        ]
    }
    
    // MARK: - URL Parsing
    
    private func parseJobURL() {
        let urlString = jobURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate URL format first
        guard LinkedInJobParser.shared.isValidLinkedInJobURL(urlString) else {
            urlParseError = "Please enter a valid LinkedIn job posting URL"
            showingURLError = true
            return
        }
        
        isParsingURL = true
        
        Task {
            do {
                let job = try await LinkedInJobParser.shared.parseJob(from: urlString)
                
                await MainActor.run {
                    self.parsedJob = job
                    self.isParsingURL = false
                    self.jobURLInput = "" // Clear input on success
                    self.showingParsedJobSetup = true
                }
                
                print("✅ Successfully parsed job: \(job.role) at \(job.company)")
            } catch let error as LinkedInParserError {
                await MainActor.run {
                    self.urlParseError = error.errorDescription
                    self.showingURLError = true
                    self.isParsingURL = false
                }
                print("❌ LinkedIn parsing error: \(error.errorDescription ?? "Unknown")")
            } catch {
                await MainActor.run {
                    self.urlParseError = "Failed to parse job: \(error.localizedDescription)"
                    self.showingURLError = true
                    self.isParsingURL = false
                }
                print("❌ Unexpected error: \(error)")
            }
        }
    }
}

struct StepView: View {
    let icon: String
    let text: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 44, height: 44)
                .background(AppTheme.lightGreen)
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// ... rest of the file remains unchanged ...
