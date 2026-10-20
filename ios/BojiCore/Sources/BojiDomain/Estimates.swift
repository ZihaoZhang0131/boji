import Foundation

public enum EstimateSource: String, Codable, Sendable { case model, manual, demo }
public struct FoodItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var grams: Decimal?
    public var kcal: Decimal
    public var referenceGrams: Decimal?
    public var referenceKcal: Decimal
    public var assumptions: [String] = []
    public init(id: UUID = UUID(), name: String, grams: Decimal?, kcal: Decimal) {
        self.id = id; self.name = name; self.grams = grams; self.kcal = kcal
        referenceGrams = grams; referenceKcal = kcal
    }
}
public struct EstimateRange: Codable, Equatable, Sendable {
    public var low: Decimal
    public var high: Decimal
    public init(low: Decimal, high: Decimal) { self.low = low; self.high = high }
}
public struct EstimateRevision: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var recordID: UUID
    public var inputRevision: Int64
    public var source: EstimateSource
    public var items: [FoodItem]
    public var totalKcal: Decimal
    public var range: EstimateRange?
    public var questions: [String] = []
    public var provider: String?
    public var model: String?
    public var promptVersion: String?
    public var previousRevisionID: UUID?
    public var createdAt: Date
    public init(id: UUID = UUID(), recordID: UUID, inputRevision: Int64, source: EstimateSource, items: [FoodItem], totalKcal: Decimal, createdAt: Date) {
        self.id = id; self.recordID = recordID; self.inputRevision = inputRevision; self.source = source
        self.items = items; self.totalKcal = totalKcal; self.createdAt = createdAt
    }
}

public enum EstimateJobStatus: String, Codable, Sendable {
    case pendingNetwork, queued, running, succeeded, failed, cancelled
    public var isTerminal: Bool { [.succeeded, .failed, .cancelled].contains(self) }
}
public struct EstimateJob: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var datasetID: UUID
    public var recordID: UUID
    public var inputRevision: Int64
    public var lifecycleEpoch: Int64
    public var manualRevision: Int64
    public var consentEpoch: Int64
    public var policyVersion: String
    public var photoIDs: [UUID]
    public var note: String
    public var automatic: Bool
    public var queuedAt: Date
    public var requestCreatedAt: Date?
    public var remoteJobID: String?
    public var draftID: UUID?
    public var uploadedReferences: [String]?
    public var remoteCancellationPending: Bool?
    public var nextAttemptAt: Date?
    public var retryOf: String?
    public var serviceURL: URL?
    public var status: EstimateJobStatus = .pendingNetwork
    public var deadline: Date?
    public var attempts = 0
    public var errorCode: String?
    public init(id: UUID = UUID(), datasetID: UUID, meal: Meal, consentEpoch: Int64, policyVersion: String, automatic: Bool, queuedAt: Date) {
        self.id = id; self.datasetID = datasetID; recordID = meal.id; inputRevision = meal.inputRevision
        lifecycleEpoch = meal.lifecycleEpoch; manualRevision = meal.manualRevision; self.consentEpoch = consentEpoch
        self.policyVersion = policyVersion; photoIDs = meal.photoIDs; note = meal.note; self.automatic = automatic; self.queuedAt = queuedAt
    }
}
public struct AISettings: Codable, Equatable, Sendable {
    public var serviceURL: URL?
    public var acceptedPolicy: String?
    public var consentEpoch: Int64 = 0
    public var automatic = false
    public var cachedPolicy: AIServicePolicy?
    public init() {}
}
public enum BackupStatus: String, Codable, Sendable {
    case disconnected, dirty, writing, written, pendingUpload, uploadConfirmed, failed, unknown
}
public struct BackupState: Codable, Equatable, Sendable {
    public var directoryBookmark: Data?
    public var directoryLabel: String?
    public var lastError: String?
    public var retryCount: Int?
    public var nextRetryAt: Date?
    public var lastPublishedRevision: Int64?
    public var dirty = false
    public var activeExportID: UUID?
    public var activePointerSHA256: String?
    public var pointerSHA256: String?
    public var lastWrittenAt: Date?
    public var status: BackupStatus = .disconnected
    public init() {}
}
