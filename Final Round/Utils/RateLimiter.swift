import Foundation

/// Thread-safe rate limiter using the token bucket algorithm
/// Protects against DDoS and API abuse by limiting request frequency
actor RateLimiter {
    
    // MARK: - Configuration
    
    struct Config {
        let maxTokens: Int
        let refillRate: TimeInterval // Seconds per token refill
        let initialTokens: Int
        
        /// Default config for Groq chat completions (10 requests per minute)
        static let groqChat = Config(maxTokens: 10, refillRate: 6.0, initialTokens: 10)
        
        /// Config for Groq transcription (5 requests per minute)
        static let groqTranscription = Config(maxTokens: 5, refillRate: 12.0, initialTokens: 5)
        
        /// Config for Supabase auth (10 requests per minute)
        static let supabaseAuth = Config(maxTokens: 10, refillRate: 6.0, initialTokens: 10)
        
        /// Config for Supabase database (30 requests per minute)
        static let supabaseDB = Config(maxTokens: 30, refillRate: 2.0, initialTokens: 30)
        
        /// Config for general API calls (20 requests per minute)
        static let general = Config(maxTokens: 20, refillRate: 3.0, initialTokens: 20)
    }
    
    enum LimitType: String, CaseIterable {
        case groqChat = "groq_chat"
        case groqTranscription = "groq_transcription"
        case supabaseAuth = "supabase_auth"
        case supabaseDB = "supabase_db"
        case general = "general"
        
        var config: Config {
            switch self {
            case .groqChat: return .groqChat
            case .groqTranscription: return .groqTranscription
            case .supabaseAuth: return .supabaseAuth
            case .supabaseDB: return .supabaseDB
            case .general: return .general
            }
        }
    }
    
    // MARK: - Errors
    
    enum RateLimitError: LocalizedError {
        case rateLimited(retryAfter: TimeInterval)
        case tooManyRetries
        
        var errorDescription: String? {
            switch self {
            case .rateLimited(let retryAfter):
                return "Rate limited. Please try again in \(Int(retryAfter)) seconds."
            case .tooManyRetries:
                return "Too many retry attempts. Please try again later."
            }
        }
    }
    
    // MARK: - State
    
    private var buckets: [LimitType: TokenBucket] = [:]
    private var failureCounts: [LimitType: Int] = [:]
    private var lastFailureTime: [LimitType: Date] = [:]
    
    // MARK: - Singleton
    
    static let shared = RateLimiter()
    
    private init() {
        // Initialize buckets for all limit types
        for type in LimitType.allCases {
            buckets[type] = TokenBucket(config: type.config)
        }
    }
    
    // MARK: - Public Methods
    
    /// Attempts to consume a token for the given limit type
    /// - Parameter type: The type of rate limit to check
    /// - Returns: true if request is allowed, false if rate limited
    func tryConsume(_ type: LimitType) async -> Bool {
        guard let bucket = buckets[type] else { return true }
        return bucket.tryConsume()
    }
    
    /// Waits until a token is available, then consumes it
    /// - Parameters:
    ///   - type: The type of rate limit
    ///   - maxWait: Maximum time to wait (default 30 seconds)
    /// - Throws: RateLimitError if max wait time exceeded
    func waitAndConsume(_ type: LimitType, maxWait: TimeInterval = 30) async throws {
        guard let bucket = buckets[type] else { return }
        
        let startTime = Date()
        
        while !bucket.tryConsume() {
            let elapsed = Date().timeIntervalSince(startTime)
            
            if elapsed >= maxWait {
                throw RateLimitError.rateLimited(retryAfter: bucket.timeUntilNextToken())
            }
            
            // Wait a short interval before trying again
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }
    
    /// Returns the time until the next token is available
    func timeUntilAvailable(_ type: LimitType) async -> TimeInterval {
        guard let bucket = buckets[type] else { return 0 }
        return bucket.timeUntilNextToken()
    }
    
    /// Returns the current number of available tokens
    func availableTokens(_ type: LimitType) async -> Int {
        guard let bucket = buckets[type] else { return 0 }
        return bucket.availableTokens()
    }
    
    /// Records a failure for exponential backoff
    func recordFailure(_ type: LimitType) {
        failureCounts[type, default: 0] += 1
        lastFailureTime[type] = Date()
    }
    
    /// Records a success, resetting failure count
    func recordSuccess(_ type: LimitType) {
        failureCounts[type] = 0
        lastFailureTime[type] = nil
    }
    
    /// Calculates exponential backoff delay based on failure count
    func backoffDelay(_ type: LimitType) -> TimeInterval {
        let failures = failureCounts[type, default: 0]
        guard failures > 0 else { return 0 }
        
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s (max)
        let delay = min(pow(2.0, Double(failures - 1)), 16.0)
        return delay
    }
    
    /// Checks if we should retry based on failure count
    func shouldRetry(_ type: LimitType, maxRetries: Int = 3) -> Bool {
        return failureCounts[type, default: 0] < maxRetries
    }
    
    /// Resets all rate limits (for testing)
    func reset() {
        for type in LimitType.allCases {
            buckets[type] = TokenBucket(config: type.config)
            failureCounts[type] = 0
            lastFailureTime[type] = nil
        }
    }
}

// MARK: - Token Bucket Implementation

private class TokenBucket {
    private let maxTokens: Int
    private let refillRate: TimeInterval
    private var tokens: Double
    private var lastRefillTime: Date
    private let lock = NSLock()
    
    init(config: RateLimiter.Config) {
        self.maxTokens = config.maxTokens
        self.refillRate = config.refillRate
        self.tokens = Double(config.initialTokens)
        self.lastRefillTime = Date()
    }
    
    /// Attempts to consume a token
    /// - Returns: true if token consumed, false if bucket empty
    func tryConsume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        refill()
        
        if tokens >= 1.0 {
            tokens -= 1.0
            return true
        }
        
        return false
    }
    
    /// Returns the number of available tokens
    func availableTokens() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        refill()
        return Int(tokens)
    }
    
    /// Returns time until next token is available
    func timeUntilNextToken() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        
        refill()
        
        if tokens >= 1.0 {
            return 0
        }
        
        let neededTokens = 1.0 - tokens
        return neededTokens * refillRate
    }
    
    /// Refills tokens based on elapsed time
    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillTime)
        let tokensToAdd = elapsed / refillRate
        
        tokens = min(Double(maxTokens), tokens + tokensToAdd)
        lastRefillTime = now
    }
}

