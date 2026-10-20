import Foundation

public enum DatasetMode: String, Codable, Sendable { case personal, demo }
public enum RecordKind: String, Codable, Sendable { case meal, workout }

public struct Dataset: Codable, Equatable, Sendable {
    public var id: UUID
    public var schemaVersion = 1
    public var revision: Int64 = 0
    public var mode: DatasetMode
    public init(id: UUID = UUID(), mode: DatasetMode = .personal) { self.id = id; self.mode = mode }
}

public struct SourceIdentity: Codable, Hashable, Sendable {
    public var datasetID: UUID
    public var entityID: UUID
    public var kind: String
    public init(datasetID: UUID, entityID: UUID, kind: String) {
        self.datasetID = datasetID; self.entityID = entityID; self.kind = kind
    }
}

/// External lineage for entities without a dedicated source field, including immutable media versions.
public struct EntityOrigin: Codable, Equatable, Identifiable, Sendable {
    public var kind: String
    public var localID: UUID
    public var source: SourceIdentity
    public var contentHash: String?
    public var id: String { kind + "/" + localID.uuidString }
    public init(kind: String, localID: UUID, source: SourceIdentity, contentHash: String? = nil) {
        self.kind = kind; self.localID = localID; self.source = source; self.contentHash = contentHash
    }
}

public struct Meal: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var time: RecordTime
    public var note = ""
    public var slot: String?
    public var tags: [String] = []
    public var photoIDs: [UUID] = []
    public var factsRevision: Int64 = 0
    public var inputRevision: Int64 = 0
    public var lifecycleEpoch: Int64 = 0
    public var manualRevision: Int64 = 0
    public var currentEstimateID: UUID?
    public var deletedAt: Date?
    public var source: SourceIdentity?
    public var isDemo = false
    public init(id: UUID = UUID(), time: RecordTime) { self.id = id; self.time = time }
}

public struct PhotoAsset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sha256: String
    public var relativePath: String
    public var mimeType: String
    public var byteCount: Int
    public var width: Int
    public var height: Int
    public init(id: UUID = UUID(), sha256: String, relativePath: String, mimeType: String, byteCount: Int, width: Int, height: Int) {
        self.id = id; self.sha256 = sha256; self.relativePath = relativePath; self.mimeType = mimeType
        self.byteCount = byteCount; self.width = width; self.height = height
    }
}

public enum ExerciseKind: String, Codable, Sendable { case weighted, bodyweight }
public struct WorkoutSet: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var weightKG: Decimal?
    public var reps: Int?
    public var completed: Bool
    public init(id: UUID = UUID(), weightKG: Decimal? = nil, reps: Int? = nil, completed: Bool = false) {
        self.id = id; self.weightKG = weightKG; self.reps = reps; self.completed = completed
    }
}
public struct Exercise: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ExerciseKind
    public var weightConvention: String
    public var sets: [WorkoutSet]
    public init(id: UUID = UUID(), name: String, kind: ExerciseKind, weightConvention: String = "总重量（kg）", sets: [WorkoutSet] = []) {
        self.id = id; self.name = name; self.kind = kind; self.weightConvention = weightConvention; self.sets = sets
    }
}

public enum TrainingIntensity: String, Codable, CaseIterable, Sendable {
    case regular, compound, vigorous
    public var met: Decimal { switch self { case .regular: 3.5; case .compound: 5; case .vigorous: 6 } }
    public var title: String { switch self { case .regular: "常规力量"; case .compound: "深蹲／硬拉为主"; case .vigorous: "高强度力量" } }
}
public struct WorkoutEnergy: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var weightKG: Decimal?
    public var minutes: Decimal?
    public var intensity: TrainingIntensity
    public var profileVersionID: UUID?
    public var kcal: Int?
    public var algorithmVersion: String
    public var createdAt: Date
    public init(weightKG: Decimal?, minutes: Decimal?, intensity: TrainingIntensity, profileVersionID: UUID?, kcal: Int?, algorithmVersion: String, createdAt: Date) {
        self.weightKG = weightKG; self.minutes = minutes; self.intensity = intensity
        self.profileVersionID = profileVersionID; self.kcal = kcal; self.algorithmVersion = algorithmVersion; self.createdAt = createdAt
    }
}
public struct Workout: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var time: RecordTime
    public var name = ""
    public var exercises: [Exercise] = []
    public var energyHistory: [WorkoutEnergy] = []
    public var currentEnergyID: UUID?
    public var factsRevision: Int64 = 0
    public var lifecycleEpoch: Int64 = 0
    public var deletedAt: Date?
    public var source: SourceIdentity?
    public var isDemo = false
    public init(id: UUID = UUID(), time: RecordTime) { self.id = id; self.time = time }
}

