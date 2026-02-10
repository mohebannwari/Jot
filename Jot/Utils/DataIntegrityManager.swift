import Foundation
import SwiftData
import OSLog
import CryptoKit
import Combine

/// Comprehensive data integrity and validation system for Jot app
@MainActor
final class DataIntegrityManager: ObservableObject {

    // MARK: - Singleton
    static let shared = DataIntegrityManager()

    // MARK: - Published Properties
    @Published private(set) var validationStatus: ValidationStatus = .idle
    @Published private(set) var lastValidationDate: Date?
    @Published private(set) var dataHealthScore: Double = 1.0

    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.jot.app", category: "DataIntegrity")
    private let performanceMonitor = PerformanceMonitor.shared
    private var validationTimer: Timer?

    // MARK: - Configuration
    private let validationInterval: TimeInterval = 6 * 60 * 60 // 6 hours
    private let maxValidationTime: TimeInterval = 30.0 // 30 seconds max

    private init() {
        setupPeriodicValidation()
    }

    // MARK: - Public Methods

    /// Perform comprehensive data validation
    func validateDataIntegrity() async -> ValidationResult {
        return await performanceMonitor.trackSwiftDataOperation(
            operation: .validate,
            recordCount: 0
        ) {
            await _performValidation()
        }
    }

    /// Repair data inconsistencies
    func repairDataInconsistencies() async -> RepairResult {
        return await performanceMonitor.trackSwiftDataOperation(
            operation: .repair,
            recordCount: 0
        ) {
            await _performRepair()
        }
    }

    /// Calculate data health metrics
    func calculateDataHealth() async -> DataHealthMetrics {
        return await performanceMonitor.trackSwiftDataOperation(
            operation: .healthCheck,
            recordCount: 0
        ) {
            await _calculateDataHealth()
        }
    }

    /// Validate specific note entity
    func validateNote(_ note: NoteEntity) -> NoteValidationResult {
        var issues: [ValidationIssue] = []

        // Check required fields
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyTitle)
        }

        if note.content.isEmpty {
            issues.append(.emptyContent)
        }

        // Check data consistency
        if note.createdAt > Date() {
            issues.append(.futureCreationDate)
        }

        if note.modifiedAt < note.createdAt {
            issues.append(.inconsistentDates)
        }

        // Check content integrity
        if note.content.count > 1_000_000 { // 1MB text limit
            issues.append(.contentTooLarge)
        }

        // Validate tags
        for tag in note.tags {
            if tag.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.invalidTag)
                break
            }
        }

        let severity: ValidationSeverity = issues.isEmpty ? .none :
                                         issues.contains { $0.severity == .critical } ? .critical :
                                         issues.contains { $0.severity == .warning } ? .warning : .info

        return NoteValidationResult(
            noteId: note.id,
            isValid: issues.isEmpty,
            issues: issues,
            severity: severity
        )
    }

    /// Generate data checksum for integrity verification
    func generateDataChecksum() async -> String {
        return await performanceMonitor.trackSwiftDataOperation(
            operation: .checksum,
            recordCount: 0
        ) {
            await _generateChecksum()
        }
    }

    /// Verify data against checksum
    func verifyDataIntegrity(against checksum: String) async -> Bool {
        let currentChecksum = await generateDataChecksum()
        return currentChecksum == checksum
    }
}

// MARK: - Private Implementation

private extension DataIntegrityManager {

    func _performValidation() async -> ValidationResult {
        validationStatus = .validating
        let startTime = Date()

        do {
            var totalIssues: [ValidationIssue] = []
            var noteResults: [NoteValidationResult] = []
            var validNotes = 0
            var totalNotes = 0

            // Create a background context for validation
            let container = ModelContainer.shared
            let context = ModelContext(container)

            // Fetch all notes in batches for memory efficiency
            let batchSize = 100
            var offset = 0
            var hasMoreNotes = true

            while hasMoreNotes {
                var descriptor = FetchDescriptor<NoteEntity>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset

                let notes = try context.fetch(descriptor)
                hasMoreNotes = notes.count == batchSize
                offset += batchSize
                totalNotes += notes.count

                // Validate each note
                for note in notes {
                    let result = validateNote(note)
                    noteResults.append(result)

                    if result.isValid {
                        validNotes += 1
                    } else {
                        totalIssues.append(contentsOf: result.issues)
                    }
                }

                // Check for timeout
                if Date().timeIntervalSince(startTime) > maxValidationTime {
                    logger.warning("Validation timeout reached, stopping at \(totalNotes) notes")
                    break
                }
            }

            // Validate relationships
            let relationshipIssues = try await validateRelationships(context: context)
            totalIssues.append(contentsOf: relationshipIssues)

            // Calculate health score
            let healthScore = totalNotes > 0 ? Double(validNotes) / Double(totalNotes) : 1.0
            dataHealthScore = healthScore

            let validationTime = Date().timeIntervalSince(startTime)
            lastValidationDate = Date()
            validationStatus = .completed

            let result = ValidationResult(
                isValid: totalIssues.isEmpty,
                totalNotes: totalNotes,
                validNotes: validNotes,
                totalIssues: totalIssues.count,
                healthScore: healthScore,
                validationTime: validationTime,
                noteResults: noteResults
            )

            logger.info("Data validation completed: \(validNotes)/\(totalNotes) notes valid, health score: \(String(format: "%.2f", healthScore))")
            return result

        } catch {
            validationStatus = .failed
            logger.error("Data validation failed: \(error.localizedDescription)")
            return ValidationResult(
                isValid: false,
                totalNotes: 0,
                validNotes: 0,
                totalIssues: 0,
                healthScore: 0.0,
                validationTime: Date().timeIntervalSince(startTime),
                noteResults: []
            )
        }
    }

