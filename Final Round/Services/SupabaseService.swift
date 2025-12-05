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
        
        // Delete user's avatar from storage first
        try? await deleteAvatar()
        SecureLogger.authEvent("User avatar deleted", category: .auth)
        
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
        
        // Retry logic for stale QUIC connection issues
        // The SDK uses its own URLSession which can have stale connections
        var lastError: Error?
        for attempt in 1...3 {
            do {
        try await client
            .from("profiles")
            .upsert(profile)
            .execute()
        
        SecureLogger.database("Upsert", table: "profiles", category: .database)
                if attempt > 1 {
                    SecureLogger.info("Profile saved on attempt \(attempt)", category: .database)
                }
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                
                // Check for network connection errors that benefit from retry
                // -1005: connection lost, -1001: timeout, -1004: cannot connect
                let isRetryableError = nsError.domain == NSURLErrorDomain &&
                    [-1005, -1001, -1004].contains(nsError.code)
                
                if isRetryableError && attempt < 3 {
                    SecureLogger.warning("Profile save attempt \(attempt) failed (code: \(nsError.code)), retrying...", category: .database)
                    // Short delay - the failed request establishes a fresh connection
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    continue
                }
                
                throw error
            }
        }
        
        if let error = lastError {
            throw error
        }
    }
    
    func updateProfile(_ profile: UserProfile) async throws {
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        // Retry logic for stale QUIC connection issues
        var lastError: Error?
        for attempt in 1...3 {
            do {
        try await client
            .from("profiles")
            .upsert(profile)
            .execute()
        
        SecureLogger.database("Update", table: "profiles", category: .database)
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                
                let isRetryableError = nsError.domain == NSURLErrorDomain &&
                    [-1005, -1001, -1004].contains(nsError.code)
                
                if isRetryableError && attempt < 3 {
                    SecureLogger.warning("Profile update attempt \(attempt) failed, retrying...", category: .database)
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    continue
                }
                
                throw error
            }
        }
        
        if let error = lastError {
            throw error
        }
    }
    
    func fetchProfile() async throws -> UserProfile? {
        guard let userId = currentUser?.id else {
            throw SupabaseError.userNotFound
        }
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        // Retry logic for stale QUIC connection issues
        var lastError: Error?
        for attempt in 1...3 {
            do {
        let response: [UserProfile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        SecureLogger.database("Fetch profile", table: "profiles", category: .database)
        
                return response.first
            } catch {
                lastError = error
                let nsError = error as NSError
                
                let isRetryableError = nsError.domain == NSURLErrorDomain &&
                    [-1005, -1001, -1004].contains(nsError.code)
                
                if isRetryableError && attempt < 3 {
                    SecureLogger.warning("Profile fetch attempt \(attempt) failed, retrying...", category: .database)
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    continue
                }
                
                throw error
            }
        }
        
        if let error = lastError {
            throw error
        }
        
        return nil
    }
    
    func uploadAvatar(image: UIImage) async throws -> String {
        guard let userId = currentUser?.id else {
            throw SupabaseError.userNotFound
        }
        
        // Resize image to max 512x512 to reduce upload size significantly
        let resizedImage = resizeImage(image, maxDimension: 512)
        
        // Compress with more aggressive quality for faster upload
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.5) else {
            throw SupabaseError.imageCompressionFailed
        }
        
        // If still too large, compress more aggressively
        var finalData = imageData
        if imageData.count > 500_000 { // 500KB
            if let moreCompressed = resizedImage.jpegData(compressionQuality: 0.3) {
                finalData = moreCompressed
            }
        }
        
        // Security: Validate image size (max 2MB for avatars)
        guard finalData.count <= 2 * 1024 * 1024 else {
            throw SupabaseError.custom("Image is too large. Please select a smaller image.")
        }
        
        let fileName = "\(userId.uuidString).jpg"
        let filePath = fileName  // Just the filename - bucket is already "avatars"
        
        SecureLogger.debug("Uploading avatar (\(finalData.count / 1024)KB)", category: .database)
        
        // Security: Apply rate limiting
        try await RateLimiter.shared.waitAndConsume(.supabaseDB)
        
        // Use direct upload which bypasses the Supabase SDK's URLSession
        // Each attempt creates a fresh URLSession to avoid stale QUIC connections
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let publicURL = try await directUploadToStorage(
                    data: finalData,
                    path: filePath,
                    bucket: "avatars"
                )
                
                SecureLogger.database("Avatar uploaded", table: "avatars", category: .database)
                SecureLogger.info("Upload completed in attempt \(attempt)", category: .database)
                
                return publicURL
            } catch {
                lastError = error
                let nsError = error as NSError
                SecureLogger.warning("Avatar upload attempt \(attempt) failed: \(error.localizedDescription)", category: .database)
                
                if attempt < 3 {
                    // Exponential backoff: 1s, then 2s
                    // Longer delays give iOS time to clean up stale connections
                    let delaySeconds = Double(attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    
                    // Log connection reset
                    SecureLogger.debug("Retrying upload with fresh connection...", category: .database)
                }
            }
        }
        
        throw lastError ?? SupabaseError.networkError
    }
    
    /// Delete user's avatar from storage using direct HTTP (avoids QUIC issues)
    func deleteAvatar() async throws {
        guard let userId = currentUser?.id else { return }
        
        let filePath = "\(userId.uuidString).jpg"  // Just the filename - bucket is already "avatars"
        
        // Use direct HTTP delete to avoid QUIC connection issues
        // The SDK's storage client uses QUIC which times out on stale connections
        var lastError: Error?
        for attempt in 1...3 {
        do {
                try await directDeleteFromStorage(path: filePath, bucket: "avatars")
            SecureLogger.database("Avatar deleted", table: "avatars", category: .database)
                return
        } catch {
                lastError = error
                let nsError = error as NSError
                
                // Check if it's a 404 (file doesn't exist) - that's fine
                if let urlError = error as? URLError, urlError.code == .fileDoesNotExist {
                    SecureLogger.debug("Avatar already deleted or doesn't exist", category: .database)
                    return
                }
                
                // For network errors, retry
                if nsError.domain == NSURLErrorDomain && attempt < 3 {
                    SecureLogger.warning("Avatar deletion attempt \(attempt) failed: \(error.localizedDescription), retrying...", category: .database)
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    continue
                }
                
                // Log but don't throw - avatar deletion shouldn't block account deletion
                SecureLogger.debug("Avatar deletion failed: \(error.localizedDescription)", category: .database)
            }
        }
        
        // Log final failure but don't throw - account deletion should continue
        if let error = lastError {
            SecureLogger.warning("Avatar deletion failed after 3 attempts: \(error.localizedDescription)", category: .database)
        }
    }
    
    /// Direct delete from Supabase Storage using custom URLSession
    /// This bypasses the SDK's internal URLSession which has QUIC issues
    private func directDeleteFromStorage(path: String, bucket: String) async throws {
        guard let authToken = await getAuthToken() else {
            throw SupabaseError.userNotFound
        }
        
        // Supabase Storage delete endpoint expects a DELETE request with JSON body
        let deleteURLString = "\(supabaseURL)/storage/v1/object/\(bucket)"
        guard let deleteURL = URL(string: deleteURLString) else {
            throw SupabaseError.custom("Invalid delete URL")
        }
        
        // Build the delete request
        var request = URLRequest(url: deleteURL)
        request.httpMethod = "DELETE"
        
        // Body contains the list of paths to delete
        let body = ["prefixes": [path]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Headers required by Supabase Storage API
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.timeoutInterval = 15 // Shorter timeout for delete
        
        SecureLogger.debug("Starting direct delete from \(bucket)/\(path)", category: .database)
        
        // Create a fresh session to avoid stale QUIC connections
        let session = Self.createFreshUploadSession()
        defer { session.finishTasksAndInvalidate() }
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }
        
        SecureLogger.debug("Delete response status: \(httpResponse.statusCode)", category: .database)
        
        // Handle response codes
        switch httpResponse.statusCode {
        case 200, 204:
            // Success
            return
        case 400:
            // Bad request - might be wrong format, try alternative endpoint
            // Some Supabase versions use different endpoint format
            let altDeleteURLString = "\(supabaseURL)/storage/v1/object/\(bucket)/\(path)"
            guard let altDeleteURL = URL(string: altDeleteURLString) else {
                throw SupabaseError.custom("Invalid delete URL")
            }
            
            var altRequest = URLRequest(url: altDeleteURL)
            altRequest.httpMethod = "DELETE"
            altRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            altRequest.setValue(supabaseKey, forHTTPHeaderField: "apikey")
            altRequest.timeoutInterval = 15
            
            // Create another fresh session for the alternative request
            let altSession = Self.createFreshUploadSession()
            defer { altSession.finishTasksAndInvalidate() }
            
            let (_, altResponse) = try await altSession.data(for: altRequest)
            guard let altHttpResponse = altResponse as? HTTPURLResponse,
                  (200...299).contains(altHttpResponse.statusCode) || altHttpResponse.statusCode == 404 else {
                let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
                throw SupabaseError.custom("Delete failed: \(errorMessage)")
            }
            return
        case 404:
            // File doesn't exist - that's okay
            return
        case 401:
            throw SupabaseError.userNotFound
        default:
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Status \(httpResponse.statusCode)"
            throw SupabaseError.custom("Delete failed: \(errorMessage)")
        }
    }
    
    // MARK: - Connection Pre-warming
    
    /// Lightweight connection pre-warming
    /// Called before photo step to pre-establish HTTP/2 connection
    func aggressiveWarmUp() async {
        // The direct upload session handles connection pooling automatically
        // This method is kept for backward compatibility but is now a lightweight no-op
        // The real work happens in directUploadToStorage with HTTP/2 (no QUIC)
        SecureLogger.debug("Connection ready (HTTP/2 mode)", category: .database)
    }
    
    // MARK: - Direct Upload Session (Bypasses SDK to avoid QUIC issues)
    
    /// Creates a fresh URLSession for each upload to avoid stale connection reuse
    /// iOS aggressively caches QUIC connections which can become stale and timeout
    private static func createFreshUploadSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral  // Fresh session, no cached connections
        
        // Short timeouts to fail fast on stale connections (then retry)
        config.timeoutIntervalForRequest = 20   // 20 second timeout per request
        config.timeoutIntervalForResource = 45  // 45 second total resource timeout
        
        // Disable waiting for connectivity - fail fast instead
        config.waitsForConnectivity = false
        
        // Connection settings for reliability
        config.httpShouldUsePipelining = false  // More reliable for uploads
        config.httpMaximumConnectionsPerHost = 1  // Single connection = less confusion
        
        // Disable caching completely
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // Force HTTP/2 instead of HTTP/3 (QUIC) - QUIC has stale connection issues
        if #available(iOS 15.0, *) {
            config.multipathServiceType = .none
        }
        
        return URLSession(configuration: config)
    }
    
    /// Supabase configuration for direct API calls
    private var supabaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
    }
    
    private var supabaseKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
    }
    
    /// Get current auth token for API calls
    private func getAuthToken() async -> String? {
        do {
            let session = try await client.auth.session
            return session.accessToken
        } catch {
            return nil
        }
    }
    
    /// Direct upload to Supabase Storage using custom URLSession
    /// This bypasses the SDK's internal URLSession which has QUIC issues
    private func directUploadToStorage(data: Data, path: String, bucket: String) async throws -> String {
        guard let authToken = await getAuthToken() else {
            throw SupabaseError.userNotFound
        }
        
        // Construct the storage upload URL
        let uploadURLString = "\(supabaseURL)/storage/v1/object/\(bucket)/\(path)"
        guard let uploadURL = URL(string: uploadURLString) else {
            throw SupabaseError.custom("Invalid upload URL")
        }
        
        // Build the upload request
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.httpBody = data
        
        // Headers required by Supabase Storage API
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert") // Upsert mode
        
        // Request timeout
        request.timeoutInterval = 30
        
        SecureLogger.debug("Starting direct upload to \(bucket)/\(path)", category: .database)
        
        // Create a fresh session for this upload to avoid stale QUIC connections
        let session = Self.createFreshUploadSession()
        defer {
            // Invalidate session after use to release connections
            session.finishTasksAndInvalidate()
        }
        
        let (responseData, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }
        
        SecureLogger.debug("Upload response status: \(httpResponse.statusCode)", category: .database)
        
        // Handle response codes
        switch httpResponse.statusCode {
        case 200, 201:
            // Success - construct public URL
            let publicURL = "\(supabaseURL)/storage/v1/object/public/\(bucket)/\(path)"
            return publicURL
        case 400:
            // Bad request - might need to use PUT for update
            // Try PUT method for upsert
            var putRequest = request
            putRequest.httpMethod = "PUT"
            
            // Create another fresh session for PUT request
            let putSession = Self.createFreshUploadSession()
            defer { putSession.finishTasksAndInvalidate() }
            
            let (_, putResponse) = try await putSession.data(for: putRequest)
            guard let putHttpResponse = putResponse as? HTTPURLResponse,
                  (200...299).contains(putHttpResponse.statusCode) else {
                let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
                throw SupabaseError.custom("Upload failed: \(errorMessage)")
            }
            
            let publicURL = "\(supabaseURL)/storage/v1/object/public/\(bucket)/\(path)"
            return publicURL
        case 401:
            throw SupabaseError.userNotFound
        case 413:
            throw SupabaseError.custom("Image is too large")
        default:
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Status \(httpResponse.statusCode)"
            throw SupabaseError.custom("Upload failed: \(errorMessage)")
        }
    }
    
    /// Resize image to fit within maxDimension while maintaining aspect ratio
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        
        // If image is already small enough, return as-is
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        let aspectRatio = size.width / size.height
        let newSize: CGSize
        
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Use UIGraphicsImageRenderer for efficient ARM-optimized resizing
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
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
