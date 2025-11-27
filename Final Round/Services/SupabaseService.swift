import Foundation
import UIKit
import Supabase
import Combine
import Auth

class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    private let client: SupabaseClient
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    private init() {
        guard 
            let url = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            !url.isEmpty, !anonKey.isEmpty else {
            fatalError("Supabase credentials not found in Info.plist")
        }
        
        print("🔧 Initializing Supabase with URL: \(url)")
        
        self.client = SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: anonKey,
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        
        print("✅ Supabase client initialized successfully")
        
        // Check for existing session on init
        Task {
            await checkSession()
        }
    }
    
    // MARK: - Session Management
    
    func checkSession() async {
        do {
            let session = try await client.auth.session
            await MainActor.run {
                self.currentUser = session.user
                self.isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                self.currentUser = nil
                self.isAuthenticated = false
            }
        }
    }
    
    // MARK: - Authentication
    
    func signUp(email: String, password: String, fullName: String) async throws {
        print("📝 Creating new account for: \(email)")
        let response = try await client.auth.signUp(
            email: email,
            password: password
        )
        
        let user = response.user
        print("✅ Sign up successful! User ID: \(user.id.uuidString)")
        print("📧 User email: \(user.email ?? "N/A")")
        
        // Create initial user profile with full name
        let profile = UserProfile(
            id: user.id,
            fullName: fullName,
            targetRole: "",
            yearsOfExperience: "",
            skills: [],
            avatarURL: nil,
            location: nil,
            currency: nil,
            updatedAt: Date()
        )
        
        // Save profile to database
        try await client
            .from("profiles")
            .insert(profile)
            .execute()
        
        print("✅ Initial profile created")
        
        await MainActor.run {
            self.currentUser = user
            self.isAuthenticated = true
        }
    }
    
    func signIn(email: String, password: String) async throws {
        print("🔐 Attempting to sign in with email: \(email)")
        
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )
        
        print("✅ Sign in successful! User ID: \(session.user.id.uuidString)")
        print("📧 User email: \(session.user.email ?? "N/A")")
        await MainActor.run {
            self.currentUser = session.user
            self.isAuthenticated = true
        }
    }
    
    func signOut() async throws {
        try await client.auth.signOut()
        await MainActor.run {
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }
    
    func deleteAccount() async throws {
        guard currentUser != nil else {
            throw SupabaseError.userNotFound
        }
        
        // Call the Supabase function to delete the user
        try await client.rpc("delete_user").execute()
        
        await MainActor.run {
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }
    
    func updatePassword(newPassword: String) async throws {
        try await client.auth.update(user: UserAttributes(password: newPassword))
    }
    
    // MARK: - OTP-Based Password Reset
    
    /// Generates and sends OTP to email for password reset
    func sendPasswordResetOTP(email: String) async throws {
        print("📧 [OTP] Starting password reset for: \(email)")
        
        // Generate a 6-digit OTP
        let otp = String(format: "%06d", Int.random(in: 0...999999))
        let expiresAt = Date().addingTimeInterval(600) // 10 minutes expiration
        
        print("📧 [OTP] Generated OTP, expires at: \(expiresAt)")
        
        // Store OTP in Supabase table
        let otpRecord = PasswordResetOTP(
            email: email.lowercased(),
            otp: otp,
            expiresAt: expiresAt,
            used: false
        )
        
        // Delete any existing OTPs for this email first
        do {
            try await client
                .from("password_reset_otps")
                .delete()
                .eq("email", value: email.lowercased())
                .execute()
            print("📧 [OTP] Cleaned up any existing OTPs")
        } catch {
            print("⚠️ [OTP] Failed to clean up existing OTPs: \(error.localizedDescription)")
            // Continue anyway
        }
        
        // Insert new OTP
        do {
            try await client
                .from("password_reset_otps")
                .insert(otpRecord)
                .execute()
            print("📧 [OTP] OTP stored in database successfully")
        } catch {
            print("❌ [OTP] Failed to store OTP in database: \(error)")
            throw SupabaseError.custom("Failed to store verification code. Please try again.")
        }
        
        // Send email via Supabase edge function
        do {
            print("📧 [OTP] Invoking send-otp-email edge function...")
            try await client.functions.invoke(
                "send-otp-email",
                options: .init(body: ["email": email, "otp": otp])
            )
            print("✅ [OTP] Edge function completed successfully")
        } catch {
            print("❌ [OTP] Edge function failed: \(error)")
            print("❌ [OTP] Error details: \(String(describing: error))")
            throw SupabaseError.custom("Failed to send verification email. Please check your email address and try again.")
        }
        
        print("✅ [OTP] Password reset OTP sent successfully to \(email)")
    }
    
    /// Verifies the OTP entered by user
    func verifyPasswordResetOTP(email: String, otp: String) async throws -> Bool {
        print("🔐 Verifying OTP for: \(email)")
        
        let response: [PasswordResetOTP] = try await client
            .from("password_reset_otps")
            .select()
            .eq("email", value: email.lowercased())
            .eq("otp", value: otp)
            .eq("used", value: false)
            .execute()
            .value
        
        guard let otpRecord = response.first else {
            print("❌ Invalid OTP")
            return false
        }
        
        // Check if OTP has expired
        if otpRecord.expiresAt < Date() {
            print("❌ OTP has expired")
            // Clean up expired OTP
            try? await client
                .from("password_reset_otps")
                .delete()
                .eq("email", value: email.lowercased())
                .execute()
            return false
        }
        
        print("✅ OTP verified successfully")
        return true
    }
    
    /// Resets password after OTP verification
    func resetPasswordWithOTP(email: String, otp: String, newPassword: String) async throws {
        print("🔑 [RESET] Starting password reset for: \(email)")
        
        // Verify OTP first
        print("🔑 [RESET] Verifying OTP...")
        guard try await verifyPasswordResetOTP(email: email, otp: otp) else {
            print("❌ [RESET] OTP verification failed")
            throw SupabaseError.invalidOTP
        }
        print("✅ [RESET] OTP verified")
        
        // Mark OTP as used
        print("🔑 [RESET] Marking OTP as used...")
        do {
            try await client
                .from("password_reset_otps")
                .update(["used": true])
                .eq("email", value: email.lowercased())
                .eq("otp", value: otp)
                .execute()
            print("✅ [RESET] OTP marked as used")
        } catch {
            print("⚠️ [RESET] Failed to mark OTP as used: \(error)")
            // Continue anyway
        }
        
        // Update password using admin function (requires Supabase edge function)
        print("🔑 [RESET] Calling reset-user-password edge function...")
        do {
            try await client.functions.invoke(
                "reset-user-password",
                options: .init(body: ["email": email, "new_password": newPassword])
            )
            print("✅ [RESET] Edge function completed successfully")
        } catch {
            print("❌ [RESET] Edge function failed: \(error)")
            print("❌ [RESET] Error details: \(String(describing: error))")
            throw SupabaseError.custom("Failed to reset password. Please ensure the reset-user-password edge function is deployed.")
        }
        
        // Clean up OTP
        print("🔑 [RESET] Cleaning up OTP...")
        do {
            try await client
                .from("password_reset_otps")
                .delete()
                .eq("email", value: email.lowercased())
                .execute()
            print("✅ [RESET] OTP cleaned up")
        } catch {
            print("⚠️ [RESET] Failed to clean up OTP: \(error)")
            // Not critical, continue
        }
        
        print("✅ [RESET] Password reset completed successfully")
    }
    
    /// Verifies if new password is same as current (for logged-in users)
    func verifyPasswordIsDifferent(email: String, password: String) async throws -> Bool {
        // Try to sign in with the password - if it works, passwords are same
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            // Sign out immediately
            try await client.auth.signOut()
            return false // Password is the same
        } catch {
            return true // Password is different (sign-in failed)
        }
    }
    
    // MARK: - Interview Session Storage
    
    func saveInterviewSession(_ session: InterviewSession) async throws {
        guard let userEmail = currentUser?.email else {
            throw SupabaseError.userNotFound
        }
        
        print("💾 Saving interview session for: \(userEmail)")
        let record = try InterviewSessionRecord(from: session, userEmail: userEmail)
        
        try await client
            .from("interview_sessions")
            .insert(record)
            .execute()
        
        print("✅ Interview session saved successfully")
    }
    
    func fetchInterviewSessions(limit: Int? = nil) async throws -> [InterviewSession] {
        guard let userEmail = currentUser?.email else {
            throw SupabaseError.userNotFound
        }
        
        print("📥 Fetching interview sessions for: \(userEmail)")
        
        var query = client
            .from("interview_sessions")
            .select()
            .eq("user_email", value: userEmail)
            .order("created_at", ascending: false)
        
        if let limit = limit {
            query = query.limit(limit)
        }
        
        let response: [InterviewSessionRecord] = try await query.execute().value
        
        print("✅ Fetched \(response.count) sessions")
        return try response.map { try $0.toSession() }
    }
    
    func fetchRecentSessions(count: Int = 3) async throws -> [InterviewSession] {
        return try await fetchInterviewSessions(limit: count)
    }
    
    func deleteInterviewSession(id: UUID) async throws {
        guard currentUser != nil else {
            throw SupabaseError.userNotFound
        }
        
        print("🗑️ Deleting interview session: \(id)")
        
        try await client
            .from("interview_sessions")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
        
        print("✅ Interview session deleted successfully")
    }
    
    func getSessionStats() async throws -> SessionStats {
        guard let userEmail = currentUser?.email else {
            throw SupabaseError.userNotFound
        }
        
        let sessions = try await fetchInterviewSessions()
        
        let totalSessions = sessions.count
        let avgScore = sessions.isEmpty ? 0 : Int(sessions.map { $0.completionRate * 100 }.reduce(0, +) / Double(sessions.count))
        
        // Calculate weekly streak
        let calendar = Calendar.current
        let now = Date()
        var weeklyStreak = 0
        
        for i in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            let dayStartDate = calendar.startOfDay(for: dayStart)
            
            let hasSessions = sessions.contains { session in
                guard let startTime = session.startTime else { return false }
                let sessionDay = calendar.startOfDay(for: startTime)
                return sessionDay == dayStartDate
            }
            
            if hasSessions {
                weeklyStreak += 1
            } else if i > 0 {
                // Break streak if a day is missed (except today)
                break
            }
        }
        
        return SessionStats(
            totalSessions: totalSessions,
            weeklyStreak: weeklyStreak,
            avgScore: avgScore
        )
    }
    
    // MARK: - Profile Management
    
    func checkProfileExists() async throws -> Bool {
        guard let userId = currentUser?.id else {
            throw SupabaseError.userNotFound
        }
        
        print("🔍 Checking if profile exists for user: \(userId)")
        
        do {
            let response: [UserProfile] = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            let exists = !response.isEmpty
            print(exists ? "✅ Profile exists" : "❌ No profile found")
            return exists
        } catch {
            print("❌ Error checking profile: \(error)")
            return false
        }
    }
    
    func saveProfile(
        fullName: String,
        targetRole: String,
        yearsOfExperience: String,
        skills: [String],
        avatarURL: String?,
        location: String?,
        currency: String?
    ) async throws {
        guard let userId = currentUser?.id else {
            throw SupabaseError.userNotFound
        }
        
        print("💾 Saving profile for user: \(userId)")
        
        let profile = UserProfile(
            id: userId,
            fullName: fullName,
            targetRole: targetRole,
            yearsOfExperience: yearsOfExperience,
            skills: skills,
            avatarURL: avatarURL,
            location: location,
            currency: currency,
            updatedAt: Date()
        )
        
        // Use upsert to handle both insert and update
        try await client
            .from("profiles")
            .upsert(profile)
            .execute()
        
        print("✅ Profile saved successfully")
    }
    
    func updateProfile(_ profile: UserProfile) async throws {
        print("💾 Updating profile for user: \(profile.id)")
        
        // Use upsert to update the profile
        try await client
            .from("profiles")
            .upsert(profile)
            .execute()
        
        print("✅ Profile updated successfully")
    }
    
    func fetchProfile() async throws -> UserProfile? {
        guard let userId = currentUser?.id else {
            throw SupabaseError.userNotFound
        }
        
        print("📥 Fetching profile for user: \(userId)")
        
        let response: [UserProfile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        if let profile = response.first {
            print("✅ Profile fetched successfully")
            print("👤 Name: \(profile.fullName), Role: \(profile.targetRole)")
            print("🎯 Skills count: \(profile.skills.count)")
            print("🔧 Skills: \(profile.skills)")
            return profile
        }
        
        print("❌ No profile found")
        return nil
    }
    
    func uploadAvatar(image: UIImage) async throws -> String {
        guard let userId = currentUser?.id else {
            throw SupabaseError.userNotFound
        }
        
        // Compress and convert image to JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw SupabaseError.imageCompressionFailed
        }
        
        let fileName = "\(userId.uuidString).jpg"
        let filePath = "avatars/\(fileName)"
        
        print("📤 Uploading avatar: \(filePath)")
        
        // Upload to Supabase Storage - using Data directly instead of deprecated File
        try await client.storage
            .from("avatars")
            .upload(path: filePath, file: imageData, options: FileOptions(upsert: true))
        
        // Get public URL
        let publicURL = try client.storage
            .from("avatars")
            .getPublicURL(path: filePath)
        
        print("✅ Avatar uploaded successfully: \(publicURL)")
        return publicURL.absoluteString
    }
}

