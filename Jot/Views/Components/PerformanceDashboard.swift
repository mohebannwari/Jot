import SwiftUI
import OSLog

/// Performance dashboard for monitoring app health and analytics
struct PerformanceDashboard: View {
    @State private var healthStatus: AppHealthStatus?
    @State private var analyticsReport: AnalyticsReport?
    @State private var isExpanded = false
    @State private var refreshTimer: Timer?

    private let performanceMonitor = PerformanceMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with toggle
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(healthStatus?.isHealthy == true ? .green : .orange)

                Text("Performance Monitor")
                    .font(.headline)

                Spacer()

                Button(isExpanded ? "Collapse" : "Expand") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                performanceContent
            } else {
                compactStatus
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            refreshData()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    @ViewBuilder
    private var compactStatus: some View {
        HStack(spacing: 16) {
            if let status = healthStatus {
                StatusIndicator(
                    title: "Health",
                    value: status.isHealthy ? "Good" : "Poor",
                    color: status.isHealthy ? .green : .red
                )

                StatusIndicator(
                    title: "Memory",
                    value: "\(Int(status.memoryUsageMB))MB",
                    color: status.memoryUsageMB < 100 ? .green : .orange
                )

                StatusIndicator(
                    title: "Response",
                    value: "\(Int(status.averageResponseTime * 1000))ms",
                    color: status.averageResponseTime < 0.5 ? .green : .orange
                )
            } else {
                Text("Loading...")
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var performanceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Health Status Section
            if let status = healthStatus {
                healthStatusSection(status)
            }

            Divider()

            // Analytics Report Section
            if let report = analyticsReport {
                analyticsSection(report)
            }

            Divider()

            // Controls
            controlsSection
        }
    }

    @ViewBuilder
    private func healthStatusSection(_ status: AppHealthStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System Health")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                MetricCard(
                    title: "Memory Usage",
                    value: "\(String(format: "%.1f", status.memoryUsageMB))MB",
                    subtitle: status.memoryUsageMB < 100 ? "Good" : "High",
                    color: status.memoryUsageMB < 100 ? .green : .orange
                )

                MetricCard(
                    title: "Response Time",
                    value: "\(String(format: "%.0f", status.averageResponseTime * 1000))ms",
                    subtitle: status.averageResponseTime < 0.5 ? "Fast" : "Slow",
                    color: status.averageResponseTime < 0.5 ? .green : .orange
                )

                MetricCard(
                    title: "Error Rate",
                    value: "\(String(format: "%.1f", status.errorRate * 100))%",
                    subtitle: status.errorRate < 0.05 ? "Low" : "High",
                    color: status.errorRate < 0.05 ? .green : .red
                )

                MetricCard(
                    title: "Uptime",
                    value: formatUptime(status.uptime),
                    subtitle: "Session",
                    color: .blue
                )
            }
        }
    }

    @ViewBuilder
    private func analyticsSection(_ report: AnalyticsReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analytics")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                MetricCard(
                    title: "Operations",
                    value: "\(report.totalOperations)",
                    subtitle: "Total",
                    color: .blue
                )

                MetricCard(
                    title: "Errors",
                    value: "\(report.errorCount)",
                    subtitle: "Total",
                    color: report.errorCount == 0 ? .green : .red
                )
            }

            // Feature Usage
            if !report.featureUsage.isEmpty {
                Text("Feature Usage")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.top, 4)

                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(report.featureUsage.sorted(by: { $0.value > $1.value }), id: \.key) { feature, count in
                        HStack {
                            Text(feature.capitalized)
                                .font(.caption)
                            Spacer()
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(16)
            }
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        HStack {
            Button("Refresh") {
                refreshData()
            }
            .buttonStyle(.borderedProminent)

            Button("Export Metrics") {
                exportMetrics()
            }
            .buttonStyle(.bordered)

            Button("Reset") {
                resetMetrics()
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)

            Spacer()

            Text("Last updated: \(formatTimestamp(Date()))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helper Methods

    private func refreshData() {
        healthStatus = performanceMonitor.performHealthCheck()
        analyticsReport = performanceMonitor.generateAnalyticsReport()
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            refreshData()
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func exportMetrics() {
        let metrics = performanceMonitor.exportMetrics()
        // In a real app, you might save to file or share
        print("Exported metrics:\n\(metrics)")
    }

    private func resetMetrics() {
        performanceMonitor.resetMetrics()
        refreshData()
    }

    private func formatUptime(_ uptime: TimeInterval) -> String {
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct StatusIndicator: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - Preview

#Preview {
    PerformanceDashboard()
        .frame(width: 600, height: 400)
        .padding()
}
