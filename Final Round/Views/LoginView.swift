import SwiftUI
import Lottie
import UIKit

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var supabase = SupabaseService.shared
    
    // Form fields with character limits
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    
    // Security: Input validation state
    @State private var emailValidationError: String?
    @State private var passwordValidationError: String?
    @State private var nameValidationError: String?
    
    // UI state
    @State private var isCreatingAccount = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorBanner = false
    @State private var shakeOffset: CGFloat = 0
    @State private var passwordHasError = false
    @State private var isPasswordVisible = false
    @State private var showAccountNotFoundAlert = false
    
    // Forgot password state
    @State private var showForgotPasswordSheet = false
    @State private var resetEmail = ""
    @State private var isResettingPassword = false
    @State private var showResetSuccessAlert = false
    @State private var resetErrorMessage: String?
    @State private var resetFlowStep: PasswordResetStep = .enterEmail
    @State private var otpCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    
    enum PasswordResetStep {
        case enterEmail
        case enterOTP
        case enterNewPassword
    }
    
    // Keyboard management
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password, name
    }
    
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 20)
                    
                    // Lottie Animation
                    LottieView(animation: .named("Login"))
                        .playing(loopMode: .loop)
                        .animationSpeed(1.0)
                        .frame(width: 200, height: 200)
                    
                    // Welcome Text
                    Text(isCreatingAccount ? "Create Account" : "Welcome Back")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    // Form Card
                    VStack(spacing: 20) {
                    // Full Name (Create Account only)
                    if isCreatingAccount {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                            Text("Full Name")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                Spacer()
                                // Security: Character count indicator
                                if fullName.count > InputSanitizer.Limits.fullName - 20 {
                                    Text("\(fullName.count)/\(InputSanitizer.Limits.fullName)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(fullName.count > InputSanitizer.Limits.fullName ? AppTheme.softRed : AppTheme.textSecondary)
                                }
                            }
                            
                            ZStack(alignment: .leading) {
                                if fullName.isEmpty {
                                    Text("John Doe")
                                        .font(.system(size: 16))
                                        .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                                        .padding(.horizontal, 16)
                                }
                                TextField("", text: $fullName)
                                    .textFieldStyle(LoginTextFieldStyle(hasError: nameValidationError != nil))
                                    .textContentType(.name)
                                    .autocorrectionDisabled(true)
                                    .focused($focusedField, equals: .name)
                                    .submitLabel(.next)
                                    .onSubmit {
                                        handleKeyboardAction()
                                    }
                                    // Security: Enforce character limit
                                    .onChange(of: fullName) { _, newValue in
                                        if newValue.count > InputSanitizer.Limits.fullName {
                                            fullName = String(newValue.prefix(InputSanitizer.Limits.fullName))
                                        }
                                        nameValidationError = validateName()
                                    }
                            }
                            
                            // Validation error message
                            if let error = nameValidationError {
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.softRed)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Email
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        
                        ZStack(alignment: .leading) {
                            if email.isEmpty {
                                Text("you@example.com")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                                    .padding(.horizontal, 16)
                            }
                            TextField("", text: $email)
                                .textFieldStyle(LoginTextFieldStyle(hasError: emailValidationError != nil))
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit {
                                    handleKeyboardAction()
                                }
                                // Security: Enforce character limit and validate
                                .onChange(of: email) { _, newValue in
                                    if newValue.count > InputSanitizer.Limits.email {
                                        email = String(newValue.prefix(InputSanitizer.Limits.email))
                                    }
                                    emailValidationError = validateEmail()
                                }
                        }
                        
                        // Validation error message
                        if let error = emailValidationError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.softRed)
                        }
                    }
                    
                    // Password
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        
                        ZStack(alignment: .trailing) {
                            ZStack(alignment: .leading) {
                                if password.isEmpty {
                                    Text("••••••••")
                                        .font(.system(size: 16))
                                        .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                                        .padding(.horizontal, 16)
                                }
                                
                                if isPasswordVisible {
                                    TextField("", text: $password)
                                        .textFieldStyle(LoginTextFieldStyle(hasError: passwordHasError || passwordValidationError != nil))
                                        .textContentType(isCreatingAccount ? .newPassword : .password)
                                        .focused($focusedField, equals: .password)
                                        .submitLabel(isFormValid ? (isCreatingAccount ? .go : .go) : .done)
                                        .onSubmit {
                                            handleKeyboardAction()
                                        }
                                        // Security: Enforce character limit
                                        .onChange(of: password) { _, newValue in
                                            if newValue.count > InputSanitizer.Limits.password {
                                                password = String(newValue.prefix(InputSanitizer.Limits.password))
                                            }
                                            passwordValidationError = validatePassword()
                                        }
                                } else {
                                    SecureField("", text: $password)
                                        .textFieldStyle(LoginTextFieldStyle(hasError: passwordHasError || passwordValidationError != nil))
                                        .textContentType(isCreatingAccount ? .newPassword : .password)
                                        .focused($focusedField, equals: .password)
                                        .submitLabel(isFormValid ? (isCreatingAccount ? .go : .go) : .done)
                                        .onSubmit {
                                            handleKeyboardAction()
                                        }
                                        // Security: Enforce character limit
                                        .onChange(of: password) { _, newValue in
                                            if newValue.count > InputSanitizer.Limits.password {
                                                password = String(newValue.prefix(InputSanitizer.Limits.password))
                                            }
                                            passwordValidationError = validatePassword()
                                        }
                                }
                            }
                            
                            // Show/Hide Password Toggle
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    isPasswordVisible.toggle()
                                }
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(width: 44, height: 44)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(.trailing, 4)
                        }
                        .offset(x: shakeOffset)
                        
                        // Validation error message
                        if let error = passwordValidationError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.softRed)
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.cardBackground)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, 24)
                
                // Action Buttons
                VStack(spacing: 16) {
                    // Primary Action Button
                    Button {
                        handlePrimaryAction()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(isCreatingAccount ? "Create Account" : "Sign In")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isLoading || !isFormValid)
                    .opacity(isFormValid ? 1 : 0.5)
                    
                    // Forgot Password (only in sign-in mode)
                    if !isCreatingAccount {
                        Button {
                            resetEmail = email // Pre-fill with current email
                            showForgotPasswordSheet = true
                        } label: {
                            Text("Forgot Password?")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .disabled(isLoading)
                    }
                    
                    // Toggle Mode Button
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isCreatingAccount.toggle()
                            clearError()
                            focusedField = nil
                        }
                    } label: {
                        Text(isCreatingAccount ? "Already have an account? Sign In" : "Don't have an account? Create one")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.primary)
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal, 24)
                
                Spacer().frame(height: 100)
            }
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Floating Error Banner Overlay
            VStack {
                if showErrorBanner, let error = errorMessage {
                    FloatingErrorBanner(message: error)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
                Spacer()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showErrorBanner)
        }
        .onTapGesture {
            focusedField = nil
        }
        .sheet(isPresented: $showForgotPasswordSheet, onDismiss: {
            // Reset state when sheet is dismissed
            resetFlowStep = .enterEmail
            otpCode = ""
            newPassword = ""
            confirmPassword = ""
            resetErrorMessage = nil
        }) {
            PasswordResetFlowView(
                step: $resetFlowStep,
                email: $resetEmail,
                otpCode: $otpCode,
                newPassword: $newPassword,
                confirmPassword: $confirmPassword,
                isLoading: $isResettingPassword,
                errorMessage: $resetErrorMessage,
                onSendOTP: handleSendOTP,
                onVerifyOTP: handleVerifyOTP,
                onResetPassword: handleResetPassword,
                onDismiss: { showForgotPasswordSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
        .alert("Password Reset Successful", isPresented: $showResetSuccessAlert) {
            Button("OK", role: .cancel) {
                showForgotPasswordSheet = false
            }
        } message: {
            Text("Your password has been reset successfully. You can now sign in with your new password.")
        }
        .alert("Sign In Failed", isPresented: $showAccountNotFoundAlert) {
            Button("Create Account") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isCreatingAccount = true
                    password = "" // Clear password for fresh start
                    clearError()
                }
            }
            Button("Try Again", role: .cancel) {
                password = "" // Clear password to retry
                triggerPasswordShake()
            }
        } message: {
            Text("The email or password you entered is incorrect. If you don't have an account, you can create one now.")
        }
        .onAppear {
            // Determine default view based on app state
            if appState.justSignedOut {
                // User just signed out - show sign in view
                isCreatingAccount = false
                appState.justSignedOut = false
            } else if appState.justDeletedAccount {
                // User just deleted account - show create account view
                isCreatingAccount = true
                appState.justDeletedAccount = false
            } else if !UserDefaults.standard.bool(forKey: "hasEverSignedIn") {
                // First time user - show create account view
                isCreatingAccount = true
            }
        }
    }
    
    private var isFormValid: Bool {
        // Security: Validate all inputs
        let emailValid = InputSanitizer.isValidEmail(email)
        let passwordValid = InputSanitizer.isValidPassword(password).isValid
        
        if isCreatingAccount {
            let nameValid = !fullName.trimmingCharacters(in: .whitespaces).isEmpty &&
                            fullName.count <= InputSanitizer.Limits.fullName
            return emailValid && passwordValid && nameValid
        } else {
            return emailValid && passwordValid
        }
    }
    
    // Security: Detailed validation for showing errors
    private func validateEmail() -> String? {
        guard !email.isEmpty else { return nil }
        if email.count > InputSanitizer.Limits.email {
            return "Email is too long"
        }
        if !InputSanitizer.isValidEmail(email) {
            return "Please enter a valid email address"
        }
        return nil
    }
    
    private func validatePassword() -> String? {
        guard !password.isEmpty else { return nil }
        let result = InputSanitizer.isValidPassword(password)
        return result.isValid ? nil : result.message
    }
    
    private func validateName() -> String? {
        guard !fullName.isEmpty else { return nil }
        if fullName.count > InputSanitizer.Limits.fullName {
            return "Name is too long (max \(InputSanitizer.Limits.fullName) characters)"
        }
        return nil
    }
    
    private var keyboardButtonText: String {
        guard let focused = focusedField else { return "Done" }
        
        switch focused {
        case .name:
            return "Next"
        case .email:
            return "Next"
        case .password:
            return isFormValid ? (isCreatingAccount ? "Create Account" : "Sign In") : "Done"
        }
    }
    
    private func handleKeyboardAction() {
        guard let focused = focusedField else { return }
        
        switch focused {
        case .name:
            // Move to email
            focusedField = .email
        case .email:
            // Move to password
            focusedField = .password
        case .password:
            // Submit if form is valid
            if isFormValid {
                handlePrimaryAction()
            } else {
                focusedField = nil
            }
        }
    }
    
    private func handlePrimaryAction() {
        guard !isLoading, isFormValid else { return }
        focusedField = nil
        clearError()
        
        if isCreatingAccount {
            handleCreateAccount()
        } else {
            handleLogin()
        }
    }
    
    private func handleLogin() {
        isLoading = true
        
        Task {
            do {
                try await supabase.signIn(email: email, password: password)
                
                // Check if user has completed profile setup
                let profileExists = try await supabase.checkProfileExists()
                
                // Check if profile has all required fields (not just exists)
                var hasCompleteProfile = false
                if profileExists, let profile = try? await supabase.fetchProfile() {
                    // Profile is complete if it has targetRole and skills
                    hasCompleteProfile = !profile.targetRole.isEmpty && !profile.skills.isEmpty
                }
                
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasEverSignedIn")
                    appState.hasCompletedOnboarding = true
                    appState.isLoggedIn = true
                    appState.hasProfileSetup = hasCompleteProfile
                    appState.completeSignIn()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                    isLoading = false
                }
            }
        }
    }
    
    private func handleCreateAccount() {
        isLoading = true
        
        Task {
            do {
                try await supabase.signUp(email: email, password: password, fullName: fullName)
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasEverSignedIn")
                    appState.hasCompletedOnboarding = true
                    appState.isLoggedIn = true
                    // Keep hasProfileSetup = false to trigger ProfileSetupView
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                    isLoading = false
                }
            }
        }
    }
    
    private func handleError(_ error: Error) {
        // Parse error message
        let errorText = error.localizedDescription
        
        // Check for invalid login credentials (covers both "user not found" and "wrong password")
        if errorText.contains("Invalid login credentials") || errorText.contains("invalid_grant") {
            // Immediately show the alert with options to create account or try again
            // This provides better UX than making user guess if account exists
            showAccountNotFoundAlert = true
            return
        } else if errorText.lowercased().contains("user not found") || 
                  errorText.lowercased().contains("no user found") ||
                  errorText.lowercased().contains("user does not exist") {
            // Account doesn't exist - show alert
            showAccountNotFoundAlert = true
            return
        } else if errorText.contains("User already registered") {
            errorMessage = "This email is already registered. Please sign in instead."
        } else {
            errorMessage = errorText
        }
        
        // Show error banner
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showErrorBanner = true
        }
        
        // Auto-hide error after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            clearError()
        }
    }
    
    private func triggerPasswordShake() {
        // Mark password field as having error
        passwordHasError = true
        
        // Smooth shake animation sequence
        let shakeDuration: Double = 0.08
        let shakeDistance: CGFloat = 10
        
        withAnimation(.easeInOut(duration: shakeDuration)) {
            shakeOffset = shakeDistance
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + shakeDuration) {
            withAnimation(.easeInOut(duration: shakeDuration)) {
                shakeOffset = -shakeDistance
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + shakeDuration * 2) {
            withAnimation(.easeInOut(duration: shakeDuration)) {
                shakeOffset = shakeDistance * 0.5
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + shakeDuration * 3) {
            withAnimation(.easeInOut(duration: shakeDuration)) {
                shakeOffset = -shakeDistance * 0.5
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + shakeDuration * 4) {
            withAnimation(.easeInOut(duration: shakeDuration * 1.5)) {
                shakeOffset = 0
            }
        }
    }
    
    private func clearError() {
        withAnimation {
            showErrorBanner = false
            errorMessage = nil
            shakeOffset = 0
            passwordHasError = false
        }
    }
    
    private func handleSendOTP() {
        guard !resetEmail.isEmpty else {
            resetErrorMessage = "Please enter your email address"
            return
        }
        
        // Basic email validation
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        guard resetEmail.range(of: emailRegex, options: .regularExpression) != nil else {
            resetErrorMessage = "Please enter a valid email address"
            return
        }
        
        isResettingPassword = true
        resetErrorMessage = nil
        
        Task {
            do {
                print("🔄 [UI] Initiating OTP send for: \(resetEmail)")
                try await supabase.sendPasswordResetOTP(email: resetEmail)
                print("✅ [UI] OTP sent successfully, moving to verification step")
                await MainActor.run {
                    isResettingPassword = false
                    resetFlowStep = .enterOTP
                }
            } catch let error as SupabaseError {
                print("❌ [UI] SupabaseError: \(error)")
                await MainActor.run {
                    isResettingPassword = false
                    switch error {
                    case .custom(let message):
                        resetErrorMessage = message
                    default:
                        resetErrorMessage = "Failed to send verification code. Please try again."
                    }
                }
            } catch {
                print("❌ [UI] Unknown error: \(error)")
                print("❌ [UI] Error description: \(error.localizedDescription)")
                await MainActor.run {
                    isResettingPassword = false
                    resetErrorMessage = "Failed to send verification code: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleVerifyOTP() {
        guard otpCode.count == 6 else {
            resetErrorMessage = "Please enter the 6-digit code"
            return
        }
        
        isResettingPassword = true
        resetErrorMessage = nil
        
        Task {
            do {
                let isValid = try await supabase.verifyPasswordResetOTP(email: resetEmail, otp: otpCode)
                await MainActor.run {
                    isResettingPassword = false
                    if isValid {
                        resetFlowStep = .enterNewPassword
                    } else {
                        resetErrorMessage = "Invalid or expired verification code"
                    }
                }
            } catch {
                await MainActor.run {
                    isResettingPassword = false
                    resetErrorMessage = "Failed to verify code. Please try again."
                }
            }
        }
    }
    
    private func handleResetPassword() {
        guard !newPassword.isEmpty else {
            resetErrorMessage = "Please enter a new password"
            return
        }
        
        guard newPassword.count >= 6 else {
            resetErrorMessage = "Password must be at least 6 characters"
            return
        }
        
        guard newPassword == confirmPassword else {
            resetErrorMessage = "Passwords do not match"
            return
        }
        
        isResettingPassword = true
        resetErrorMessage = nil
        
        Task {
            do {
                // Check if new password is different from old
                let isDifferent = try await supabase.verifyPasswordIsDifferent(email: resetEmail, password: newPassword)
                
                guard isDifferent else {
                    await MainActor.run {
                        isResettingPassword = false
                        resetErrorMessage = "New password cannot be the same as your old password"
                    }
                    return
                }
                
                print("🔄 [UI] Calling resetPasswordWithOTP...")
                try await supabase.resetPasswordWithOTP(email: resetEmail, otp: otpCode, newPassword: newPassword)
                print("✅ [UI] Password reset successful")
                await MainActor.run {
                    isResettingPassword = false
                    showResetSuccessAlert = true
                }
            } catch let error as SupabaseError {
                print("❌ [UI] SupabaseError: \(error)")
                await MainActor.run {
                    isResettingPassword = false
                    resetErrorMessage = error.errorDescription ?? "Failed to reset password"
                }
            } catch {
                print("❌ [UI] Unknown error: \(error)")
                print("❌ [UI] Error description: \(error.localizedDescription)")
                await MainActor.run {
                    isResettingPassword = false
                    resetErrorMessage = "Failed to reset password: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.softRed)
        )
        .shadow(color: AppTheme.softRed.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Floating Error Banner (Overlay)
struct FloatingErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.softRed)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 12, y: 6)
    }
}

// MARK: - Login Text Field Style with Error State
struct LoginTextFieldStyle: TextFieldStyle {
    var hasError: Bool = false
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16))
            .foregroundStyle(AppTheme.textPrimary)
            .tint(AppTheme.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.controlBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(hasError ? AppTheme.softRed : AppTheme.border, lineWidth: hasError ? 2 : 1)
                    )
            )
    }
}

// MARK: - Password Reset Flow View
struct PasswordResetFlowView: View {
    @Binding var step: LoginView.PasswordResetStep
    @Binding var email: String
    @Binding var otpCode: String
    @Binding var newPassword: String
    @Binding var confirmPassword: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    
    let onSendOTP: () -> Void
    let onVerifyOTP: () -> Void
    let onResetPassword: () -> Void
    let onDismiss: () -> Void
    
    @State private var isNewPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (fixed at top)
            headerView
            
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= stepIndex ? AppTheme.primary : AppTheme.border)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case .enterEmail:
                        emailStepContent
                    case .enterOTP:
                        otpStepContent
                    case .enterNewPassword:
                        newPasswordStepContent
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 14))
                            Text(error)
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(AppTheme.softRed)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40) // Extra padding for keyboard
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppTheme.cardBackground)
    }
    
    private var headerView: some View {
        HStack {
            if step != .enterEmail {
                Button {
                    withAnimation {
                        switch step {
                        case .enterOTP:
                            step = .enterEmail
                        case .enterNewPassword:
                            step = .enterOTP
                        default:
                            break
                        }
                        errorMessage = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(8)
                        .background(AppTheme.background)
                        .clipShape(Circle())
                }
            }
            
            Text(headerTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(8)
                    .background(AppTheme.background)
                    .clipShape(Circle())
            }
        }
        .padding(20)
    }
    
    private var headerTitle: String {
        switch step {
        case .enterEmail: return "Reset Password"
        case .enterOTP: return "Verify Code"
        case .enterNewPassword: return "New Password"
        }
    }
    
    private var stepIndex: Int {
        switch step {
        case .enterEmail: return 0
        case .enterOTP: return 1
        case .enterNewPassword: return 2
        }
    }
    
    // MARK: - Step 1: Enter Email
    private var emailStepContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter your email address and we'll send you a verification code to reset your password.")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                
                ZStack(alignment: .leading) {
                    if email.isEmpty {
                        Text("you@example.com")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                            .padding(.horizontal, 16)
                    }
                    TextField("", text: $email)
                        .textFieldStyle(LoginTextFieldStyle(hasError: errorMessage != nil))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.send)
                        .onSubmit {
                            if !email.isEmpty && !isLoading {
                                onSendOTP()
                            }
                        }
                }
            }
            
            Button {
                onSendOTP()
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Send Verification Code")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading || email.isEmpty)
            .opacity(email.isEmpty ? 0.5 : 1)
        }
    }
    
    // MARK: - Step 2: Enter OTP
    private var otpStepContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("We've sent a 6-digit verification code to \(email). Enter it below.")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Verification Code")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                
                // OTP Input with auto-submit when complete
                OTPInputView(code: $otpCode, onComplete: {
                    if !isLoading {
                        onVerifyOTP()
                    }
                })
            }
            
            Button {
                onVerifyOTP()
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Verify Code")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading || otpCode.count != 6)
            .opacity(otpCode.count != 6 ? 0.5 : 1)
            
            // Resend code button
            Button {
                otpCode = ""
                errorMessage = nil
                onSendOTP()
            } label: {
                Text("Didn't receive code? Resend")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
            }
            .disabled(isLoading)
        }
    }
    
    // MARK: - Step 3: Enter New Password
    private var newPasswordStepContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create a new password for your account. Make sure it's different from your previous password.")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // New Password
            VStack(alignment: .leading, spacing: 8) {
                Text("New Password")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                
                ZStack(alignment: .trailing) {
                    ZStack(alignment: .leading) {
                        if newPassword.isEmpty {
                            Text("••••••••")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                                .padding(.horizontal, 16)
                        }
                        
                        if isNewPasswordVisible {
                            TextField("", text: $newPassword)
                                .textFieldStyle(LoginTextFieldStyle(hasError: errorMessage != nil))
                                .textContentType(.newPassword)
                                .submitLabel(.next)
                        } else {
                            SecureField("", text: $newPassword)
                                .textFieldStyle(LoginTextFieldStyle(hasError: errorMessage != nil))
                                .textContentType(.newPassword)
                                .submitLabel(.next)
                        }
                    }
                    
                    Button {
                        isNewPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isNewPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .padding(.trailing, 4)
                }
            }
            
            // Confirm Password
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                
                ZStack(alignment: .trailing) {
                    ZStack(alignment: .leading) {
                        if confirmPassword.isEmpty {
                            Text("••••••••")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                                .padding(.horizontal, 16)
                        }
                        
                        if isConfirmPasswordVisible {
                            TextField("", text: $confirmPassword)
                                .textFieldStyle(LoginTextFieldStyle(hasError: errorMessage != nil))
                                .textContentType(.newPassword)
                                .submitLabel(.done)
                                .onSubmit {
                                    if !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword.count >= 6 && !isLoading {
                                        onResetPassword()
                                    }
                                }
                        } else {
                            SecureField("", text: $confirmPassword)
                                .textFieldStyle(LoginTextFieldStyle(hasError: errorMessage != nil))
                                .textContentType(.newPassword)
                                .submitLabel(.done)
                                .onSubmit {
                                    if !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword.count >= 6 && !isLoading {
                                        onResetPassword()
                                    }
                                }
                        }
                    }
                    
                    Button {
                        isConfirmPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isConfirmPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .padding(.trailing, 4)
                }
            }
            
            // Password requirements hint
            if !newPassword.isEmpty && newPassword.count < 6 {
                Text("Password must be at least 6 characters")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            Button {
                onResetPassword()
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Reset Password")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading || newPassword.isEmpty || confirmPassword.isEmpty || newPassword.count < 6)
            .opacity((newPassword.isEmpty || confirmPassword.isEmpty || newPassword.count < 6) ? 0.5 : 1)
        }
    }
}