struct SessionStats {
    let totalSessions: Int
    let weeklyStreak: Int
    let avgScore: Int
}

// MARK: - User Profile Model
struct UserProfile: Codable {
    let id: UUID
    let fullName: String
    let targetRole: String
    let yearsOfExperience: String
    let skills: [String]
    var avatarURL: String?
    let location: String?
    let currency: String?
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case targetRole = "target_role"
        case yearsOfExperience = "years_of_experience"
        case skills
        case avatarURL = "avatar_url"
        case location
        case currency
        case updatedAt = "updated_at"
    }
}

enum SupabaseError: LocalizedError {
    case userNotFound
    case invalidCredentials
    case networkError
    case imageCompressionFailed
    case invalidOTP
    case otpExpired
    case samePassword
    case custom(String)
    
    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "User not found"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network connection error"
        case .imageCompressionFailed:
            return "Failed to compress image"
        case .invalidOTP:
            return "Invalid verification code"
        case .otpExpired:
            return "Verification code has expired"
        case .samePassword:
            return "New password cannot be the same as the old password"
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Password Reset OTP Model
struct PasswordResetOTP: Codable {
    let email: String
    let otp: String
    let expiresAt: Date
    let used: Bool
    
    enum CodingKeys: String, CodingKey {
        case email
        case otp
        case expiresAt = "expires_at"
        case used
    }
}
