import Foundation

/// Service for parsing LinkedIn job posting URLs and extracting job details using Groq LLM
class LinkedInJobParser {
    static let shared = LinkedInJobParser()
    
    private init() {}
    
    // MARK: - URL Validation
    
    /// Validates if the given URL is a valid LinkedIn job posting URL
    func isValidLinkedInJobURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        
        // Check for linkedin.com domain variations
        let isLinkedIn = host.contains("linkedin.com") || host.contains("lnkd.in")
        
        // Check for job posting paths
        let isJobPath = path.contains("/jobs/view/") || 
                        path.contains("/jobs/") ||
                        path.contains("/job/")
        
        return isLinkedIn && isJobPath
    }
    
    // MARK: - Job Parsing
    
    /// Parses a LinkedIn job URL and returns a JobPost object
    /// - Parameter urlString: The LinkedIn job posting URL
    /// - Returns: A JobPost object with extracted details
    func parseJob(from urlString: String) async throws -> JobPost {
        // Validate URL
        guard isValidLinkedInJobURL(urlString) else {
            throw LinkedInParserError.invalidURL
        }
        
        guard let url = URL(string: urlString) else {
            throw LinkedInParserError.invalidURL
        }
        
        // Fetch the page HTML
        let html = try await fetchPageHTML(from: url)
        
        // Extract job details using Groq LLM
        let jobDetails = try await extractJobDetails(from: html, sourceURL: urlString)
        
        return jobDetails
    }
    
    // MARK: - HTML Fetching
    
    private func fetchPageHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        // Set headers to mimic a browser request
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInParserError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LinkedInParserError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw LinkedInParserError.parsingError("Could not decode HTML")
        }
        
        // Check if we got a meaningful response (not a login wall)
        if html.contains("authwall") || html.contains("sign-in-modal") {
            print("⚠️ LinkedIn returned auth wall, attempting to extract metadata...")
        }
        
        return html
    }
    
    // MARK: - Groq LLM Extraction
    
    private func extractJobDetails(from html: String, sourceURL: String) async throws -> JobPost {
        // First, try to extract Open Graph metadata as a fallback
        let ogData = extractOpenGraphData(from: html)
        
        // Truncate HTML to avoid token limits (keep first ~15000 chars which usually contains job info)
        let truncatedHTML = String(html.prefix(15000))
        
        // Use Groq to extract structured data
        let extractedData = try await callGroqForExtraction(html: truncatedHTML, ogData: ogData)
        
        return extractedData
    }
    
    private func extractOpenGraphData(from html: String) -> [String: String] {
        var ogData: [String: String] = [:]
        
        // Extract og:title
        if let titleMatch = html.range(of: #"<meta[^>]*property="og:title"[^>]*content="([^"]*)"#, options: .regularExpression) {
            let match = String(html[titleMatch])
            if let contentRange = match.range(of: #"content="([^"]*)"#, options: .regularExpression) {
                let content = String(match[contentRange])
                    .replacingOccurrences(of: "content=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                ogData["title"] = content
            }
        }
        
        // Extract og:description
        if let descMatch = html.range(of: #"<meta[^>]*property="og:description"[^>]*content="([^"]*)"#, options: .regularExpression) {
            let match = String(html[descMatch])
            if let contentRange = match.range(of: #"content="([^"]*)"#, options: .regularExpression) {
                let content = String(match[contentRange])
                    .replacingOccurrences(of: "content=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                ogData["description"] = content
            }
        }
        
        // Try to extract from JSON-LD if present
        if let jsonLDMatch = html.range(of: #"<script type="application/ld\+json"[^>]*>([^<]*)</script>"#, options: .regularExpression) {
            ogData["jsonLD"] = String(html[jsonLDMatch])
        }
        
        return ogData
    }
    
    private func callGroqForExtraction(html: String, ogData: [String: String]) async throws -> JobPost {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GroqAPIKey") as? String,
              !apiKey.isEmpty else {
            throw LinkedInParserError.missingAPIKey
        }
        
        let ogContext = ogData.isEmpty ? "" : """
        
        Open Graph metadata found:
        - Title: \(ogData["title"] ?? "N/A")
        - Description: \(ogData["description"] ?? "N/A")
        """
        
        let prompt = """
        Extract job posting details from this LinkedIn page HTML and return ONLY valid JSON.
        \(ogContext)
        
        HTML content:
        \(html)
        
        Return ONLY this JSON format (no markdown, no explanation):
        {
            "role": "Job Title",
            "company": "Company Name",
            "location": "City, State/Country or Remote",
            "salary": "Salary range if mentioned, otherwise empty string",
            "tags": ["skill1", "skill2", "skill3"],
            "description": "Brief job description summary (2-3 sentences)",
            "responsibilities": ["responsibility1", "responsibility2", "responsibility3"]
        }
        
        Guidelines:
        - Extract the exact job title for "role"
        - Extract the company name
        - For location, extract city/state or note if remote
        - For salary, extract if mentioned, otherwise use empty string
        - For tags, extract 3-5 key skills/technologies mentioned
        - For description, provide a concise 2-3 sentence summary
        - For responsibilities, extract 3-5 key responsibilities
        - If information is not found, use reasonable defaults based on job title
        
        RETURN ONLY THE JSON, NO OTHER TEXT.
        """
        
        let requestBody: [String: Any] = [
            "model": "meta-llama/llama-4-scout-17b-16e-instruct",
            "messages": [
                ["role": "system", "content": "You are a precise data extraction assistant. Extract job details from HTML and return only valid JSON. Never include markdown formatting or explanations."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "max_tokens": 1000
        ]
        
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw LinkedInParserError.networkError("Invalid API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60
        
        print("📤 Sending LinkedIn job to Groq for extraction...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinkedInParserError.networkError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Groq API error: \(errorBody)")
            throw LinkedInParserError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        // Parse Groq response
        guard let groqResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = groqResponse["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LinkedInParserError.parsingError("Invalid Groq response format")
        }
        
        print("✅ Groq extraction complete")
        
        // Parse the extracted JSON
        return try parseExtractedJSON(content)
    }
    
    private func parseExtractedJSON(_ content: String) throws -> JobPost {
        // Clean up the response (remove any markdown if present)
        var cleanedContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find JSON object bounds
        if let startIndex = cleanedContent.firstIndex(of: "{"),
           let endIndex = cleanedContent.lastIndex(of: "}") {
            cleanedContent = String(cleanedContent[startIndex...endIndex])
        }
        
        guard let jsonData = cleanedContent.data(using: .utf8) else {
            throw LinkedInParserError.parsingError("Could not encode JSON")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw LinkedInParserError.parsingError("Invalid JSON structure")
        }
        
        // Extract fields with defaults
        let role = json["role"] as? String ?? "Unknown Position"
        let company = json["company"] as? String ?? "Unknown Company"
        let location = json["location"] as? String ?? "Location not specified"
        let salary = json["salary"] as? String ?? ""
        let tags = json["tags"] as? [String] ?? []
        let description = json["description"] as? String
        let responsibilities = json["responsibilities"] as? [String]
        
        print("✅ Parsed job: \(role) at \(company)")
        
        return JobPost(
            role: role,
            company: company,
            location: location,
            salary: salary,
            tags: tags,
            description: description,
            responsibilities: responsibilities,
            logoName: "link.circle.fill"
        )
    }
}

// MARK: - Error Types

enum LinkedInParserError: LocalizedError {
    case invalidURL
    case networkError(String)
    case parsingError(String)
    case apiError(String)
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Please enter a valid LinkedIn job posting URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError(let message):
            return "Could not parse job details: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .missingAPIKey:
            return "API key not configured"
        }
    }
}