public enum DraftContent: Codable, Equatable, Sendable {
    case meal(Meal)
    case workout(Workout)
    public var recordID: UUID { switch self { case .meal(let value): value.id; case .workout(let value): value.id } }
    public var kind: RecordKind { switch self { case .meal: .meal; case .workout: .workout } }
    public var photoIDs: [UUID] { switch self { case .meal(let value): value.photoIDs; case .workout: [] } }
}
public struct RecordDraft: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var editingRecordID: UUID?
    public var content: DraftContent
    public var savedAt: Date
    public var revision: Int64 = 0
    public var workoutFields: WorkoutDraftFields?
    public init(id: UUID = UUID(), editingRecordID: UUID? = nil, content: DraftContent, savedAt: Date) {
        self.id = id; self.editingRecordID = editingRecordID; self.content = content; self.savedAt = savedAt
    }
}

/// Preserve incomplete and invalid keyboard input in drafts without allowing it into formal sets.
public struct WorkoutDraftFields: Codable, Equatable, Sendable {
    public var weightText: [UUID: String] = [:]
    public var repsText: [UUID: String] = [:]
    public var minutesText = ""
    public var intensity: TrainingIntensity = .regular
    public var reestimate = false
    public init() {}
}

public enum FormulaSex: String, Codable, CaseIterable, Sendable { case male, female }
public struct BodyProfile: Codable, Equatable, Sendable {
    public var sex: FormulaSex
    public var age: Int
    public var heightCM: Decimal
    public var weightKG: Decimal
    public var activityFactor: Decimal
    public var targetKcal: Decimal?
    public init(sex: FormulaSex, age: Int, heightCM: Decimal, weightKG: Decimal, activityFactor: Decimal, targetKcal: Decimal? = nil) {
        self.sex = sex; self.age = age; self.heightCM = heightCM; self.weightKG = weightKG
        self.activityFactor = activityFactor; self.targetKcal = targetKcal
    }
}
public struct ProfileVersion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var effectiveDay: LocalDay
    public var sequence: Int64
    public var profile: BodyProfile
    public var createdAt: Date
    public var source: SourceIdentity?
    public init(id: UUID = UUID(), effectiveDay: LocalDay, sequence: Int64, profile: BodyProfile, createdAt: Date) {
        self.id = id; self.effectiveDay = effectiveDay; self.sequence = sequence; self.profile = profile; self.createdAt = createdAt
    }
}
public enum Goal: String, Codable, CaseIterable, Sendable {
    case loseSlowly, gainSteadily, maintain
    public var title: String { switch self { case .loseSlowly: "缓慢减脂"; case .gainSteadily: "稳步增肌"; case .maintain: "保持状态" } }
}
public struct GoalStage: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startDay: LocalDay
    public var endDay: LocalDay?
    public var goal: Goal
    public var note = ""
    public var sequence: Int64
    public var source: SourceIdentity?
    public init(id: UUID = UUID(), startDay: LocalDay, goal: Goal, sequence: Int64) {
        self.id = id; self.startDay = startDay; self.goal = goal; self.sequence = sequence
    }
}
public struct DayConfirmation: Codable, Equatable, Identifiable, Sendable {
    public var id: String { day.description }
    public var day: LocalDay
    public var confirmedAt: Date
    public var factsRevision: Int64
    public init(day: LocalDay, confirmedAt: Date, factsRevision: Int64) {
        self.day = day; self.confirmedAt = confirmedAt; self.factsRevision = factsRevision
    }
}
public struct DeletionTombstone: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(source.datasetID)/\(source.kind)/\(source.entityID)" }
    public var source: SourceIdentity
    public var deletedAt: Date
    public init(source: SourceIdentity, deletedAt: Date) { self.source = source; self.deletedAt = deletedAt }
}
