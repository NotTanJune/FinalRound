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
                        Text("Based on your profile as \(profile.targetRole ?? "Professional")")
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
        
        // Check cache first
        if let cached = JobCache.shared.getCachedJobsWithCategories(for: profile.id) {
            await MainActor.run {
                self.categories = cached.categories
                self.allJobs = cached.jobs
            }
            return
        }
        
        await MainActor.run {
            self.isLoadingJobs = true
        }
        
        do {
            let role = profile.targetRole
            let skills = profile.skills
            
            print("🔍 Fetching jobs with categories for \(role)...")
            
            let result = try await groqService.searchJobsWithCategories(role: role, skills: skills)
            
            // Cache the results
            JobCache.shared.cacheJobsWithCategories(result, for: profile.id)
            
            await MainActor.run {
                self.categories = result.categories
                self.allJobs = result.jobs
                self.isLoadingJobs = false
            }
            
            print("✅ Successfully loaded \(result.jobs.count) jobs in \(result.categories.count) categories")
        } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
            print("⏱️ Request timed out, using fallback jobs")
            await MainActor.run {
                let fallback = createFallbackJobsWithCategories(for: profile)
                self.categories = fallback.categories
                self.allJobs = fallback.jobs
                self.isLoadingJobs = false
            }
        } catch {
            print("❌ Failed to load jobs with categories: \(error)")
            await MainActor.run {
                let fallback = createFallbackJobsWithCategories(for: profile)
                self.categories = fallback.categories
                self.allJobs = fallback.jobs
                self.isLoadingJobs = false
            }
        }
    }
    
    private func createFallbackJobsWithCategories(for profile: UserProfile) -> JobSearchResult {
        let role = profile.targetRole ?? "Software Engineer"
        let skills = profile.skills
        
        // Determine categories based on skills
        var cats: [String] = []
        if skills.contains(where: { $0.lowercased().contains("software") || $0.lowercased().contains("engineer") }) {
            cats.append("software")
        }
        if skills.contains(where: { $0.lowercased().contains("design") || $0.lowercased().contains("ui") }) {
            cats.append("design")
        }
        if skills.contains(where: { $0.lowercased().contains("data") || $0.lowercased().contains("analyst") }) {
            cats.append("data")
        }
        
        // Default categories if none matched
        if cats.isEmpty {
            cats = ["software", "design", "product"]
        } else if cats.count < 3 {
            cats.append("product")
        }
        
        let fallbackJobs: [JobPost] = cats.flatMap { category in
            [
                JobPost(
                    role: "Senior \(category.capitalized) Engineer",
                    company: "Tech Corp",
                    location: "Remote",
                    salary: "$120k-$160k",
                    tags: Array(skills.prefix(2)),
                    description: "Work on innovative projects in \(category).",
                    responsibilities: ["Lead development", "Mentor team", "Drive innovation"],
                    category: category,
                    logoName: iconForCategory(category)
                ),
                JobPost(
                    role: "\(category.capitalized) Specialist",
                    company: "Innovation Labs",
                    location: "San Francisco, CA",
                    salary: "$100k-$140k",
                    tags: Array(skills.prefix(2)),
                    description: "Join our \(category) team.",
                    responsibilities: ["Build features", "Collaborate", "Ensure quality"],
                    category: category,
                    logoName: iconForCategory(category)
                )
            ]
        }
        
        return JobSearchResult(categories: cats, jobs: fallbackJobs)
    }
    }
    
    private func iconForCategory(_ category: String) -> String {
        let lowercased = category.lowercased()
        if lowercased.contains("software") || lowercased.contains("engineer") || lowercased.contains("developer") {
            return "curlybraces.square"
        } else if lowercased.contains("design") || lowercased.contains("ui") || lowercased.contains("ux") {
            return "pencil.and.outline"
        } else if lowercased.contains("marketing") || lowercased.contains("sales") {
            return "megaphone.fill"
        } else if lowercased.contains("data") || lowercased.contains("analyst") {
            return "chart.bar.fill"
        } else {
            return "briefcase.fill"
        }
    }


#Preview {
    RecommendedJobsView(userProfile: nil)
}
