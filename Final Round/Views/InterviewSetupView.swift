import SwiftUI

struct InterviewSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    
    // Optional job for pre-population
    let job: JobPost?
    
    @State private var selectedCategories: Set<QuestionCategory> = []
    @State private var difficulty: Difficulty? = nil
    @State private var numberOfQuestions: Double = 5
    @State private var roleTitle: String = ""
    @State private var enableAudioRecording: Bool = true
    @State private var selectedExperienceLevel: ProfileSetupViewModel.ExperienceLevel? = nil
    @State private var showingSession = false
    @State private var interviewSession: InterviewSession?
    @FocusState private var isRoleFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var hasScrolled = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isGeneratingQuestions = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]
    
    /// Check if all required fields are filled to start the interview
    private var canStartInterview: Bool {
        !roleTitle.trimmingCharacters(in: .whitespaces).isEmpty &&
        !selectedCategories.isEmpty &&
        difficulty != nil &&
        selectedExperienceLevel != nil
    }
    
    // Default initializer without job
    init() {
        self.job = nil
    }
    
    // Initializer with job for pre-population
    init(job: JobPost) {
        self.job = job
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        roleSection
                        categoriesSection
                        difficultySection
                            .id("difficulty")
                        experienceLevelSection
                        audioRecordingSection
                        questionsSection
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .background(AppTheme.background)
                .onAppear {
                    scrollProxy = proxy
                }
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                    if scrollOffset < -10 && !hasScrolled {
                        withAnimation(.easeOut(duration: 0.3)) {
                            hasScrolled = true
                        }
                    }
                }
            }
            .navigationTitle("Setup Interview")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isRoleFocused = false
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(AppTheme.controlBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    // Scroll indicator - positioned at bottom left, above the button
                    if !hasScrolled {
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    scrollProxy?.scrollTo("difficulty", anchor: .top)
                                    hasScrolled = true
                                }
                            } label: {
                                ScrollIndicator()
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    // Floating Start Interview button
                    Button {
                        startInterview()
                    } label: {
                        if isGeneratingQuestions {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                                Text("Generating Questions...")
                            }
                        } else {
                            Label("Start Interview", systemImage: "arrow.right")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canStartInterview || isGeneratingQuestions)
                    .opacity(canStartInterview ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.2), value: roleTitle.isEmpty)
                    .shadow(color: AppTheme.primary.opacity(0.3), radius: 12, x: 0, y: 6)
                    .padding(.horizontal, 24)
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: AppTheme.background.opacity(0), location: 0),
                                .init(color: AppTheme.background.opacity(0.3), location: 0.3),
                                .init(color: AppTheme.background.opacity(0.7), location: 0.6),
                                .init(color: AppTheme.background, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 60)
                        
                        AppTheme.background
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                )
            }
            .fullScreenCover(isPresented: $showingSession) {
                if let session = interviewSession {
                    InterviewSessionView(session: session)
                }
            }
            .onChange(of: showingSession) { _, newValue in
                if newValue {
                    isRoleFocused = false
                }
            }
            .onChange(of: appState.overlayDismissToken) { _, _ in
                // When overlayDismissToken changes, dismiss this view with animation
                withAnimation(.easeOut(duration: 0.3)) {
                    dismiss()
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .onAppear {
                // Only pre-populate if coming from a job
                prepopulateFromJob()
            }
        }
    }
    
    private func prepopulateFromJob() {
        guard let job = job else { return }
        
        // Pre-populate role from job
        roleTitle = job.role
        
        // Suggest categories based on job tags
        var suggestedCategories: Set<QuestionCategory> = []
        
        let tags = job.tags.map { $0.lowercased() }
        let roleWords = job.role.lowercased().components(separatedBy: " ")
        let allKeywords = tags + roleWords
        
        // Technical keywords
        let technicalKeywords = ["software", "engineer", "developer", "programming", "technical", "code", "data", "analyst", "architecture", "devops", "backend", "frontend", "fullstack", "ios", "android", "web", "cloud", "ai", "ml", "machine learning"]
        if allKeywords.contains(where: { keyword in technicalKeywords.contains(where: { keyword.contains($0) }) }) {
            suggestedCategories.insert(.technical)
        }
        
        // Always include behavioral for any role
        suggestedCategories.insert(.behavioral)
        
        // Infer experience level from job title keywords
        let executiveKeywords = ["chief", "cto", "ceo", "cfo", "coo", "vp", "vice president", "executive", "president"]
        let seniorKeywords = ["senior", "lead", "manager", "director", "principal", "head", "staff", "architect"]
        let midKeywords = ["mid", "intermediate", "experienced"]
        let juniorKeywords = ["junior", "entry", "intern", "associate", "graduate", "trainee", "fresher"]
        
        var inferredLevel: ProfileSetupViewModel.ExperienceLevel? = nil
        
        if allKeywords.contains(where: { keyword in executiveKeywords.contains(where: { keyword.contains($0) }) }) {
            inferredLevel = .executive
            suggestedCategories.insert(.situational)
        } else if allKeywords.contains(where: { keyword in seniorKeywords.contains(where: { keyword.contains($0) }) }) {
            inferredLevel = .senior
            suggestedCategories.insert(.situational)
        } else if allKeywords.contains(where: { keyword in juniorKeywords.contains(where: { keyword.contains($0) }) }) {
            inferredLevel = .beginner
        } else if allKeywords.contains(where: { keyword in midKeywords.contains(where: { keyword.contains($0) }) }) {
            inferredLevel = .mid
        }
        
        // Set experience level: use inferred level, fall back to user profile, then default to mid
        if let level = inferredLevel {
            selectedExperienceLevel = level
        } else if let profileExperience = appState.preloadedProfile?.yearsOfExperience,
                  let profileLevel = ProfileSetupViewModel.ExperienceLevel(storedValue: profileExperience) {
            selectedExperienceLevel = profileLevel
        } else {
            selectedExperienceLevel = .mid
        }
        
        // If we have categories, use them
        if !suggestedCategories.isEmpty {
            selectedCategories = suggestedCategories
        }
        
        // Set reasonable defaults for job-based interviews
        difficulty = .medium
        numberOfQuestions = 8
    }
    
    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Interview Role")
            TextField("e.g. Software Engineer, Product Manager", text: $roleTitle)
                .font(.system(size: 14))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .focused($isRoleFocused)
                .submitLabel(.done)
                .onSubmit {
                    isRoleFocused = false
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.controlBackground)
                )
        }
        .appCard()
    }
    
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Question Categories")
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(QuestionCategory.allCases, id: \.self) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategories.contains(category)
                    ) {
                        if selectedCategories.contains(category) {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                        }
                    }
                }
            }
        }
        .appCard()
    }
    
    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Difficulty Level")
            HStack(spacing: 12) {
                ForEach(Difficulty.allCases, id: \.self) { level in
                    DifficultyButton(
                        difficulty: level,
                        isSelected: difficulty == level
                    ) {
                        difficulty = level
                    }
                }
            }
        }
        .appCard()
    }
    
    private var experienceLevelSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Your Experience Level")
                Text("Grading adjusts based on your level")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ProfileSetupViewModel.ExperienceLevel.allCases, id: \.self) { level in
                    ExperienceLevelButton(
                        level: level,
                        isSelected: selectedExperienceLevel == level
                    ) {
                        selectedExperienceLevel = level
                    }
                }
            }
        }
        .appCard()
    }
    
    private var audioRecordingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Audio Recording")
            
            Button {
                enableAudioRecording.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: enableAudioRecording ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24))
                        .foregroundStyle(enableAudioRecording ? AppTheme.primary : AppTheme.textSecondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable audio recording")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text("Record your responses for AI-powered transcription and feedback")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(enableAudioRecording ? AppTheme.lightGreen.opacity(0.3) : AppTheme.background)
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .appCard()
    }
    
    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            statHeader(title: "Number of Questions", value: String(format: "%.0f", numberOfQuestions))
            Slider(value: $numberOfQuestions, in: 3...15, step: 1)
                .tint(AppTheme.accent)
        }
        .appCard()
    }
    
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
    }
    
    private func statHeader(title: String, value: String) -> some View {
        HStack {
            sectionTitle(title)
            Spacer()
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.accent)
        }
    }
    
    private func startInterview() {
        // Guard to ensure required fields are set (should always pass due to button being disabled)
        guard let selectedDifficulty = difficulty,
              let experienceLevel = selectedExperienceLevel else {
            return
        }
        
        isRoleFocused = false
        let trimmedRole = roleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        roleTitle = trimmedRole
        
        isGeneratingQuestions = true
        
        Task {
            do {
                // Generate questions using Groq API
                let questions = try await GroqService.shared.generateQuestions(
                    role: trimmedRole,
                    categories: Array(selectedCategories),
                    difficulty: selectedDifficulty,
                    count: Int(numberOfQuestions)
                )
                
                // Ensure we have questions
                guard !questions.isEmpty else {
                    await MainActor.run {
                        errorMessage = "No questions were generated. Please try again."
                        showingError = true
                        isGeneratingQuestions = false
                    }
                    return
                }
                
                // Create session and show it
                await MainActor.run {
                    interviewSession = InterviewSession(
                        role: trimmedRole,
                        difficulty: selectedDifficulty,
                        categories: Array(selectedCategories),
                        questions: questions,
                        enableAudioRecording: enableAudioRecording,
                        experienceLevel: experienceLevel.rawValue
                    )
                    
                    isGeneratingQuestions = false
                    showingSession = true
                }
            } catch let error as GroqError {
                await MainActor.run {
                    errorMessage = error.errorDescription
                    showingError = true
                    isGeneratingQuestions = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate questions: \(error.localizedDescription)"
                    showingError = true
                    isGeneratingQuestions = false
                }
            }
        }
    }
}

