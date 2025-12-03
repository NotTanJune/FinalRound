import SwiftUI

struct JobDescriptionView: View {
    let job: JobPost
    @State private var selectedTab = 0
    @State private var showingInterviewSetup = false
    @State private var companyInfo: String?
    @State private var isLoadingCompanyInfo = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 16) {
                            Image(systemName: job.logoName)
                                .font(.system(size: 32))
                                .foregroundStyle(AppTheme.textPrimary)
                                .frame(width: 64, height: 64)
                                .background(AppTheme.cardBackground)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.role)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                
                                HStack(spacing: 6) {
                                    Text(job.salary)
                                        .fontWeight(.medium)
                                    Text("•")
                                    Text(job.company) // Using company as placeholder for salary range/type if needed
                                    Text("•")
                                    Text(job.location)
                                }
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        
                        FlowLayout(spacing: 8) {
                            ForEach(job.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(tagColor(for: tag))
                                    .cornerRadius(8)
                                    .fixedSize()
                            }
                        }
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    
                    // Tabs
                    HStack(spacing: 0) {
                        TabButton(title: "Job Detail", isSelected: selectedTab == 0) {
                            withAnimation { selectedTab = 0 }
                        }
                        TabButton(title: "About Company", isSelected: selectedTab == 1) {
                            withAnimation { selectedTab = 1 }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Content
                    VStack(alignment: .leading, spacing: 16) {
                        if selectedTab == 0 {
                            Text("Description")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                            
                            Text(job.description ?? "Are you a passionate UI/UX Designer looking to join a global tech leader? We're at the forefront of innovation, shaping the future of communication and technology. If you're a creative thinker, adept at crafting seamless user experiences, we want you on our team!")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineSpacing(4)
                            
                            Text("Responsibilities")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.top, 8)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                if let responsibilities = job.responsibilities, !responsibilities.isEmpty {
                                    ForEach(Array(responsibilities.enumerated()), id: \.offset) { index, responsibility in
                                        ResponsibilityRow(number: "\(index + 1)", text: responsibility)
                                    }
                                } else {
                                    ResponsibilityRow(number: "1", text: "User-Centric Design: Create intuitive and user-friendly interfaces that prioritize the needs and preferences of our diverse user base.")
                                    ResponsibilityRow(number: "2", text: "Wireframing and Prototyping: Develop wireframes, prototypes, and mockups to visualize design concepts and gather feedback.")
                                    ResponsibilityRow(number: "3", text: "Design System Development: Contribute to the maintenance and evolution of our design system.")
                                }
                            }
                        } else {
                            Text("About \(job.company)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                            
                            if isLoadingCompanyInfo {
                                HStack {
                                    ProgressView()
                                        .tint(AppTheme.primary)
                                    Text("Loading company information...")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 40)
                            } else if let info = companyInfo {
                                Text(info)
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineSpacing(4)
                            } else {
                                Text("Unable to load company information at this time.")
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineSpacing(4)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100) // Space for bottom bar
                }
            }
            .background(AppTheme.background)
            
            // Bottom Bar
            BottomActionBar(showsSeparator: false) {
                HStack(spacing: 16) {
                    Button {
                        showingInterviewSetup = true
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("Generate Interview")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingInterviewSetup) {
            InterviewSetupView(job: job)
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 1 && companyInfo == nil && !isLoadingCompanyInfo {
                Task {
                    await loadCompanyInfo()
                }
            }
        }
    }
    
    private func loadCompanyInfo() async {
        // Check cache first
        if let cachedInfo = JobCache.shared.getCachedCompanyInfo(for: job.company) {
            await MainActor.run {
                self.companyInfo = cachedInfo
            }
            return
        }
        
        // Not in cache, fetch from API
        isLoadingCompanyInfo = true
        
        do {
            let info = try await GroqService.shared.getCompanyInfo(
                companyName: job.company,
                industry: job.tags.first ?? "technology"
            )
            
            // Cache the result
            JobCache.shared.cacheCompanyInfo(info, for: job.company)
            
            await MainActor.run {
                self.companyInfo = info
                self.isLoadingCompanyInfo = false
            }
        } catch {
            print("❌ Failed to load company info: \(error)")
            await MainActor.run {
                self.companyInfo = "This is a placeholder for the company description. \(job.company) is a leading company in the \(job.tags.first ?? "tech") industry."
                self.isLoadingCompanyInfo = false
            }
        }
    }
    
    private func tagColor(for tag: String) -> Color {
        switch tag {
        case "Accounting": return AppTheme.ratingYellow.opacity(0.3)
        case "Software": return AppTheme.lightGreen
        case "Art & Design": return AppTheme.ratingYellow.opacity(0.3)
        default: return AppTheme.lightGreen
        }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                
                Rectangle()
                    .fill(isSelected ? AppTheme.textPrimary : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ResponsibilityRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 24, height: 24)
                .background(AppTheme.background)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(AppTheme.border, lineWidth: 1)
                )
            
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(4)
        }
    }
}

