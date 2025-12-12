import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';

/// Password reset step enum
enum PasswordResetStep { enterEmail, enterOTP, enterNewPassword }

/// Forgot password screen - sends magic link via Supabase
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _linkSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSendResetLink() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showError('Please enter your email address');
      return;
    }

    if (!_isValidEmail(email)) {
      _showError('Please enter a valid email address');
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.requestPasswordReset(email);

    if (success && mounted) {
      setState(() => _linkSent = true);
      _showSnackBar('Password reset link sent to your email');

      // Auto-pop after 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        Navigator.pop(context);
      }
    } else if (mounted) {
      _showError(auth.errorMessage ?? 'Failed to send reset link');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.background(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Reset Password',
          style: AppTheme.headline(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (_linkSent) {
                return _buildSuccessScreen();
              }

              return _buildResetForm(auth);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResetForm(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        
        // Icon
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withOpacity(0.1),
            ),
            child: const Icon(
              Icons.mail_outline,
              size: 40,
              color: AppTheme.primary,
            ),
          ),
        ),
        
        const SizedBox(height: 32),
        
        // Title
        Text(
          'Forgot Your Password?',
          style: AppTheme.title(context),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 12),
        
        // Description
        Text(
          'Enter your email and we\'ll send you a link to reset your password.',
          style: AppTheme.body(context).copyWith(
            color: AppTheme.textSecondary(context),
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 32),
        
        // Email field
        TextField(
          controller: _emailController,
          enabled: !auth.isLoading,
          decoration: InputDecoration(
            hintText: 'Email address',
            hintStyle: TextStyle(color: AppTheme.textSecondary(context)),
            filled: true,
            fillColor: AppTheme.inputBackground(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.border(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.border(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        
        const SizedBox(height: 24),
        
        // Send button
        ElevatedButton(
          onPressed: auth.isLoading ? null : _handleSendResetLink,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            disabledBackgroundColor: AppTheme.primary.withOpacity(0.5),
          ),
          child: auth.isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Send Reset Link',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSuccessScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        
        // Success icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.success.withOpacity(0.1),
          ),
          child: Icon(
            Icons.check_circle,
            color: AppTheme.success,
            size: 60,
          ),
        ),
        
        const SizedBox(height: 32),
        
        // Title
        Text(
          'Check Your Email',
          style: AppTheme.title(context),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 12),
        
        // Description
        Text(
          'We\'ve sent a password reset link to ${_emailController.text.trim()}',
          style: AppTheme.body(context).copyWith(
            color: AppTheme.textSecondary(context),
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 12),
        
        Text(
          'Click the link in the email to reset your password. It will expire in 1 hour.',
          style: AppTheme.subheadline(context),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 32),
        
        Text(
          'Returning to login...',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}
