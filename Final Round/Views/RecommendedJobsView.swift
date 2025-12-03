import SwiftUI

struct RecommendedJobsView: View {
    @Environment(\.dismiss) var dismiss
    let userProfile: UserProfile?
    @State private var selectedCategory = "All"
    @State private var categories: [String] = []
    @State private var allJobs: [JobPost] = []
    @State private var isLoadingJobs = false
    private let groqService = GroqService.shared
    
    var filteredJobs: [JobPost] {
        if selectedCategory == "All" {
            return allJobs
        }
        return allJobs.filter { $0.category?.lowercased() == selectedCategory.lowercased() }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommended for You")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    if let profile = userProfile {
                        Text("Based on your profile as \(profile.targetRole.isEmpty ? "Professional" : profile.targetRole)")
                            .font(.system(size: 15))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button {
                            selectedCategory = "All"
                        } label: {
                            CategoryChip(icon: "square.grid.2x2", text: "All", isSelected: selectedCategory == "All")
                        }
                        .buttonStyle(.plain)
                        
                        ForEach(categories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                CategoryChip(
                                    icon: iconForCategory(category),
                                    text: category.capitalized,
                                    isSelected: selectedCategory == category
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)
                
                // Jobs List
                ScrollView {
                    VStack(spacing: 12) {
                        if isLoadingJobs {
                            LoadingView(message: "Finding the best jobs for you...", size: 120)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                        } else if filteredJobs.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "briefcase.circle")
                                    .font(.system(size: 64))
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                                
                                Text("No matching jobs found")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                                
                                Text("Try adjusting your filters or update your profile")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            ForEach(filteredJobs) { job in
                                NavigationLink(destination: JobDescriptionView(job: job)) {
                                    JobPostCard(job: job)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
            }
        }
        .task {
            await loadJobsWithCategories()
        }
    }
    
    private func loadJobsWithCategories() async {
        guard let profile = userProfile else { return }
        
        // Check cache first - but only if location matches current profile
        if let location = profile.location, !location.isEmpty,
           let cached = JobCache.shared.getCachedJobsWithCategories(for: profile.id) {
            await MainActor.run {
                self.categories = cached.categories
                self.allJobs = cached.jobs
            }
            SecureLogger.debug("Using cached jobs for location: \(location)", category: .api)
            return
        }
        
        await MainActor.run {
            self.isLoadingJobs = true
        }
        
        do {
            let role = profile.targetRole
            let skills = profile.skills
            let location = profile.location
            let currency = profile.currency
            
            SecureLogger.debug("Fetching jobs with categories for role", category: .api)
            
            // Pass all profile data including location and currency for personalized results
            let result = try await groqService.searchJobsWithCategories(
                role: role,
                skills: skills,
                location: location,
                currency: currency
            )
            
            // Cache the results
            JobCache.shared.cacheJobsWithCategories(result, for: profile.id)
            
            await MainActor.run {
                self.categories = result.categories
                self.allJobs = result.jobs
                self.isLoadingJobs = false
            }
            
            SecureLogger.info("Successfully loaded \(result.jobs.count) jobs in \(result.categories.count) categories", category: .api)
        } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
            SecureLogger.warning("Request timed out, using fallback jobs", category: .api)
            await MainActor.run {
                let fallback = createFallbackJobsWithCategories(for: profile)
                self.categories = fallback.categories
                self.allJobs = fallback.jobs
                self.isLoadingJobs = false
            }
        } catch {
            SecureLogger.error("Failed to load jobs with categories", category: .api)
            await MainActor.run {
                let fallback = createFallbackJobsWithCategories(for: profile)
                self.categories = fallback.categories
                self.allJobs = fallback.jobs
                self.isLoadingJobs = false
            }
        }
    }
    
    private func createFallbackJobsWithCategories(for profile: UserProfile) -> JobSearchResult {
        let role = profile.targetRole.isEmpty ? "Professional" : profile.targetRole
        let skills = profile.skills
        let location = profile.location ?? "Remote"
        let currency = profile.currency ?? "USD"
        let currencySymbol = getCurrencySymbol(for: currency)
        
        // Determine categories based on the user's role and skills
        var cats: [String] = []
        
        let roleLower = role.lowercased()
        let skillsLower = skills.map { $0.lowercased() }
        
        // Infer categories from user's actual role
        if roleLower.contains("software") || roleLower.contains("engineer") || roleLower.contains("developer") {
            cats.append("engineering")
        }
        if roleLower.contains("product") || roleLower.contains("pm") {
            cats.append("product")
        }
        if roleLower.contains("design") || roleLower.contains("ux") || roleLower.contains("ui") {
            cats.append("design")
        }
        if roleLower.contains("data") || roleLower.contains("analyst") || roleLower.contains("science") {
            cats.append("data")
        }
        if roleLower.contains("marketing") || roleLower.contains("sales") || roleLower.contains("business") {
            cats.append("business")
        }
        if roleLower.contains("manager") || roleLower.contains("director") || roleLower.contains("vp") || 
           roleLower.contains("president") || roleLower.contains("executive") || roleLower.contains("lead") {
            cats.append("leadership")
        }
        
        // Also check skills if no categories from role
        if cats.isEmpty {
            for skill in skillsLower {
                if skill.contains("software") || skill.contains("code") || skill.contains("programming") {
                    cats.append("engineering")
                    break
                }
            }
        }
        
        // Default categories if none matched
        if cats.isEmpty {
            cats = ["general", "leadership", "operations"]
        }
        
        // Ensure we have at least 2-3 categories
        if cats.count == 1 {
            cats.append("general")
        }
        
        // Create fallback jobs that are RELEVANT to the user's actual role
        var fallbackJobs: [JobPost] = []
        
        // Add role-specific jobs
        fallbackJobs.append(contentsOf: [
            JobPost(
                role: "Senior \(role)",
                company: "Global Tech",
                location: location,
                salary: "\(currencySymbol)150k-\(currencySymbol)200k",
                tags: Array(skills.prefix(3)),
                description: "Lead strategic initiatives as a \(role) at a growing company.",
                responsibilities: ["Drive strategic direction", "Lead cross-functional teams", "Deliver results"],
                category: cats.first ?? "leadership",
                logoName: iconForCategory(cats.first ?? "leadership")
            ),
                JobPost(
                role: "\(role)",
                company: "Innovation Corp",
                location: location,
                salary: "\(currencySymbol)120k-\(currencySymbol)160k",
                tags: Array(skills.prefix(3)),
                description: "Join our team as \(role) and make an impact.",
                responsibilities: ["Execute strategy", "Collaborate with stakeholders", "Drive growth"],
                category: cats.first ?? "general",
                logoName: iconForCategory(cats.first ?? "general")
                ),
                JobPost(
                role: "Director of \(role.replacingOccurrences(of: "Vice ", with: "").replacingOccurrences(of: "VP ", with: ""))",
                company: "Enterprise Solutions",
                location: location,
                salary: "\(currencySymbol)180k-\(currencySymbol)250k",
                tags: Array(skills.prefix(3)),
                description: "Senior leadership opportunity for experienced professionals.",
                responsibilities: ["Set vision and strategy", "Build and lead teams", "Report to executive leadership"],
                category: "leadership",
                logoName: iconForCategory("leadership")
            )
        ])
        
        // Add category-specific jobs with the user's role context
        for (index, category) in cats.prefix(3).enumerated() {
            fallbackJobs.append(JobPost(
                role: "\(role) - \(category.capitalized) Focus",
                company: ["TechStart", "GrowthCo", "NextGen Inc"][index % 3],
                location: location,
                salary: "\(currencySymbol)100k-\(currencySymbol)140k",
                    tags: Array(skills.prefix(2)),
                description: "Opportunity for \(role) with \(category) expertise.",
                responsibilities: ["Apply \(category) expertise", "Collaborate across teams", "Drive innovation"],
                    category: category,
                    logoName: iconForCategory(category)
            ))
        }
        
        return JobSearchResult(categories: Array(Set(cats)), jobs: fallbackJobs)
    }
    
    private func getCurrencySymbol(for currency: String) -> String {
        let symbols: [String: String] = [
            "USD": "$", "CAD": "CA$", "GBP": "£", "EUR": "€",
            "INR": "₹", "CNY": "¥", "JPY": "¥", "AUD": "A$"
        ]
        return symbols[currency] ?? "$"
    }
    
    private func iconForCategory(_ category: String) -> String {
        let lowercased = category.lowercased()
        if lowercased.contains("software") || lowercased.contains("engineer") || lowercased.contains("developer") || lowercased.contains("engineering") {
            return "curlybraces.square"
        } else if lowercased.contains("design") || lowercased.contains("ui") || lowercased.contains("ux") {
            return "pencil.and.outline"
        } else if lowercased.contains("marketing") || lowercased.contains("sales") || lowercased.contains("business") {
            return "megaphone.fill"
        } else if lowercased.contains("data") || lowercased.contains("analyst") {
            return "chart.bar.fill"
        } else if lowercased.contains("leadership") || lowercased.contains("executive") || lowercased.contains("management") {
            return "person.3.fill"
        } else if lowercased.contains("product") {
            return "cube.fill"
        } else {
            return "briefcase.fill"
        }
    }
}

#Preview {
    RecommendedJobsView(userProfile: nil)
}
