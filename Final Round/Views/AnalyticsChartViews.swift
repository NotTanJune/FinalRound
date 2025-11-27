import SwiftUI
import Charts

// MARK: - Time Spent Chart

struct TimeSpentChart: View {
    let questions: [InterviewQuestion]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Spent per Question")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        if let timeSpent = question.answer?.timeSpent {
                            BarMark(
                                x: .value("Question", "Q\(index + 1)"),
                                y: .value("Time", timeSpent)
                            )
                            .foregroundStyle(barColor(for: timeSpent))
                            .annotation(position: .top) {
                                Text("\(Int(timeSpent))s")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text("\(Int(seconds))s")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            } else {
                // Fallback for iOS 15
                LegacyBarChart(data: questions.compactMap { $0.answer?.timeSpent })
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func barColor(for timeSpent: TimeInterval) -> Color {
        switch timeSpent {
        case 0..<30: return Color.orange
        case 30..<120: return AppTheme.primary
        default: return Color.blue
        }
    }
}

// MARK: - Eye Contact Chart

struct EyeContactChart: View {
    let questions: [InterviewQuestion]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Eye Contact Percentage")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        if let eyeContact = question.answer?.eyeContactMetrics {
                            LineMark(
                                x: .value("Question", index + 1),
                                y: .value("Eye Contact", eyeContact.percentage)
                            )
                            .foregroundStyle(AppTheme.primary)
                            .interpolationMethod(.catmullRom)
                            
                            AreaMark(
                                x: .value("Question", index + 1),
                                y: .value("Eye Contact", eyeContact.percentage)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.primary.opacity(0.3), AppTheme.primary.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                            
                            PointMark(
                                x: .value("Question", index + 1),
                                y: .value("Eye Contact", eyeContact.percentage)
                            )
                            .foregroundStyle(AppTheme.primary)
                        }
                    }
                    
                    // Reference line at 60%
                    RuleMark(y: .value("Target", 60))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("Target")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.gray)
                        }
                }
                .frame(height: 200)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let percent = value.as(Double.self) {
                                Text("\(Int(percent))%")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let num = value.as(Int.self) {
                                Text("Q\(num)")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            } else {
                LegacyLineChart(data: questions.compactMap { $0.answer?.eyeContactMetrics?.percentage })
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
}

// MARK: - Confidence Score Chart

struct ConfidenceScoreChart: View {
    let questions: [InterviewQuestion]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confidence Score Trend")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        if let confidence = question.answer?.confidenceScore {
                            LineMark(
                                x: .value("Question", index + 1),
                                y: .value("Confidence", confidence)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [scoreColor(for: confidence), scoreColor(for: confidence).opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .interpolationMethod(.catmullRom)
                            
                            AreaMark(
                                x: .value("Question", index + 1),
                                y: .value("Confidence", confidence)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [scoreColor(for: confidence).opacity(0.3), scoreColor(for: confidence).opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                            
                            PointMark(
                                x: .value("Question", index + 1),
                                y: .value("Confidence", confidence)
                            )
                            .foregroundStyle(scoreColor(for: confidence))
                            .symbolSize(60)
                        }
                    }
                }
                .frame(height: 200)
                .chartYScale(domain: 0...10)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 2.5, 5, 7.5, 10]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let score = value.as(Double.self) {
                                Text(String(format: "%.1f", score))
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let num = value.as(Int.self) {
                                Text("Q\(num)")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            } else {
                LegacyLineChart(data: questions.compactMap { $0.answer?.confidenceScore })
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    private func scoreColor(for score: Double) -> Color {
        switch score {
        case 8...10: return AppTheme.primary
        case 6..<8: return Color.blue
        case 4..<6: return Color.orange
        default: return AppTheme.softRed
        }
    }
}

// MARK: - Metrics Summary Cards

struct MetricsSummaryCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
}

struct AnalyticsOverviewCards: View {
    let session: InterviewSession
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricsSummaryCard(
                    icon: "eye.fill",
                    title: "Avg Eye Contact",
                    value: String(format: "%.0f%%", session.averageEyeContact),
                    subtitle: eyeContactSubtitle,
                    color: eyeContactColor
                )
                
                MetricsSummaryCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Avg Confidence",
                    value: String(format: "%.1f/10", session.averageConfidenceScore),
                    subtitle: confidenceSubtitle,
                    color: confidenceColor
                )
            }
            
            HStack(spacing: 12) {
                MetricsSummaryCard(
                    icon: "waveform",
                    title: "Speech Pace",
                    value: String(format: "%.0f WPM", session.averageSpeechPace),
                    subtitle: paceSubtitle,
                    color: paceColor
                )
                
                MetricsSummaryCard(
                    icon: "clock.fill",
                    title: "Total Time",
                    value: session.formattedDuration,
                    subtitle: "\(session.answeredCount) questions",
                    color: AppTheme.primary
                )
            }
        }
    }
    
    private var eyeContactColor: Color {
        session.averageEyeContact >= 60 ? AppTheme.primary : Color.orange
    }
    
    private var eyeContactSubtitle: String {
        session.averageEyeContact >= 60 ? "Excellent" : "Needs improvement"
    }
    
    private var confidenceColor: Color {
        switch session.averageConfidenceScore {
        case 8...10: return AppTheme.primary
        case 6..<8: return Color.blue
        case 4..<6: return Color.orange
        default: return AppTheme.softRed
        }
    }
    
    private var confidenceSubtitle: String {
        switch session.averageConfidenceScore {
        case 8...10: return "Very confident"
        case 6..<8: return "Good confidence"
        case 4..<6: return "Moderate"
        default: return "Needs work"
        }
    }
    
    private var paceColor: Color {
        switch session.averageSpeechPace {
        case 120...150: return AppTheme.primary
        case 100..<120, 150..<180: return Color.blue
        default: return Color.orange
        }
    }
    
    private var paceSubtitle: String {
        switch session.averageSpeechPace {
        case 120...150: return "Optimal pace"
        case 100..<120: return "Slightly slow"
        case 150..<180: return "Slightly fast"
        default: return "Adjust pace"
        }
    }
}

// MARK: - Legacy Charts (iOS 15 Fallback)

struct LegacyBarChart: View {
    let data: [TimeInterval]
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                VStack {
                    Rectangle()
                        .fill(AppTheme.primary)
                        .frame(height: CGFloat(value) * 2)
                    Text("Q\(index + 1)")
                        .font(.system(size: 10))
                }
            }
        }
        .frame(height: 200)
    }
}

struct LegacyLineChart: View {
    let data: [Double]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !data.isEmpty else { return }
                let width = geometry.size.width
                let height = geometry.size.height
                let stepX = width / CGFloat(data.count - 1)
                let maxValue = data.max() ?? 100
                
                path.move(to: CGPoint(x: 0, y: height - (CGFloat(data[0]) / CGFloat(maxValue)) * height))
                
                for (index, value) in data.enumerated().dropFirst() {
                    let x = CGFloat(index) * stepX
                    let y = height - (CGFloat(value) / CGFloat(maxValue)) * height
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(AppTheme.primary, lineWidth: 2)
        }
        .frame(height: 200)
    }
}

