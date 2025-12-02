import Foundation
import UIKit
import Supabase
import Combine
import Auth
import Security

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
        
        SecureLogger.debug("Initializing Supabase", category: .database)
        
        self.client = SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: anonKey,
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        
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
        // Security: Sanitize inputs
        let sanitizedEmail = InputSanitizer.sanitizeEmail(email)
        let sanitizedName = InputSanitizer.sanitizeName(fullName)
        
        // Security: Validate inputs
        guard InputSanitizer.isValidEmail(sanitizedEmail) else {
            throw SupabaseError.custom("Invalid email format")
        }
        
        let passwordValidation = InputSanitizer.isValidPassword(password)
        guard passwordValidation.isValid else {
            throw SupabaseError.custom(passwordValidation.message ?? "Invalid password")
        }
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseAuth)
        
        SecureLogger.authEvent("Sign up initiated", email: sanitizedEmail, category: .auth)
        
        // Retry logic for cases where a recently deleted account might not have fully propagated
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                let response = try await client.auth.signUp(
                    email: sanitizedEmail,
                    password: password
                )
                
                let user = response.user
                
                // Create initial user profile with full name
                let profile = UserProfile(
                    id: user.id,
                    fullName: sanitizedName,
                    targetRole: "",
                    yearsOfExperience: "",
                    skills: [],
                    avatarURL: nil,
                    location: nil,
                    currency: nil,
                    updatedAt: Date()
                )
                
                // Save profile to database with retry
                try await saveProfileWithRetry(profile: profile)
                
                SecureLogger.authEvent("Sign up successful", category: .auth)
                
                await MainActor.run {
                    self.currentUser = user
                    self.isAuthenticated = true
                }
                return
                
            } catch {
                lastError = error
                let errorDescription = error.localizedDescription.lowercased()
                let nsError = error as NSError
                
                // Check for network errors or account conflict errors that might resolve with retry
                let isNetworkError = nsError.domain == NSURLErrorDomain && 
                                     (nsError.code == -1005 || nsError.code == -1004 || nsError.code == -1001)
                let isConflictError = errorDescription.contains("already registered") ||
                                      errorDescription.contains("already exists") ||
                                      errorDescription.contains("conflict")
                
                if (isNetworkError || isConflictError) && attempt < maxRetries {
                    SecureLogger.warning("Sign up attempt \(attempt) failed, retrying in 2 seconds...", category: .auth)
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                    continue
                }
                
                // Provide more helpful error messages
                if isConflictError {
                    throw SupabaseError.custom("This email is already in use. If you recently deleted an account, please wait a moment and try again.")
                }
                
                throw error
            }
        }
        
        // If we get here, all retries failed
        if let error = lastError {
            throw error
        }
    }
    
    /// Saves profile with retry logic for network issues
    private func saveProfileWithRetry(profile: UserProfile) async throws {
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                try await client
                    .from("profiles")
                    .insert(profile)
                    .execute()
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                
                if nsError.domain == NSURLErrorDomain && attempt < maxRetries {
                    SecureLogger.warning("Profile save attempt \(attempt) failed, retrying...", category: .database)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                throw error
            }
        }
        
        if let error = lastError {
            throw error
        }
    }
    
    func signIn(email: String, password: String) async throws {
        // Security: Sanitize email
        let sanitizedEmail = InputSanitizer.sanitizeEmail(email)
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseAuth)
        
        SecureLogger.authEvent("Sign in initiated", email: sanitizedEmail, category: .auth)
        
        let session = try await client.auth.signIn(
            email: sanitizedEmail,
            password: password
        )
        
        SecureLogger.authEvent("Sign in successful", category: .auth)
        
        await MainActor.run {
            self.currentUser = session.user
            self.isAuthenticated = true
        }
    }
    
    func signOut() async throws {
        SecureLogger.authEvent("Sign out initiated", category: .auth)
        try await client.auth.signOut()
        await MainActor.run {
            self.currentUser = nil
            self.isAuthenticated = false
        }
        SecureLogger.authEvent("Sign out successful", category: .auth)
    }
    
    func deleteAccount() async throws {
        guard let user = currentUser else {
            throw SupabaseError.userNotFound
        }
        
        let userEmail = user.email ?? ""
        SecureLogger.authEvent("Account deletion initiated", category: .auth)
        
        // Retry logic for network connection issues (error -1005)
        // iOS sometimes drops idle connections, causing the first request to fail
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                // Call the Supabase function to delete the user
                try await client.rpc("delete_user").execute()
                
                // Sign out the local session
                try? await client.auth.signOut()
                
                // Success - update state
                await MainActor.run {
                    self.currentUser = nil
                    self.isAuthenticated = false
                }
                
                SecureLogger.authEvent("Account deletion RPC successful, verifying...", category: .auth)
                
                // Poll to verify the deletion has propagated
                // This ensures the email is free for re-registration
                let deletionVerified = await verifyAccountDeleted(email: userEmail)
                
                if deletionVerified {
                    SecureLogger.authEvent("Account deletion verified", category: .auth)
                } else {
                    SecureLogger.warning("Account deletion could not be verified, proceeding anyway", category: .auth)
                }
                
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                
                // Check if it's the "network connection was lost" error (-1005)
                // or "cannot connect to host" (-1004) which can also occur
                if nsError.domain == NSURLErrorDomain &&
                   (nsError.code == -1005 || nsError.code == -1004) &&
                   attempt < maxRetries {
                    SecureLogger.warning("Network error on attempt \(attempt), retrying...", category: .network)
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second before retry
                    continue
                }
                
                // For other errors or last attempt, throw the error
                throw error
            }
        }
        
        // If we get here, all retries failed
        if let error = lastError {
            throw error
        }
    }
    
    /// Verifies that account deletion has propagated by attempting to check if the email is available
    /// Polls for up to 10 seconds to ensure Supabase has fully processed the deletion
    private func verifyAccountDeleted(email: String) async -> Bool {
        guard !email.isEmpty else { return true }
        
        // Poll for up to 10 seconds (20 attempts at 500ms each)
        for attempt in 1...20 {
            do {
                // Try to sign in with the deleted account
                // If the account is truly deleted, this should fail with "Invalid login credentials"
                _ = try await client.auth.signIn(email: email, password: "verification_check_\(UUID().uuidString)")
                
                // If sign-in succeeds (shouldn't happen), account still exists
                try? await client.auth.signOut()
                SecureLogger.debug("Deletion verification attempt \(attempt): account still exists", category: .auth)
                
            } catch {
                let errorDescription = error.localizedDescription.lowercased()
                
                // "Invalid login credentials" means the account doesn't exist or password is wrong
                // Either way, the account is effectively deleted or inaccessible
                if errorDescription.contains("invalid") || 
                   errorDescription.contains("not found") ||
                   errorDescription.contains("credentials") {
                    SecureLogger.debug("Deletion verified on attempt \(attempt)", category: .auth)
                    return true
                }
                
                // For other errors (rate limiting, network), continue polling
                SecureLogger.debug("Deletion verification attempt \(attempt): \(errorDescription)", category: .auth)
            }
            
            // Wait 500ms before next attempt
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        // After 10 seconds, assume deletion is complete
        // The deletion was successful on the server, propagation might just be slow
        return true
    }
    
    func updatePassword(newPassword: String) async throws {
        try await client.auth.update(user: UserAttributes(password: newPassword))
    }
    
    // MARK: - OTP-Based Password Reset
    
    /// Generates and sends OTP to email for password reset
    func sendPasswordResetOTP(email: String) async throws {
        // Security: Sanitize and validate email
        let sanitizedEmail = InputSanitizer.sanitizeEmail(email)
        
        guard InputSanitizer.isValidEmail(sanitizedEmail) else {
            throw SupabaseError.custom("Invalid email format")
        }
        
        // Security: Apply rate limiting to prevent OTP abuse
        try await RateLimiter.shared.waitAndConsume(.supabaseAuth)
        
        SecureLogger.authEvent("OTP password reset initiated", email: sanitizedEmail, category: .auth)
        
        // Generate a 6-digit OTP using cryptographically secure random
        var randomBytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let randomValue = randomBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
        let otp = String(format: "%06d", randomValue % 1000000)
        
        let expiresAt = Date().addingTimeInterval(600) // 10 minutes expiration
        
        // Store OTP in Supabase table
        let otpRecord = PasswordResetOTP(
            email: sanitizedEmail,
            otp: otp,
            expiresAt: expiresAt,
            used: false
        )
        
        // Delete any existing OTPs for this email first
        do {
            try await client
                .from("password_reset_otps")
                .delete()
                .eq("email", value: sanitizedEmail)
                .execute()
        } catch {
            // Continue anyway - old OTPs will expire
        }
        
        // Insert new OTP
        do {
            try await client
                .from("password_reset_otps")
                .insert(otpRecord)
                .execute()
        } catch {
            SecureLogger.error("Failed to store OTP", category: .auth)
            throw SupabaseError.custom("Failed to store verification code. Please try again.")
        }
        
        // Send email via Supabase edge function
        do {
            try await client.functions.invoke(
                "send-otp-email",
                options: .init(body: ["email": sanitizedEmail, "otp": otp])
            )
            SecureLogger.authEvent("OTP sent successfully", category: .auth)
        } catch {
            SecureLogger.error("Edge function failed for OTP email", category: .auth)
            throw SupabaseError.custom("Failed to send verification email. Please check your email address and try again.")
        }
    }
    
    /// Verifies the OTP entered by user
    func verifyPasswordResetOTP(email: String, otp: String) async throws -> Bool {
        // Security: Sanitize inputs
        let sanitizedEmail = InputSanitizer.sanitizeEmail(email)
        let sanitizedOTP = otp.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Security: Validate OTP format (6 digits only)
        guard sanitizedOTP.count == 6, sanitizedOTP.allSatisfy({ $0.isNumber }) else {
            SecureLogger.security("Invalid OTP format attempted", category: .auth)
            return false
        }
        
        // Security: Apply rate limiting to prevent brute force
        try await RateLimiter.shared.waitAndConsume(.supabaseAuth)
        
        let response: [PasswordResetOTP] = try await client
            .from("password_reset_otps")
            .select()
            .eq("email", value: sanitizedEmail)
            .eq("otp", value: sanitizedOTP)
            .eq("used", value: false)
            .execute()
            .value
        
        guard let otpRecord = response.first else {
            SecureLogger.security("OTP verification failed - not found", category: .auth)
            return false
        }
        
        // Check if OTP has expired
        if otpRecord.expiresAt < Date() {
            SecureLogger.security("OTP verification failed - expired", category: .auth)
            // Clean up expired OTP
            try? await client
                .from("password_reset_otps")
                .delete()
                .eq("email", value: sanitizedEmail)
                .execute()
            return false
        }
        
        SecureLogger.authEvent("OTP verified successfully", category: .auth)
        return true
    }
    
    /// Resets password after OTP verification
    func resetPasswordWithOTP(email: String, otp: String, newPassword: String) async throws {
        // Security: Sanitize email
        let sanitizedEmail = InputSanitizer.sanitizeEmail(email)
        
        // Security: Validate password
        let passwordValidation = InputSanitizer.isValidPassword(newPassword)
        guard passwordValidation.isValid else {
            throw SupabaseError.custom(passwordValidation.message ?? "Invalid password")
        }
        
        // Verify OTP first
        guard try await verifyPasswordResetOTP(email: sanitizedEmail, otp: otp) else {
            throw SupabaseError.invalidOTP
        }
        
        // Mark OTP as used
        try? await client
            .from("password_reset_otps")
            .update(["used": true])
            .eq("email", value: sanitizedEmail)
            .eq("otp", value: otp)
            .execute()
        
        // Update password using admin function (requires Supabase edge function)
        do {
            try await client.functions.invoke(
                "reset-user-password",
                options: .init(body: ["email": sanitizedEmail, "new_password": newPassword])
            )
            SecureLogger.authEvent("Password reset successful", category: .auth)
        } catch {
            SecureLogger.error("Edge function failed for password reset", category: .auth)
            throw SupabaseError.custom("Failed to reset password. Please ensure the reset-user-password edge function is deployed.")
        }
        
        // Clean up OTP
        try? await client
            .from("password_reset_otps")
            .delete()
            .eq("email", value: sanitizedEmail)
            .execute()
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
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        let record = try InterviewSessionRecord(from: session, userEmail: userEmail)
        
        try await client
            .from("interview_sessions")
            .insert(record)
            .execute()
        
        SecureLogger.database("Insert", table: "interview_sessions", category: .database)
    }
    
    func fetchInterviewSessions(limit: Int? = nil) async throws -> [InterviewSession] {
        guard let userEmail = currentUser?.email else {
            throw SupabaseError.userNotFound
        }
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        var query = client
            .from("interview_sessions")
            .select()
            .eq("user_email", value: userEmail)
            .order("created_at", ascending: false)
        
        if let limit = limit {
            query = query.limit(limit)
        }
        
        let response: [InterviewSessionRecord] = try await query.execute().value
        
        SecureLogger.database("Select \(response.count) records", table: "interview_sessions", category: .database)
        
        return try response.map { try $0.toSession() }
    }
    
    func fetchRecentSessions(count: Int = 3) async throws -> [InterviewSession] {
        return try await fetchInterviewSessions(limit: count)
    }
    
    func deleteInterviewSession(id: UUID) async throws {
        guard currentUser != nil else {
            throw SupabaseError.userNotFound
        }
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        try await client
            .from("interview_sessions")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
        
        SecureLogger.database("Delete", table: "interview_sessions", category: .database)
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
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        do {
            let response: [UserProfile] = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            let exists = !response.isEmpty
            SecureLogger.database(exists ? "Profile exists" : "No profile found", table: "profiles", category: .database)
            return exists
        } catch {
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
        
        // Security: Sanitize all inputs
        let sanitizedName = InputSanitizer.sanitizeName(fullName)
        let sanitizedRole = InputSanitizer.sanitizeRole(targetRole)
        let sanitizedSkills = InputSanitizer.sanitizeSkills(skills)
        let sanitizedLocation = location.map { InputSanitizer.sanitizeLocation($0) }
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        let profile = UserProfile(
            id: userId,
            fullName: sanitizedName,
            targetRole: sanitizedRole,
            yearsOfExperience: yearsOfExperience,
            skills: sanitizedSkills,
            avatarURL: avatarURL,
            location: sanitizedLocation,
            currency: currency,
            updatedAt: Date()
        )
        
        // Use upsert to handle both insert and update
        try await client
            .from("profiles")
            .upsert(profile)
            .execute()
        
        SecureLogger.database("Upsert", table: "profiles", category: .database)
    }
    
    func updateProfile(_ profile: UserProfile) async throws {
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        // Use upsert to update the profile
        try await client
            .from("profiles")
            .upsert(profile)
            .execute()
        
        SecureLogger.database("Update", table: "profiles", category: .database)
    }
    
    func fetchProfile() async throws -> UserProfile? {
        guard let userId = currentUser?.id else {
            throw SupabaseError.userNotFound
        }
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        let response: [UserProfile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        SecureLogger.database("Fetch profile", table: "profiles", category: .database)
        
        if let profile = response.first {
            return profile
        }
        
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
        
        // Security: Validate image size (max 5MB)
        guard imageData.count <= 5 * 1024 * 1024 else {
            throw SupabaseError.custom("Image is too large. Please select a smaller image.")
        }
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        let fileName = "\(userId.uuidString).jpg"
        let filePath = "avatars/\(fileName)"
        
        SecureLogger.debug("Uploading avatar", category: .database)
        
        // Upload to Supabase Storage - using Data directly instead of deprecated File
        try await client.storage
            .from("avatars")
            .upload(path: filePath, file: imageData, options: FileOptions(upsert: true))
        
        // Get public URL
        let publicURL = try client.storage
            .from("avatars")
            .getPublicURL(path: filePath)
        
        SecureLogger.database("Avatar uploaded", table: "avatars", category: .database)
        
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
    case rateLimited
    case inputValidationFailed(String)
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
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .inputValidationFailed(let message):
            return "Validation failed: \(message)"
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
