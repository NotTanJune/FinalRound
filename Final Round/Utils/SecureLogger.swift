import Foundation
import os.log

/// Secure logging utility that only logs in DEBUG builds
/// Prevents sensitive data exposure in production
enum SecureLogger {
    
    // MARK: - Log Categories
    
    enum Category: String {
        case auth = "Auth"
        case api = "API"
        case audio = "Audio"
        case camera = "Camera"
        case database = "Database"
        case network = "Network"
        case security = "Security"
        case general = "General"
        
        var emoji: String {
            switch self {
            case .auth: return "🔐"
            case .api: return "📡"
            case .audio: return "🎤"
            case .camera: return "📷"
            case .database: return "💾"
            case .network: return "🌐"
            case .security: return "🛡️"
            case .general: return "📝"
            }
        }
        
        var osLog: OSLog {
            return OSLog(subsystem: Bundle.main.bundleIdentifier ?? "FinalRound", category: rawValue)
        }
    }
    
    enum Level {
        case debug
        case info
        case warning
        case error
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
    }
    
    // MARK: - Public Logging Methods
    
    /// Logs a debug message (DEBUG builds only)
    static func debug(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    /// Logs an info message (DEBUG builds only)
    static func info(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }
    
    /// Logs a warning message (DEBUG builds only)
    static func warning(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }
    
    /// Logs an error message (DEBUG builds only, but can be configured for production)
    static func error(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    /// Logs API request details (sanitized)
    static func apiRequest(_ endpoint: String, method: String = "GET", category: Category = .api) {
        #if DEBUG
        debug("\(method) \(sanitizeURL(endpoint))", category: category)
        #endif
    }
    
    /// Logs API response (sanitized)
    static func apiResponse(_ endpoint: String, statusCode: Int, category: Category = .api) {
        #if DEBUG
        let emoji = statusCode >= 200 && statusCode < 300 ? "✅" : "❌"
        debug("\(emoji) Response \(statusCode) from \(sanitizeURL(endpoint))", category: category)
        #endif
    }
    
    /// Logs authentication events (email redacted)
    static func authEvent(_ event: String, email: String? = nil, category: Category = .auth) {
        #if DEBUG
        if let email = email {
            debug("\(event) for \(redactEmail(email))", category: category)
        } else {
            debug(event, category: category)
        }
        #endif
    }
    
    /// Logs transcription events (content truncated)
    static func transcription(_ event: String, preview: String? = nil, category: Category = .audio) {
        #if DEBUG
        if let preview = preview {
            let truncated = truncateForLog(preview, maxLength: 50)
            debug("\(event): \(truncated)", category: category)
        } else {
            debug(event, category: category)
        }
        #endif
    }
    
    /// Logs database operations
    static func database(_ operation: String, table: String? = nil, category: Category = .database) {
        #if DEBUG
        if let table = table {
            debug("\(operation) on \(table)", category: category)
        } else {
            debug(operation, category: category)
        }
        #endif
    }
    
    /// Logs security-related events
    static func security(_ event: String, category: Category = .security) {
        #if DEBUG
        warning(event, category: category)
        #endif
    }
    
    // MARK: - Private Implementation
    
    private static func log(_ message: String, level: Level, category: Category, file: String, function: String, line: Int) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        let formattedMessage = "\(level.emoji) \(category.emoji) [\(category.rawValue)] \(message)"
        
        // Print to console
        print("\(formattedMessage) (\(filename):\(line))")
        
        // Also log to unified logging system (visible in Console.app)
        os_log("%{public}@", log: category.osLog, type: level.osLogType, message)
        #endif
    }
    
    // MARK: - Data Sanitization for Logs
    
    /// Redacts email address for logging
    private static func redactEmail(_ email: String) -> String {
        guard let atIndex = email.firstIndex(of: "@") else {
            return "***@***.***"
        }
        
        let localPart = String(email[..<atIndex])
        let domain = String(email[atIndex...])
        
        let visibleChars = min(2, localPart.count)
        let redactedLocal = String(localPart.prefix(visibleChars)) + String(repeating: "*", count: max(0, localPart.count - visibleChars))
        
        return redactedLocal + domain
    }
    
    /// Sanitizes URL by removing query parameters with sensitive data
    private static func sanitizeURL(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url }
        
        // Remove or redact sensitive query parameters
        let sensitiveParams = ["key", "token", "secret", "password", "api_key", "apikey", "auth"]
        
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                if sensitiveParams.contains(where: { item.name.lowercased().contains($0) }) {
                    return URLQueryItem(name: item.name, value: "***REDACTED***")
                }
                return item
            }
        }
        
        return components.string ?? url
    }
    
    /// Truncates content for logging with ellipsis
    private static func truncateForLog(_ content: String, maxLength: Int) -> String {
        guard content.count > maxLength else { return content }
        return String(content.prefix(maxLength)) + "..."
    }
    
    // MARK: - Production Error Reporting (Optional)
    
    /// Reports critical errors that should be tracked even in production
    /// This could be integrated with crash reporting services like Crashlytics
    static func reportCriticalError(_ error: Error, context: [String: Any]? = nil) {
        // In production, this would send to a crash reporting service
        // For now, we just log it in debug mode
        #if DEBUG
        var message = "Critical Error: \(error.localizedDescription)"
        if let context = context {
            message += " | Context: \(context)"
        }
        self.error(message, category: .security)
        #endif
        
        // TODO: Integrate with crash reporting service for production
        // Crashlytics.crashlytics().record(error: error)
    }
}

// MARK: - Convenience Extensions

extension Error {
    /// Logs this error securely
    func logSecurely(category: SecureLogger.Category = .general) {
        SecureLogger.error(localizedDescription, category: category)
    }
}