struct CategoryButton: View {
    let category: QuestionCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: iconForCategory(category))
                    .font(.system(size: 24, weight: .semibold))
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 92)
            .foregroundStyle(isSelected ? AppTheme.accent : .primary)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AppTheme.softAccent : AppTheme.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent : AppTheme.separator, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func iconForCategory(_ category: QuestionCategory) -> String {
        switch category {
        case .behavioral: return "person.2.fill"
        case .technical: return "laptopcomputer"
        case .situational: return "lightbulb.max"
        case .general: return "quote.bubble.fill"
        }
    }
}

struct DifficultyButton: View {
    let difficulty: Difficulty
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(difficulty.rawValue)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(isSelected ? .white : AppTheme.accent)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? AppTheme.accent : AppTheme.controlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? AppTheme.accent.opacity(0.01) : AppTheme.separator, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ExperienceLevelButton: View {
    let level: ProfileSetupViewModel.ExperienceLevel
    let isSelected: Bool
    let action: () -> Void
    
    private var iconName: String {
        switch level {
        case .beginner: return "leaf.fill"
        case .mid: return "chart.bar.fill"
        case .senior: return "star.fill"
        case .executive: return "crown.fill"
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                Text(level.rawValue)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(isSelected ? .white : AppTheme.accent)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AppTheme.accent : AppTheme.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.01) : AppTheme.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ScrollIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 6) {
            Text("More")
                .font(.system(size: 13, weight: .medium))
            
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .offset(y: isAnimating ? 2 : -2)
        }
        .foregroundStyle(AppTheme.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(AppTheme.lightGreen)
        )
        .overlay(
            Capsule()
                .strokeBorder(AppTheme.primary.opacity(0.2), lineWidth: 1)
        )
        .animation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    InterviewSetupView()
}