// MARK: - Rate Limited Request Helper

/// Helper to execute rate-limited requests with automatic retry
struct RateLimitedRequest {
    
    /// Executes a request with rate limiting and exponential backoff
    /// - Parameters:
    ///   - type: The rate limit type
    ///   - maxRetries: Maximum retry attempts
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    static func execute<T>(
        type: RateLimiter.LimitType,
        maxRetries: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        let limiter = RateLimiter.shared
        
        // Wait for rate limit
        try await limiter.waitAndConsume(type)
        
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                // Apply exponential backoff if needed
                let delay = await limiter.backoffDelay(type)
                if delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                
                let result = try await operation()
                await limiter.recordSuccess(type)
                return result
                
            } catch {
                lastError = error
                await limiter.recordFailure(type)
                
                // Check if we should retry
                let shouldRetry = await limiter.shouldRetry(type, maxRetries: maxRetries)
                if !shouldRetry {
                    throw RateLimiter.RateLimitError.tooManyRetries
                }
                
                // Log retry attempt (debug only)
                #if DEBUG
                print("⚠️ Retry attempt \(attempt + 1)/\(maxRetries) for \(type.rawValue)")
                #endif
                
                // Handle network errors with appropriate delays
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .timedOut:
                        // Timeout - wait a bit before retry
                        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    case .networkConnectionLost, .notConnectedToInternet, .dataNotAllowed:
                        // Network issues - wait longer before retry
                        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                    case .cannotConnectToHost, .cannotFindHost:
                        // Server issues - wait even longer
                        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    default:
                        // Other errors - standard delay
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    }
                }
            }
        }
        
        throw lastError ?? RateLimiter.RateLimitError.tooManyRetries
    }
}

