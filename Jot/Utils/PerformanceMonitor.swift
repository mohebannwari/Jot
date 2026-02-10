import Foundation
import OSLog
import SwiftUI
import Combine

/// Comprehensive performance monitoring and analytics system for iOS 26+ and macOS 26+
@MainActor
@Observable
final class PerformanceMonitor {

    // MARK: - Singleton
    static let shared = PerformanceMonitor()

    // MARK: - Performance Metrics
    var currentMemoryUsage: Double = 0.0
    var averageResponseTime: TimeInterval = 0.0
    var totalOperations: Int = 0
    var errorCount: Int = 0

    // MARK: - Analytics Data
    private var operationMetrics: [String: OperationMetrics] = [:]
    private var featureUsage: [String: Int] = [:]
    private var sessionStartTime: Date = Date()
    private var lastMemoryCheck: Date = Date()

    // MARK: - Logging
    private let logger = Logger(subsystem: "com.jot.app", category: "PerformanceMonitor")
    private let analyticsLogger = Logger(subsystem: "com.jot.app", category: "Analytics")

    // MARK: - Configuration
    private let memoryCheckInterval: TimeInterval = 5.0
    private let metricsRetentionDays = 7

    private init() {
        startMonitoring()
    }

    // MARK: - Monitoring Lifecycle

    private func startMonitoring() {
        sessionStartTime = Date()
        logger.info("Performance monitoring started")

        // Start periodic memory monitoring
        Timer.scheduledTimer(withTimeInterval: memoryCheckInterval, repeats: true) { _ in
            Task { @MainActor in
                self.updateMemoryUsage()
            }
        }
    }

    // MARK: - Memory Monitoring

    private func updateMemoryUsage() {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let memoryUsageMB = Double(memoryInfo.resident_size) / 1024.0 / 1024.0
            currentMemoryUsage = memoryUsageMB

            // Log significant memory changes
            if abs(memoryUsageMB - currentMemoryUsage) > 10.0 {
                logger.info("Memory usage changed significantly: \(memoryUsageMB, privacy: .public)MB")
            }
        }

        lastMemoryCheck = Date()
    }

    // MARK: - Operation Tracking

    func trackOperation<T>(
        name: String,
        category: OperationCategory = .general,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let operationId = UUID().uuidString

        logger.info("Starting operation: \(name) (ID: \(operationId))")

        do {
            let result = try await operation()
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            recordOperationMetrics(name: name, category: category, duration: duration, success: true)
            logger.info("Operation completed: \(name) in \(duration, privacy: .public)s")

            return result
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            recordOperationMetrics(name: name, category: category, duration: duration, success: false)

            logger.error("Operation failed: \(name) after \(duration, privacy: .public)s - \(error)")
            errorCount += 1

            throw error
        }
    }

    private func recordOperationMetrics(name: String, category: OperationCategory, duration: TimeInterval, success: Bool) {
        totalOperations += 1

        if operationMetrics[name] == nil {
            operationMetrics[name] = OperationMetrics(name: name, category: category)
        }

        operationMetrics[name]?.recordExecution(duration: duration, success: success)

        // Update global average
        let totalDuration = operationMetrics.values.reduce(0) { $0 + $1.totalDuration }
        averageResponseTime = totalDuration / Double(totalOperations)
    }

    // MARK: - Feature Usage Tracking

    func trackFeatureUsage(_ feature: String) {
        featureUsage[feature, default: 0] += 1
        analyticsLogger.info("Feature used: \(feature) (total: \(self.featureUsage[feature] ?? 0))")
    }

    // MARK: - SwiftData Specific Monitoring

    func trackSwiftDataOperation<T: Sendable>(
        operation: SwiftDataOperation,
        recordCount: Int = 0,
        execution: @Sendable () async throws -> T
    ) async rethrows -> T {
        let operationName = "SwiftData.\(operation.rawValue)"

        return try await trackOperation(name: operationName, category: .database) {
            let result = try await execution()

            // Additional SwiftData-specific logging
            if recordCount > 0 {
                logger.info("SwiftData \(operation.rawValue) processed \(recordCount) records")
            }

            return result
        }
    }

    // MARK: - Health Check

    func performHealthCheck() -> AppHealthStatus {
        let memoryHealthy = currentMemoryUsage < 100.0 // Less than 100MB
        let errorRateHealthy = errorCount < (totalOperations / 10) // Less than 10% error rate
        let responseTimeHealthy = averageResponseTime < 1.0 // Less than 1 second average

        let overallHealthy = memoryHealthy && errorRateHealthy && responseTimeHealthy

        let status = AppHealthStatus(
            isHealthy: overallHealthy,
            memoryUsageMB: currentMemoryUsage,
            averageResponseTime: averageResponseTime,
            errorRate: totalOperations > 0 ? Double(errorCount) / Double(totalOperations) : 0.0,
            uptime: Date().timeIntervalSince(sessionStartTime)
        )

        logger.info("Health check completed: \(overallHealthy ? "HEALTHY" : "UNHEALTHY")")
        return status
    }

    // MARK: - Analytics Reporting

    func generateAnalyticsReport() -> AnalyticsReport {
        let report = AnalyticsReport(
            sessionDuration: Date().timeIntervalSince(sessionStartTime),
            totalOperations: totalOperations,
            averageResponseTime: averageResponseTime,
            memoryUsage: currentMemoryUsage,
            errorCount: errorCount,
            featureUsage: featureUsage,
            operationMetrics: operationMetrics,
            timestamp: Date()
        )

        logger.info("Analytics report generated - Operations: \(self.totalOperations), Errors: \(self.errorCount)")
        return report
    }

    // MARK: - Export and Cleanup

    func exportMetrics() -> String {
        let report = generateAnalyticsReport()

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            let data = try encoder.encode(report)
            return String(data: data, encoding: .utf8) ?? "Failed to encode metrics"
        } catch {
            logger.error("Failed to export metrics: \(error)")
            return "Export failed: \(error.localizedDescription)"
        }
    }

    func resetMetrics() {
        operationMetrics.removeAll()
        featureUsage.removeAll()
        totalOperations = 0
        errorCount = 0
        averageResponseTime = 0.0
        sessionStartTime = Date()

        logger.info("Performance metrics reset")
    }
}

