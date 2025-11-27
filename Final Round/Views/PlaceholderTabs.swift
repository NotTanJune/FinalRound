import SwiftUI
import Auth
import PhotosUI

struct VoiceView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
            Text("Voice Practice")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("Practice your speaking skills here.")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}

struct ResultsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var supabase = SupabaseService.shared
    @State private var sessions: [InterviewSession] = []
    @State private var isLoading = true
    @State private var selectedSession: InterviewSession?
    @State private var sessionToDelete: InterviewSession?
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                if isLoading {
                    LoadingView(message: "Loading your interview history...")
                } else if sessions.isEmpty {
                    ScrollView {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                            Text("No Interview Preps")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("Complete an interview to see your history here.")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(sessions) { session in
                                SessionCard(
                                    session: session,
                                    onTap: {
                                        selectedSession = session
                                    },
                                    onDelete: {
                                        sessionToDelete = session
                                        showingDeleteAlert = true
                                    }
                                )
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Interview Preps")
            .refreshable {
                await loadSessions()
            }
        }
        .sheet(item: $selectedSession) { session in
            SessionSummaryView(
                session: session,
                answeredQuestions: session.answeredCount,
                startTime: session.startTime ?? Date(),
                endTime: session.endTime ?? Date(),
                onDismiss: {
                    selectedSession = nil
                },
                onGoHome: {
                    // When opened from history, "Back to Home" can just dismiss
                    selectedSession = nil
                },
                onViewResults: {
                    // Already in Results tab; just dismiss
                    selectedSession = nil
                },
                isFromHistory: true
            )
        }
        .alert("Delete Session", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    Task {
                        await deleteSession(session)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this interview session? This action cannot be undone.")
        }
        .task {
            await loadSessions()
        }
    }
    
    private func loadSessions() async {
        // First, check if we have preloaded sessions from AppState
        if !appState.preloadedSessions.isEmpty {
            await MainActor.run {
                self.sessions = appState.preloadedSessions
                self.isLoading = false
            }
            print("✅ Using preloaded sessions data")
            return
        }
        
        // Fallback: Load sessions if not preloaded
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let fetchedSessions = try await supabase.fetchInterviewSessions()
            await MainActor.run {
                self.sessions = fetchedSessions
                self.isLoading = false
            }
        } catch {
            print("Failed to load sessions: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func deleteSession(_ session: InterviewSession) async {
        do {
            try await supabase.deleteInterviewSession(id: session.id)
            await MainActor.run {
                sessions.removeAll { $0.id == session.id }
            }
        } catch {
            print("Failed to delete session: \(error)")
        }
    }
}

struct SessionCard: View {
    let session: InterviewSession
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.role)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text(session.formattedDate)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        // Use averageScore instead of missing overallScore
                        let score = Int(session.averageScore)
                        if score > 0 {
                            ScoreBadge(score: Double(score))
                        }
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 16))
                                .foregroundStyle(.red)
                                .padding(8)
                                .background(Color.red.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            
            HStack(spacing: 16) {
                StatItem(icon: "questionmark.circle.fill", value: "\(session.questions.count)", label: "Questions")
                StatItem(icon: "checkmark.circle.fill", value: "\(session.answeredCount)", label: "Answered")
                
                let accuracy = session.answerRate * 100
                if accuracy > 0 {
                    StatItem(icon: "chart.bar.fill", value: "\(Int(accuracy))%", label: "Score")
                }
                }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(value)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(AppTheme.primary)
            
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

struct ScoreBadge: View {
    let score: Double
    
    var color: Color {
        if score >= 80 { return .green }
        if score >= 60 { return AppTheme.ratingYellow }
        return .red
    }
    
    var body: some View {
        Text("\(Int(score))%")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color)
            .cornerRadius(8)
    }
}

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var supabase = SupabaseService.shared
    @State private var userProfile: UserProfile?
    @State private var profileImage: UIImage?
    @State private var isLoading = true
    @State private var showingChangePassword = false
    @State private var showingDeleteAccount = false
    @State private var showingImagePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                profileContent
            }
            .navigationTitle("Profile")
        }
        .alert("Change Password", isPresented: $showingChangePassword) {
            changePasswordAlertButtons
        } message: {
            Text("You'll receive an email with instructions to reset your password.")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccount) {
            deleteAccountAlertButtons
        } message: {
            Text("Are you sure you want to delete your account? This action cannot be undone.")
        }
        .task {
            await loadProfile()
        }
        .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                await handleImageSelection(newItem)
            }
        }
    }
    
    // MARK: - Extracted Views
    
    @ViewBuilder
    private var profileContent: some View {
        if isLoading {
            LoadingView(message: "Loading profile...")
        } else if let profile = userProfile {
            profileScrollView(profile: profile)
        } else {
            Text("Unable to load profile")
                .foregroundStyle(AppTheme.textSecondary)
                .padding(40)
        }
    }
    
    private func profileScrollView(profile: UserProfile) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                profileHeader(profile: profile)
                accountActions
            }
            .padding(20)
        }
    }
    
    private func profileHeader(profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            profileAvatarSection(profile: profile)
            
            if isUploadingImage {
                ProgressView()
                    .tint(AppTheme.primary)
            }
            
            Text(profile.fullName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            
            Text(profile.targetRole)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.top, 20)
    }
    
    private func profileAvatarSection(profile: UserProfile) -> some View {
        ZStack(alignment: .bottomTrailing) {
            profileAvatarImage(profile: profile)
            editAvatarButton
        }
    }
    
    @ViewBuilder
    private func profileAvatarImage(profile: UserProfile) -> some View {
        if let image = profileImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.border, lineWidth: 2))
        } else {
            Circle()
                .fill(AppTheme.lightGreen)
                .frame(width: 100, height: 100)
                .overlay(
                    Text(String(profile.fullName.prefix(1)))
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                )
                .overlay(Circle().stroke(AppTheme.border, lineWidth: 2))
        }
    }
    
    private var editAvatarButton: some View {
        Button {
            showingImagePicker = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(AppTheme.primary)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
        .disabled(isUploadingImage)
    }
    
    private var accountActions: some View {
        VStack(spacing: 12) {
            changePasswordButton
            deleteAccountButton
            signOutButton
        }
    }
    
    private var changePasswordButton: some View {
        Button {
            showingChangePassword = true
        } label: {
            HStack {
                Image(systemName: "lock.rotation")
                Text("Change Password")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
            .padding()
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    private var deleteAccountButton: some View {
        Button {
            showingDeleteAccount = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Account")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.red)
            .padding()
            .background(Color.white)
            .cornerRadius(12)
        }
    }
    
    private var signOutButton: some View {
        Button {
            appState.signOut()
        } label: {
            Text("Sign Out")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var changePasswordAlertButtons: some View {
        Button("Cancel", role: .cancel) { }
        Button("Send Reset Email") {
            Task {
                do {
                    if let email = supabase.currentUser?.email {
                        try await supabase.sendPasswordResetOTP(email: email)
                        #if DEBUG
                        print("📧 Password reset OTP sent")
                        #endif
                    }
                } catch {
                    print("Password reset error: \(error)")
                }
            }
        }
    }
    
    @ViewBuilder
    private var deleteAccountAlertButtons: some View {
        Button("Cancel", role: .cancel) { }
        Button("Delete", role: .destructive) {
            Task {
                do {
                    try await supabase.deleteAccount()
                    appState.deleteAccount()
                } catch {
                    print("Delete account error: \(error)")
                }
            }
        }
    }
    
    private func loadProfile() async {
        // First, check if we have preloaded profile from AppState
        if let preloadedProfile = appState.preloadedProfile {
            await MainActor.run {
                self.userProfile = preloadedProfile
                self.profileImage = appState.preloadedProfileImage
                self.isLoading = false
            }
            print("✅ Using preloaded profile data")
            return
        }
        
        // Fallback: Load profile if not preloaded
        do {
            guard let profile = try await supabase.fetchProfile() else {
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            print("📋 Profile loaded - Skills: \(profile.skills)")
            
            await MainActor.run {
                self.userProfile = profile
            }
            
            // Load avatar if available
            if let avatarURL = profile.avatarURL,
               let url = URL(string: avatarURL),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.profileImage = image
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
        } catch {
            print("Failed to load profile: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func handleImageSelection(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        await MainActor.run {
            isUploadingImage = true
        }
        
        do {
            // Load the image data
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                print("❌ Failed to load image data")
                await MainActor.run {
                    isUploadingImage = false
                }
                return
            }
            
            // Upload to Supabase
            let avatarURL = try await supabase.uploadAvatar(image: image)
            
            // Update profile with new avatar URL
            if var profile = userProfile {
                profile.avatarURL = avatarURL
                try await supabase.updateProfile(profile)
                
                // Update local state
                await MainActor.run {
                    self.userProfile = profile
                    self.profileImage = image
                    self.isUploadingImage = false
                    
                    // Update preloaded data in AppState
                    appState.preloadedProfile = profile
                    appState.preloadedProfileImage = image
                }
                
                print("✅ Profile picture updated successfully")
            }
        } catch {
            print("❌ Failed to update profile picture: \(error)")
            await MainActor.run {
                isUploadingImage = false
            }
        }
    }
}

// Simple FlowLayout for skills
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
