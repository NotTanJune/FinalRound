import SwiftUI

struct JobPostCard: View {
    let job: JobPost
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: job.logoName)
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
                
                    Text(job.role)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                Text(job.salary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.lightGreen)
                    .cornerRadius(8)
                    .fixedSize()
            }
            
            HStack(spacing: 6) {
                Text(job.company)
                Text("•")
                Text(job.location)
            }
            .font(.system(size: 13))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
            .padding(.leading, 52)
            
            if !job.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(job.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.background)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(JobPost.examples) { job in
            JobPostCard(job: job)
        }
    }
    .padding()
    .background(AppTheme.background)
}