    func _performRepair() async -> RepairResult {
        validationStatus = .repairing
        let startTime = Date()

        do {
            let container = ModelContainer.shared
            let context = ModelContext(container)
            var repairedCount = 0
            var failedRepairs: [String] = []

            // Get validation results first
            let validationResult = await _performValidation()

            // Repair notes with issues
            for noteResult in validationResult.noteResults where !noteResult.isValid {
                do {
                    let noteDescriptor = FetchDescriptor<NoteEntity>()
                    // Note: Complex predicate filtering will be done in-memory for now

                    let allNotes = try context.fetch(noteDescriptor)
                    guard let note = allNotes.first(where: { $0.id == noteResult.noteId }) else {
                        failedRepairs.append("Note not found: \(noteResult.noteId)")
                        continue
                    }

                    var wasModified = false

                    // Repair issues
                    for issue in noteResult.issues {
                        switch issue {
                        case .emptyTitle:
                            note.title = "Untitled Note"
                            wasModified = true
                        case .emptyContent:
                            note.content = "Empty note"
                            wasModified = true
                        case .futureCreationDate:
                            note.createdAt = Date()
                            wasModified = true
                        case .inconsistentDates:
                            note.modifiedAt = max(note.createdAt, note.modifiedAt)
                            wasModified = true
                        case .contentTooLarge:
                            note.content = String(note.content.prefix(1_000_000))
                            wasModified = true
                        case .invalidTag:
                            // Remove empty tags
                            note.tags.removeAll { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            wasModified = true
                        default:
                            break
                        }
                    }

                    if wasModified {
                        note.modifiedAt = Date()
                        repairedCount += 1
                    }

                } catch {
                    failedRepairs.append("Failed to repair note \(noteResult.noteId): \(error.localizedDescription)")
                }
            }

            // Save changes
            try context.save()

            let repairTime = Date().timeIntervalSince(startTime)
            validationStatus = .completed

            let result = RepairResult(
                success: true,
                repairedCount: repairedCount,
                failedRepairs: failedRepairs,
                repairTime: repairTime
            )

            logger.info("Data repair completed: \(repairedCount) items repaired, \(failedRepairs.count) failures")
            return result

        } catch {
            validationStatus = .failed
            logger.error("Data repair failed: \(error.localizedDescription)")
            return RepairResult(
                success: false,
                repairedCount: 0,
                failedRepairs: ["Repair operation failed: \(error.localizedDescription)"],
                repairTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    func _calculateDataHealth() async -> DataHealthMetrics {
        do {
            let container = ModelContainer.shared
            let context = ModelContext(container)

            // Count total notes
            let totalNotesDescriptor = FetchDescriptor<NoteEntity>()
            let totalNotes = try context.fetchCount(totalNotesDescriptor)

            // Count notes with issues
            var notesWithIssues = 0
            let batchSize = 50
            var offset = 0

            while offset < totalNotes {
                var descriptor = FetchDescriptor<NoteEntity>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset

                let notes = try context.fetch(descriptor)

                for note in notes {
                    let validation = validateNote(note)
                    if !validation.isValid {
                        notesWithIssues += 1
                    }
                }

                offset += batchSize
            }

            // Calculate metrics
            let healthScore = totalNotes > 0 ? Double(totalNotes - notesWithIssues) / Double(totalNotes) : 1.0
            let dataIntegrityScore = await verifyDataIntegrity(against: await generateDataChecksum()) ? 1.0 : 0.0

            // Storage efficiency (simplified calculation)
            let averageNoteSize = totalNotes > 0 ? 1000 : 0 // Placeholder
            let storageEfficiency = min(1.0, 1000.0 / Double(max(averageNoteSize, 1)))

            dataHealthScore = healthScore

            return DataHealthMetrics(
                healthScore: healthScore,
                dataIntegrityScore: dataIntegrityScore,
                storageEfficiency: storageEfficiency,
                totalNotes: totalNotes,
                notesWithIssues: notesWithIssues,
                lastChecked: Date()
            )

        } catch {
            logger.error("Failed to calculate data health: \(error.localizedDescription)")
            return DataHealthMetrics(
                healthScore: 0.0,
                dataIntegrityScore: 0.0,
                storageEfficiency: 0.0,
                totalNotes: 0,
                notesWithIssues: 0,
                lastChecked: Date()
            )
        }
    }

    func _generateChecksum() async -> String {
        do {
            let container = ModelContainer.shared
            let context = ModelContext(container)

            // Get all notes sorted by ID for consistent ordering
            let descriptor = FetchDescriptor<NoteEntity>(
                sortBy: [SortDescriptor(\.id)]
            )
            let notes = try context.fetch(descriptor)

            // Create checksum data
            var checksumData = Data()
            for note in notes {
                let noteData = "\(note.id.uuidString)\(note.title)\(note.content)\(note.createdAt.timeIntervalSince1970)\(note.modifiedAt.timeIntervalSince1970)".data(using: .utf8) ?? Data()
                checksumData.append(noteData)
            }

            // Generate SHA256 hash
            let hash = SHA256.hash(data: checksumData)
            return hash.compactMap { String(format: "%02x", $0) }.joined()

        } catch {
            logger.error("Failed to generate checksum: \(error.localizedDescription)")
            return ""
        }
    }

    func validateRelationships(context: ModelContext) async throws -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Validate note-tag relationships
        let notesDescriptor = FetchDescriptor<NoteEntity>()
        let notes = try context.fetch(notesDescriptor)

        for note in notes {
            for tag in note.tags {
                // Check if tag still exists and is properly linked
                if tag.notes.contains(note) == false {
                    issues.append(.brokenRelationship)
                }
            }
        }

        return issues
    }

    func setupPeriodicValidation() {
        validationTimer?.invalidate()
        validationTimer = Timer.scheduledTimer(withTimeInterval: validationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = await self?.validateDataIntegrity()
            }
        }

        logger.info("Periodic validation scheduled every \(self.validationInterval / 3600) hours")
    }
}

// MARK: - Supporting Types

enum ValidationStatus {
    case idle
    case validating
    case repairing
    case completed
    case failed
}

enum ValidationSeverity {
    case none
    case info
    case warning
    case critical
}

enum ValidationIssue {
    case emptyTitle
    case emptyContent
    case futureCreationDate
    case inconsistentDates
    case contentTooLarge
    case invalidTag
    case brokenRelationship
    case corruptedData
    case missingRequiredField

    var severity: ValidationSeverity {
        switch self {
        case .emptyTitle, .emptyContent:
            return .warning
        case .futureCreationDate, .inconsistentDates:
            return .warning
        case .contentTooLarge:
            return .critical
        case .invalidTag:
            return .info
        case .brokenRelationship, .corruptedData:
            return .critical
        case .missingRequiredField:
            return .critical
        }
    }

    var description: String {
        switch self {
        case .emptyTitle:
            return "Note has empty title"
        case .emptyContent:
            return "Note has empty content"
        case .futureCreationDate:
            return "Note creation date is in the future"
        case .inconsistentDates:
            return "Note update date is before creation date"
        case .contentTooLarge:
            return "Note content exceeds size limit"
        case .invalidTag:
            return "Note has invalid tags"
        case .brokenRelationship:
            return "Broken relationship between entities"
        case .corruptedData:
            return "Data corruption detected"
        case .missingRequiredField:
            return "Required field is missing"
        }
    }
}

struct ValidationResult: Sendable {
    let isValid: Bool
    let totalNotes: Int
    let validNotes: Int
    let totalIssues: Int
    let healthScore: Double
    let validationTime: TimeInterval
    let noteResults: [NoteValidationResult]
}

struct NoteValidationResult: Sendable {
    let noteId: UUID
    let isValid: Bool
    let issues: [ValidationIssue]
    let severity: ValidationSeverity
}

struct RepairResult: Sendable {
    let success: Bool
    let repairedCount: Int
    let failedRepairs: [String]
    let repairTime: TimeInterval
}

struct DataHealthMetrics: Sendable {
    let healthScore: Double
    let dataIntegrityScore: Double
    let storageEfficiency: Double
    let totalNotes: Int
    let notesWithIssues: Int
    let lastChecked: Date
}


// MARK: - ModelContainer Extension

extension ModelContainer {
    static let shared: ModelContainer = {
        do {
            let schema = Schema([NoteEntity.self, TagEntity.self, FolderEntity.self])
            let config = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