// MARK: - OTP Input View
struct OTPInputView: View {
    @Binding var code: String
    var onComplete: (() -> Void)? = nil
    @FocusState private var isFocused: Bool
    
    let codeLength = 6
    
    var body: some View {
        ZStack {
            // Hidden text field
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0)
                .onChange(of: code) { _, newValue in
                    // Only allow digits
                    var filtered = newValue.filter { $0.isNumber }
                    // Limit to 6 digits
                    if filtered.count > codeLength {
                        filtered = String(filtered.prefix(codeLength))
                    }
                    if filtered != code {
                        code = filtered
                    }
                    // Auto-submit when complete
                    if code.count == codeLength {
                        onComplete?()
                    }
                }
            
            // Visual OTP boxes
            HStack(spacing: 8) {
                ForEach(0..<codeLength, id: \.self) { index in
                    OTPDigitBox(
                        digit: getDigit(at: index),
                        isCurrent: code.count == index,
                        isFilled: code.count > index
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }
        }
        .onAppear {
            isFocused = true
        }
    }
    
    private func getDigit(at index: Int) -> String {
        guard index < code.count else { return "" }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }
}

struct OTPDigitBox: View {
    let digit: String
    let isCurrent: Bool
    let isFilled: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.controlBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isCurrent ? AppTheme.primary : AppTheme.border, lineWidth: isCurrent ? 2 : 1)
                )
            
            Text(digit)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(width: 48, height: 56)
    }
}

#Preview {
    NavigationStack {
        LoginView()
            .environmentObject(AppState())
    }
}
