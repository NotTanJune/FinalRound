import Foundation
import AVFoundation
import Accelerate

class GroqService {
    static let shared = GroqService()
    
    private let apiKey: String
    private let chatBaseURL = "https://api.groq.com/openai/v1/chat/completions"
    private let transcriptionBaseURL = "https://api.groq.com/openai/v1/audio/transcriptions"
    private let chatModel = "openai/gpt-oss-20b"
    private let transcriptionModel = "whisper-large-v3"
    
    // Custom URLSession with longer timeout for browser search
    private lazy var browserSearchSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // 2 minutes
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()
    
    private init() {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "GroqAPIKey") as? String,
            !key.isEmpty else {
            fatalError("Groq API key not found in Info.plist")
        }
        
        self.apiKey = key
    }
    
    func generateQuestions(
        role: String,
        categories: [QuestionCategory],
        difficulty: Difficulty,
        count: Int
    ) async throws -> [InterviewQuestion] {
        guard !apiKey.isEmpty else {
            throw GroqError.missingAPIKey
        }
        
        let prompt = buildPrompt(role: role, categories: categories, difficulty: difficulty, count: count)
        let requestBody = GroqRequest(
            model: chatModel,
            messages: [
                GroqMessage(role: "system", content: """
                You are an expert interview question generator specializing in verbal interview questions.
                Generate only the specified number of questions in a clean, numbered format. 
                Each question should be on its own line starting with a number followed by a period and a space. 
                Do not include any additional text, explanations, or formatting.
                Make sure that the questions are concise, 1 sentence, so that the candidate can read and answer them within a reasonable time frame.
                
                CRITICAL: All questions must be answerable VERBALLY without writing code, drawing diagrams, or doing calculations.
                Focus on discussion-based questions about concepts, experiences, approaches, and decision-making.
                """),
                GroqMessage(role: "user", content: prompt)
            ],
            temperature: 0.6,
            max_tokens: 2000
        )
        
        guard let url = URL(string: chatBaseURL) else {
            throw GroqError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GroqError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let groqResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        
        guard let content = groqResponse.choices.first?.message.content else {
            throw GroqError.noContent
        }
        
        return parseQuestions(from: content, categories: categories, difficulty: difficulty, expectedCount: count)
    }
    
    private func buildPrompt(role: String, categories: [QuestionCategory], difficulty: Difficulty, count: Int) -> String {
        let categoryList = categories.map { $0.rawValue }.joined(separator: ", ")
        
        return """
        Generate exactly \(count) interview questions for a \(role) position.
        
        Requirements:
        - Question categories: \(categoryList)
        - Difficulty level: \(difficulty.rawValue)
        - Generate EXACTLY \(count) questions, no more, no less
        - Distribute questions evenly across the specified categories
        - Each question MUST be ONE SENTENCE ONLY (maximum 20 words)
        - Questions must be concise and direct
        - Format: Start each question with its number (1., 2., 3., etc.)
        - Do not include category labels or any other text
        - One question per line
        
        CRITICAL - SINGLE SENTENCE QUESTIONS:
        - Each question must be ONE complete sentence
        - Maximum 20 words per question
        - No multi-part questions
        - No follow-up clauses
        - Keep questions short and focused
        
        IMPORTANT - Questions must be ORALLY ANSWERABLE:
        - NO coding problems or programming exercises
        - NO whiteboard challenges or algorithm questions
        - NO questions requiring calculations, diagrams, or writing code
        - NO questions that need pen and paper or rough work
        - Focus on discussion-based questions about concepts, experiences, and decision-making
        - Questions should be answerable through verbal explanation only
        
        Examples of GOOD single-sentence questions:
        - Behavioral: "Tell me about a time when you had to work under pressure."
        - Technical: "How would you optimize a slow-running database query?"
        - Situational: "What would you do if you disagreed with a manager's decision?"
        - General: "What motivates you in your work?"
        
        Examples of BAD multi-sentence questions (DO NOT GENERATE):
        - "Tell me about a time when you worked under pressure. How did you handle it and what was the outcome?"
        - "Can you describe a recent project you worked on? What technologies did you use and what challenges did you face?"
        
        Generate exactly \(count) SHORT, SINGLE-SENTENCE questions now:
        """
    }
    
    private func parseQuestions(from content: String, categories: [QuestionCategory], difficulty: Difficulty, expectedCount: Int) -> [InterviewQuestion] {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var questions: [InterviewQuestion] = []
        
        for line in lines {
            // Remove the numbering (e.g., "1. ", "2. ", etc.)
            let cleanedLine = line.replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
            
            if !cleanedLine.isEmpty && !cleanedLine.starts(with: "#") && !cleanedLine.starts(with: "**") {
                // Assign category in a round-robin fashion
                let category = categories[questions.count % categories.count]
                let question = InterviewQuestion(
                    text: cleanedLine,
                    category: category,
                    difficulty: difficulty
                )
                questions.append(question)
                
                // Stop if we've reached the expected count
                if questions.count >= expectedCount {
                    break
                }
            }
        }
        
        // If we didn't get enough questions, return what we have
        return questions
    }
    
    // MARK: - Audio Transcription
    
    func transcribeAudio(audioURL: URL) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GroqError.missingAPIKey
        }
        
        guard let url = URL(string: transcriptionBaseURL) else {
            throw GroqError.invalidURL
        }
        
        // Read audio file
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw GroqError.fileReadError(error.localizedDescription)
        }
        
        // Check if audio file is too small (likely empty/silent)
        // M4A files have a minimum header size of ~500 bytes
        // If file is smaller than 1KB, it's likely just silence
        if audioData.count < 1024 {
            print("⚠️ Audio file too small (\(audioData.count) bytes), likely silent")
            return "[No speech detected]"
        }
        
        // Validate audio has actual content by checking for non-zero samples
        if isAudioSilent(audioURL: audioURL) {
            print("⚠️ Audio appears to be silent")
            return "[No speech detected]"
        }
        
        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(transcriptionModel)\r\n".data(using: .utf8)!)
        
        // Add temperature field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
        body.append("0\r\n".data(using: .utf8)!)
        
        // Add response_format field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("📤 Sending transcription request for: \(audioURL.lastPathComponent)")
        print("📦 Audio data size: \(audioData.count) bytes")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Transcription error (\(httpResponse.statusCode)): \(errorMessage)")
            throw GroqError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        print("✅ Transcription received: \(transcriptionResponse.text.prefix(100))...")
        
        return transcriptionResponse.text
    }
    
    private func isAudioSilent(audioURL: URL) -> Bool {
        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let format = audioFile.processingFormat
            let frameCount = UInt32(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return false
            }
            
            try audioFile.read(into: buffer)
            
            guard let channelData = buffer.floatChannelData?[0] else {
                return false
            }
            
            // Check RMS (Root Mean Square) of audio
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(buffer.frameLength))
            
            // If RMS is below threshold, audio is silent
            let silenceThreshold: Float = 0.01
            return rms < silenceThreshold
        } catch {
            return false
        }
    }
    
    // MARK: - Answer Evaluation
    
    func evaluateAnswer(question: String, answer: String, role: String) async throws -> AnswerEvaluation {
        guard !apiKey.isEmpty else {
            throw GroqError.missingAPIKey
        }
        
        let prompt = """
        You are an expert interviewer evaluating a candidate's answer for a \(role) position.
        
        Question: \(question)
        
        Candidate's Answer: \(answer)
        
        Evaluate this answer and provide:
        1. A score from 0-100 (where 100 is excellent)
        2. Brief strengths (2-3 points)
        3. Brief areas for improvement (2-3 points)
        4. A concise overall feedback (2-3 sentences)
        
        Format your response EXACTLY as follows:
        SCORE: [number]
        STRENGTHS:
        - [strength 1]
        - [strength 2]
        IMPROVEMENTS:
        - [improvement 1]
        - [improvement 2]
        FEEDBACK:
        [overall feedback]
        """
        
        let requestBody = GroqRequest(
            model: chatModel,
            messages: [
                GroqMessage(role: "system", content: "You are an expert interview evaluator. Provide constructive, professional feedback."),
                GroqMessage(role: "user", content: prompt)
            ],
            temperature: 0.3,
            max_tokens: 800
        )
        
        guard let url = URL(string: chatBaseURL) else {
            throw GroqError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        print("📤 Sending evaluation request for question: \(question.prefix(50))...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GroqError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let groqResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        
        guard let content = groqResponse.choices.first?.message.content else {
            throw GroqError.noContent
        }
        
        print("✅ Evaluation received")
        
        return parseEvaluation(from: content)
    }
    
    private func parseEvaluation(from content: String) -> AnswerEvaluation {
        var score = 0
        var strengths: [String] = []
        var improvements: [String] = []
        var feedback = ""
        
        let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        
        var currentSection = ""
        var feedbackLines: [String] = []
        
        for line in lines {
            if line.hasPrefix("SCORE:") {
                let scoreStr = line.replacingOccurrences(of: "SCORE:", with: "").trimmingCharacters(in: .whitespaces)
                score = Int(scoreStr) ?? 0
                currentSection = ""
            } else if line == "STRENGTHS:" {
                currentSection = "strengths"
            } else if line == "IMPROVEMENTS:" {
                currentSection = "improvements"
            } else if line == "FEEDBACK:" {
                currentSection = "feedback"
            } else if !line.isEmpty {
                switch currentSection {
                case "strengths":
                    if line.hasPrefix("-") {
                        strengths.append(line.replacingOccurrences(of: "- ", with: ""))
                    }
                case "improvements":
                    if line.hasPrefix("-") {
                        improvements.append(line.replacingOccurrences(of: "- ", with: ""))
                    }
                case "feedback":
                    feedbackLines.append(line)
                default:
                    break
                }
            }
        }
        
        feedback = feedbackLines.joined(separator: " ")
        
        return AnswerEvaluation(
            score: score,
            strengths: strengths,
            improvements: improvements,
            feedback: feedback
        )
    }
    
    // MARK: - Skill Generation
    
    func generateSkills(prompt: String) async throws -> [String] {
        guard !apiKey.isEmpty else {
            throw GroqError.missingAPIKey
        }
        
        let requestBody = GroqRequest(
            model: chatModel,
            messages: [
                GroqMessage(role: "system", content: "You are a career advisor. Return only valid JSON arrays of strings. No markdown, no code blocks, no explanations."),
                GroqMessage(role: "user", content: prompt)
            ],
            temperature: 0.7,
            max_tokens: 500
        )
        
        guard let url = URL(string: chatBaseURL) else {
            throw GroqError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        print("📤 Generating skills...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GroqError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let groqResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        
        guard let content = groqResponse.choices.first?.message.content else {
            throw GroqError.noContent
        }
        
        print("✅ Skills generated: \(content)")
        
        // Clean up the response - remove markdown code blocks if present
        let cleanedContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse JSON array
        guard let jsonData = cleanedContent.data(using: .utf8),
              let skills = try? JSONDecoder().decode([String].self, from: jsonData) else {
            throw GroqError.noContent
        }
        
        return skills
    }
    
    // MARK: - Job Search
    
    func searchJobs(role: String, skills: [String], count: Int = 10, location: String? = nil, currency: String? = nil) async throws -> [JobPost] {
        guard !apiKey.isEmpty else {
            throw GroqError.missingAPIKey
        }
        
        let currencySymbol = self.getCurrencySymbol(for: currency ?? "USD")
        let locationFilter = location ?? "various locations"
        
        // Simplified prompt for faster response
        let prompt = """
        Generate \(count) job postings in JSON format for \(role) in \(locationFilter).
        
        Return ONLY a valid JSON array:
        [{"role":"Job Title","company":"Company Name","location":"City, Country in \(locationFilter)","salary":"\(currencySymbol)XXk-\(currencySymbol)XXk","tags":["skill1","skill2"],"description":"Brief description","responsibilities":["task1","task2","task3"]}]
        
        IMPORTANT: All jobs must be located in or near \(locationFilter). Use \(currency ?? "USD") currency with \(currencySymbol) symbol for salaries.
        Generate exactly \(count) jobs. No markdown, no explanation, pure JSON only.
        """
        
        let requestBody: [String: Any] = [
            "model": chatModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_completion_tokens": 8000,
            "top_p": 1,
            "stream": false
        ]
        
        guard let url = URL(string: chatBaseURL) else {
            throw GroqError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60 // 60 second timeout
        
        print("📤 Searching for \(count) jobs for \(role)...")
        
        let (data, response) = try await browserSearchSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GroqError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let groqResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        
        guard let content = groqResponse.choices.first?.message.content else {
            throw GroqError.noContent
        }
        
        print("✅ Jobs received, parsing...")
        
        // Clean up the response
        var cleanedContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find the JSON array bounds
        if let startIndex = cleanedContent.firstIndex(of: "["),
           let endIndex = cleanedContent.lastIndex(of: "]") {
            cleanedContent = String(cleanedContent[startIndex...endIndex])
        }
        
        // Parse JSON array
        guard let jsonData = cleanedContent.data(using: .utf8) else {
            print("❌ Failed to convert content to data")
            throw GroqError.noContent
        }
        
        do {
            let jobResponses = try JSONDecoder().decode([JobSearchResponse].self, from: jsonData)
            print("✅ Successfully parsed \(jobResponses.count) jobs")
            
            let jobs = jobResponses.map { response in
                JobPost(
                    role: response.role,
                    company: response.company,
                    location: response.location,
                    salary: response.salary,
                    tags: response.tags,
                    description: response.description,
                    responsibilities: response.responsibilities,
                    logoName: iconForCategory(response.tags.first ?? "")
                )
            }
            
            // If we got fewer jobs than requested, that's still a valid response
            if jobs.count < count {
                print("⚠️ Only received \(jobs.count) jobs instead of \(count)")
            }
            
            return jobs
        } catch {
            print("❌ JSON parsing failed: \(error)")
            print("📄 Cleaned content length: \(cleanedContent.count)")
            print("📄 First 1000 chars: \(cleanedContent.prefix(1000))")
            if cleanedContent.count > 1000 {
                print("📄 Last 500 chars: \(cleanedContent.suffix(500))")
            }
            throw error
        }
    }
    
    func searchJobsWithCategories(role: String, skills: [String], location: String? = nil, currency: String? = nil) async throws -> JobSearchResult {
        guard !apiKey.isEmpty else {
            throw GroqError.missingAPIKey
        }
        
        let locationFilter = location ?? "various locations"
        
        print("📤 Generating categories and jobs for \(role) in \(locationFilter)...")
        
        // First, get categories based on user profile
        let categoriesPrompt = """
        For a \(role) with skills: \(skills.prefix(5).joined(separator: ", ")), suggest 3 job categories.
        
        Return ONLY a JSON array: ["category1", "category2", "category3"]
        Use lowercase, one-word categories like: software, design, marketing, data, sales, etc.
        """
        
        let categoriesRequestBody: [String: Any] = [
            "model": chatModel,
            "messages": [
                ["role": "user", "content": categoriesPrompt]
            ],
            "temperature": 0.7,
            "max_completion_tokens": 100,
            "top_p": 1,
            "stream": false
        ]
        
        guard let url = URL(string: chatBaseURL) else {
            throw GroqError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: categoriesRequestBody)
        request.timeoutInterval = 30
        
        let (categoriesData, categoriesResponse) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = categoriesResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GroqError.invalidResponse
        }
        
        let categoriesGroqResponse = try JSONDecoder().decode(GroqResponse.self, from: categoriesData)
        guard let categoriesContent = categoriesGroqResponse.choices.first?.message.content else {
            throw GroqError.noContent
        }
        
        let cleanedCategories = categoriesContent
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let categoriesJsonData = cleanedCategories.data(using: .utf8),
              let categories = try? JSONDecoder().decode([String].self, from: categoriesJsonData) else {
            throw GroqError.noContent
        }
        
        print("✅ Categories generated: \(categories)")
        
        let currencySymbol = self.getCurrencySymbol(for: currency ?? "USD")
        
        // Now generate jobs for each category (10 jobs per category)
        let jobsPrompt = """
        Generate 10 realistic job postings for EACH category: \(categories.joined(separator: ", ")).
        User profile: \(role) with skills: \(skills.prefix(5).joined(separator: ", ")).
        Location: \(locationFilter)
        
        Return ONLY this JSON (no markdown):
        {
          "categories": \(categories),
          "jobs": [
            {
              "category": "category1",
              "role": "Job Title",
              "company": "Real Company",
              "location": "City, Country in \(locationFilter)",
              "salary": "\(currencySymbol)XXk-\(currencySymbol)XXk",
              "tags": ["skill1", "skill2"],
              "description": "Brief description",
              "responsibilities": ["task1", "task2", "task3"]
            }
          ]
        }
        
        Requirements:
        - Exactly 10 jobs PER category (30 total)
        - ALL jobs must be in or near \(locationFilter)
        - Real companies that hire in this location
        - 2025 market salaries in \(currency ?? "USD") (\(currencySymbol))
        - Match category to job type
        - JSON only
        """
        
        let jobsRequestBody: [String: Any] = [
            "model": chatModel,
            "messages": [
                ["role": "user", "content": jobsPrompt]
            ],
            "temperature": 0.8,
            "max_completion_tokens": 8192,
            "top_p": 1,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: jobsRequestBody)
        request.timeoutInterval = 60
        
        let (jobsData, jobsResponse) = try await browserSearchSession.data(for: request)
        
        guard let jobsHttpResponse = jobsResponse as? HTTPURLResponse, jobsHttpResponse.statusCode == 200 else {
            throw GroqError.invalidResponse
        }
        
        let jobsGroqResponse = try JSONDecoder().decode(GroqResponse.self, from: jobsData)
        guard let jobsContent = jobsGroqResponse.choices.first?.message.content else {
            throw GroqError.noContent
        }
        
        print("✅ Jobs with categories received")
        
        var cleanedJobsContent = jobsContent
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find the JSON object bounds
        if let startIndex = cleanedJobsContent.firstIndex(of: "{"),
           let endIndex = cleanedJobsContent.lastIndex(of: "}") {
            cleanedJobsContent = String(cleanedJobsContent[startIndex...endIndex])
        }
        
        guard let jobsJsonData = cleanedJobsContent.data(using: .utf8) else {
            throw GroqError.noContent
        }
        
        let searchResult = try JSONDecoder().decode(JobSearchResultResponse.self, from: jobsJsonData)
        
        let jobs = searchResult.jobs.map { response in
            JobPost(
                role: response.role,
                company: response.company,
                location: response.location,
                salary: response.salary,
                tags: response.tags,
                description: response.description,
                responsibilities: response.responsibilities,
                category: response.category,
                logoName: iconForCategory(response.category ?? response.tags.first ?? "")
            )
        }
        
        return JobSearchResult(categories: searchResult.categories, jobs: jobs)
    }
    
    private func iconForCategory(_ category: String) -> String {
        let lowercased = category.lowercased()
        if lowercased.contains("software") || lowercased.contains("engineer") || lowercased.contains("developer") {
            return "curlybraces.square"
        } else if lowercased.contains("design") || lowercased.contains("ui") || lowercased.contains("ux") {
            return "paintpalette.fill"
        } else if lowercased.contains("marketing") || lowercased.contains("sales") {
            return "megaphone.fill"
        } else if lowercased.contains("data") || lowercased.contains("analyst") {
            return "chart.bar.fill"
        } else {
            return "briefcase.fill"
        }
    }
    
    // MARK: - Company Information
    
    func getCompanyInfo(companyName: String, industry: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GroqError.missingAPIKey
        }
        
        let prompt = """
        Provide a brief, informative overview of \(companyName), a company in the \(industry) industry.
        
        Include:
        - What the company does
        - Their main products or services
        - Company size and reach (if known)
        - Notable achievements or reputation
        - Company culture or values (if known)
        
        Keep it concise (2-3 paragraphs) and professional. If you don't have specific information about this company, provide a general description based on the industry and company name.
        """
        
        let requestBody: [String: Any] = [
            "model": chatModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_completion_tokens": 500,
            "top_p": 1,
            "stream": false
        ]
        
        var request = URLRequest(url: URL(string: chatBaseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30
        
        let (data, response) = try await browserSearchSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Groq API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw GroqError.apiError(message: "API returned status code \(httpResponse.statusCode)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GroqError.noContent
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Currency Helper
    
    private func getCurrencySymbol(for currencyCode: String) -> String {
        let currencySymbols: [String: String] = [
            "USD": "$", "CAD": "CA$", "MXN": "MX$",
            "GBP": "£", "EUR": "€", "CHF": "CHF",
            "SEK": "kr", "NOK": "kr", "DKK": "kr",
            "PLN": "zł", "CZK": "Kč", "HUF": "Ft", "RON": "lei",
            "INR": "₹", "CNY": "¥", "JPY": "¥", "KRW": "₩",
            "SGD": "S$", "HKD": "HK$", "TWD": "NT$",
            "THB": "฿", "MYR": "RM", "IDR": "Rp", "PHP": "₱",
            "VND": "₫", "PKR": "₨", "BDT": "৳",
            "AUD": "A$", "NZD": "NZ$",
            "AED": "AED", "SAR": "SR", "ILS": "₪", "TRY": "₺",
            "QAR": "QR", "KWD": "KD",
            "ZAR": "R", "NGN": "₦", "KES": "KSh", "EGP": "E£",
            "BRL": "R$", "ARS": "AR$", "CLP": "CLP", "COP": "COL$", "PEN": "S/"
        ]
        
        return currencySymbols[currencyCode] ?? currencyCode
    }
}

// MARK: - Request/Response Models

struct GroqRequest: Codable {
    let model: String
    let messages: [GroqMessage]
    let temperature: Double
    let max_tokens: Int
}

struct JobSearchResponse: Codable {
    let role: String
    let company: String
    let location: String
    let salary: String
    let tags: [String]
    let description: String?
    let responsibilities: [String]?
    let category: String?
}

struct JobSearchResultResponse: Codable {
    let categories: [String]
    let jobs: [JobSearchResponse]
}

struct JobSearchResult {
    let categories: [String]
    let jobs: [JobPost]
}

struct GroqMessage: Codable {
    let role: String
    let content: String
}

struct GroqResponse: Codable {
    let choices: [GroqChoice]
}

struct GroqChoice: Codable {
    let message: GroqMessageResponse
}

struct GroqMessageResponse: Codable {
    let content: String
}

struct TranscriptionResponse: Codable {
    let text: String
}

// MARK: - Errors

enum GroqError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case noContent
    case fileReadError(String)
    case apiError(message: String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Groq API key is missing. Please set the GROQ_API_KEY environment variable."
        case .invalidURL:
            return "Invalid URL for Groq API."
        case .invalidResponse:
            return "Invalid response from Groq API."
        case .apiError(let message):
            return "API Error: \(message)"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .noContent:
            return "No content received from Groq API."
        case .fileReadError(let message):
            return "Failed to read audio file: \(message)"
        }
    }
}