// MARK: - Supporting Types

struct OperationMetrics: Codable {
    let name: String
    let category: OperationCategory
    private var executions: [ExecutionRecord] = []

    var executionCount: Int { executions.count }
    var successCount: Int { executions.filter { $0.success }.count }
    var averageDuration: TimeInterval {
        executions.isEmpty ? 0 : executions.reduce(0) { $0 + $1.duration } / Double(executions.count)
    }
    var totalDuration: TimeInterval { executions.reduce(0) { $0 + $1.duration } }
    var successRate: Double {
        executions.isEmpty ? 0 : Double(successCount) / Double(executionCount)
    }

    init(name: String, category: OperationCategory) {
        self.name = name
        self.category = category
    }

    mutating func recordExecution(duration: TimeInterval, success: Bool) {
        executions.append(ExecutionRecord(duration: duration, success: success, timestamp: Date()))

        // Keep only recent executions to manage memory
        if executions.count > 1000 {
            executions = Array(executions.suffix(500))
        }
    }
}

struct ExecutionRecord: Codable {
    let duration: TimeInterval
    let success: Bool
    let timestamp: Date
}

enum OperationCategory: String, Codable, CaseIterable {
    case database = "database"
    case ui = "ui"
    case network = "network"
    case file = "file"
    case general = "general"
}

enum SwiftDataOperation: String, CaseIterable {
    case fetch = "fetch"
    case insert = "insert"
    case update = "update"
    case delete = "delete"
    case save = "save"
    case migration = "migration"
    case search = "search"
    case backup = "backup"
    case restore = "restore"
    case export = "export"
    case dataImport = "import"
    case validate = "validate"
    case repair = "repair"
    case healthCheck = "healthCheck"
    case checksum = "checksum"
}

struct AppHealthStatus: Codable {
    let isHealthy: Bool
    let memoryUsageMB: Double
    let averageResponseTime: TimeInterval
    let errorRate: Double
    let uptime: TimeInterval
    let timestamp: Date = Date()
}

struct AnalyticsReport: Codable {
    let sessionDuration: TimeInterval
    let totalOperations: Int
    let averageResponseTime: TimeInterval
    let memoryUsage: Double
    let errorCount: Int
    let featureUsage: [String: Int]
    let operationMetrics: [String: OperationMetrics]
    let timestamp: Date
}

// MARK: - Memory Info Helper

struct mach_task_basic_info {
    var virtual_size: mach_vm_size_t = 0
    var resident_size: mach_vm_size_t = 0
    var resident_size_max: mach_vm_size_t = 0
    var user_time: time_value_t = time_value_t()
    var system_time: time_value_t = time_value_t()
    var policy: policy_t = 0
    var suspend_count: integer_t = 0
}