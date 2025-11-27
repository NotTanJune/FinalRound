import Foundation

class JobCache {
    static let shared = JobCache()
    
    private var cache: [UUID: CachedJobData] = [:]
    private var companyInfoCache: [String: CachedCompanyInfo] = [:]
    private let cacheExpirationInterval: TimeInterval = 86400 // 24 hours for jobs
    private let companyInfoExpirationInterval: TimeInterval = 604800 // 7 days for company info
    private let cacheFileURL: URL
    private let companyInfoCacheFileURL: URL
    
    private init() {
        // Set up cache file location in Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheFileURL = documentsPath.appendingPathComponent("job_cache.json")
        companyInfoCacheFileURL = documentsPath.appendingPathComponent("company_info_cache.json")
        
        // Load cache from disk on initialization
        loadCacheFromDisk()
        loadCompanyInfoCacheFromDisk()
    }
    
    func cacheJobs(_ jobs: [JobPost], for userId: UUID) {
        cache[userId] = CachedJobData(jobs: jobs, timestamp: Date())
        saveCacheToDisk()
    }
    
    func getCachedJobs(for userId: UUID) -> [JobPost]? {
        guard let cachedData = cache[userId] else { return nil }
        
        // Check if cache has expired
        let timeElapsed = Date().timeIntervalSince(cachedData.timestamp)
        if timeElapsed > cacheExpirationInterval {
            cache.removeValue(forKey: userId)
            saveCacheToDisk()
            return nil
        }
        
        return cachedData.jobs
    }
    
    func cacheJobsWithCategories(_ result: JobSearchResult, for userId: UUID) {
        cache[userId] = CachedJobData(
            jobs: result.jobs,
            timestamp: Date(),
            categories: result.categories
        )
        saveCacheToDisk()
    }
    
    func getCachedJobsWithCategories(for userId: UUID) -> JobSearchResult? {
        guard let cachedData = cache[userId] else { return nil }
        
        // Check if cache has expired
        let timeElapsed = Date().timeIntervalSince(cachedData.timestamp)
        if timeElapsed > cacheExpirationInterval {
            cache.removeValue(forKey: userId)
            saveCacheToDisk()
            return nil
        }
        
        guard let categories = cachedData.categories else { return nil }
        
        return JobSearchResult(categories: categories, jobs: cachedData.jobs)
    }
    
    func clearCache() {
        cache.removeAll()
        saveCacheToDisk()
    }
    
    func clearCache(for userId: UUID) {
        cache.removeValue(forKey: userId)
        saveCacheToDisk()
        print("✅ Cleared cache for user: \(userId)")
    }
    
    // MARK: - Company Info Caching
    
    func cacheCompanyInfo(_ info: String, for companyName: String) {
        let normalizedKey = companyName.lowercased().trimmingCharacters(in: .whitespaces)
        companyInfoCache[normalizedKey] = CachedCompanyInfo(info: info, timestamp: Date())
        saveCompanyInfoCacheToDisk()
        print("✅ Cached company info for: \(companyName)")
    }
    
    func getCachedCompanyInfo(for companyName: String) -> String? {
        let normalizedKey = companyName.lowercased().trimmingCharacters(in: .whitespaces)
        guard let cachedData = companyInfoCache[normalizedKey] else { return nil }
        
        // Check if cache has expired (7 days)
        let timeElapsed = Date().timeIntervalSince(cachedData.timestamp)
        if timeElapsed > companyInfoExpirationInterval {
            companyInfoCache.removeValue(forKey: normalizedKey)
            saveCompanyInfoCacheToDisk()
            print("ℹ️ Company info cache expired for: \(companyName)")
            return nil
        }
        
        print("✅ Using cached company info for: \(companyName)")
        return cachedData.info
    }
    
    func clearCompanyInfoCache() {
        companyInfoCache.removeAll()
        saveCompanyInfoCacheToDisk()
        print("✅ Cleared all company info cache")
    }
    
    // MARK: - Disk Persistence
    
    private func saveCacheToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            // Convert cache to a serializable format
            let serializableCache = cache.mapValues { data in
                SerializableCachedJobData(
                    jobs: data.jobs,
                    timestamp: data.timestamp,
                    categories: data.categories
                )
            }
            
            // Convert UUID keys to strings for JSON serialization
            let stringKeyedCache = Dictionary(uniqueKeysWithValues: 
                serializableCache.map { (key, value) in (key.uuidString, value) }
            )
            
            let data = try encoder.encode(stringKeyedCache)
            try data.write(to: cacheFileURL, options: .atomic)
            print("✅ Job cache saved to disk")
        } catch {
            print("❌ Failed to save cache to disk: \(error)")
        }
    }
    
    private func loadCacheFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            print("ℹ️ No cache file found on disk")
            return
        }
        
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let stringKeyedCache = try decoder.decode([String: SerializableCachedJobData].self, from: data)
            
            // Convert string keys back to UUIDs
            cache = Dictionary(uniqueKeysWithValues: 
                stringKeyedCache.compactMap { (key, value) -> (UUID, CachedJobData)? in
                    guard let uuid = UUID(uuidString: key) else { return nil }
                    return (uuid, CachedJobData(
                        jobs: value.jobs,
                        timestamp: value.timestamp,
                        categories: value.categories
                    ))
                }
            )
            
            print("✅ Job cache loaded from disk (\(cache.count) users)")
        } catch {
            print("❌ Failed to load cache from disk: \(error)")
        }
    }
    
    // MARK: - Company Info Disk Persistence
    
    private func saveCompanyInfoCacheToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            let serializableCache = companyInfoCache.mapValues { data in
                SerializableCachedCompanyInfo(info: data.info, timestamp: data.timestamp)
            }
            
            let data = try encoder.encode(serializableCache)
            try data.write(to: companyInfoCacheFileURL, options: .atomic)
            print("✅ Company info cache saved to disk")
        } catch {
            print("❌ Failed to save company info cache to disk: \(error)")
        }
    }
    
    private func loadCompanyInfoCacheFromDisk() {
        guard FileManager.default.fileExists(atPath: companyInfoCacheFileURL.path) else {
            print("ℹ️ No company info cache file found on disk")
            return
        }
        
        do {
            let data = try Data(contentsOf: companyInfoCacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let loadedCache = try decoder.decode([String: SerializableCachedCompanyInfo].self, from: data)
            
            companyInfoCache = loadedCache.mapValues { value in
                CachedCompanyInfo(info: value.info, timestamp: value.timestamp)
            }
            
            print("✅ Company info cache loaded from disk (\(companyInfoCache.count) companies)")
        } catch {
            print("❌ Failed to load company info cache from disk: \(error)")
        }
    }
}

// MARK: - Company Info Cache Structs

private struct CachedCompanyInfo {
    let info: String
    let timestamp: Date
}

private struct SerializableCachedCompanyInfo: Codable {
    let info: String
    let timestamp: Date
}

// MARK: - Job Cache Structs

private struct CachedJobData {
    let jobs: [JobPost]
    let timestamp: Date
    let categories: [String]?
    
    init(jobs: [JobPost], timestamp: Date, categories: [String]? = nil) {
        self.jobs = jobs
        self.timestamp = timestamp
        self.categories = categories
    }
}

// Codable version for disk persistence
private struct SerializableCachedJobData: Codable {
    let jobs: [JobPost]
    let timestamp: Date
    let categories: [String]?
}
