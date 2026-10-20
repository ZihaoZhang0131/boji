import Foundation
import BojiDomain

/// An explicit allowlist. Runtime jobs, credentials, consent and directory bookmarks never enter this type.
public struct PackageRecords: Codable, Equatable, Sendable {
    public var meals: [Meal]
    public var workouts: [Workout]
    public var photos: [PhotoAsset]
    public var confirmations: [DayConfirmation]
    public var daySummaries: [DayReview]
    public var origins: [EntityOrigin]?
}
public struct PackageTrash: Codable, Equatable, Sendable {
    public var meals: [Meal]
    public var workouts: [Workout]
    public var tombstones: [DeletionTombstone]
}
public struct PackageDraft: Codable, Equatable, Sendable {
    public var id: UUID
    public var editingRecordID: UUID?
    public var kind: RecordKind
    public var meal: Meal?
    public var workout: Workout?
    public var savedAt: Date
    public var revision: Int64
    public var weightText: [String: String]?
    public var repsText: [String: String]?
    public var minutesText: String?
    public var intensity: TrainingIntensity?
    public var reestimate: Bool?
    public init(_ draft: RecordDraft) {
        id = draft.id; editingRecordID = draft.editingRecordID; kind = draft.content.kind
        switch draft.content { case .meal(let value): meal = value; case .workout(let value): workout = value }
        savedAt = draft.savedAt; revision = draft.revision
        if let fields = draft.workoutFields {
            weightText = Dictionary(uniqueKeysWithValues: fields.weightText.map { ($0.key.uuidString, $0.value) })
            repsText = Dictionary(uniqueKeysWithValues: fields.repsText.map { ($0.key.uuidString, $0.value) })
            minutesText = fields.minutesText; intensity = fields.intensity; reestimate = fields.reestimate
        }
    }
    public func domain() throws -> RecordDraft {
        let content: DraftContent
        switch kind {
        case .meal: guard let meal, workout == nil else { throw DomainError.corruptStore }; content = .meal(meal)
        case .workout: guard let workout, meal == nil else { throw DomainError.corruptStore }; content = .workout(workout)
        }
        var value = RecordDraft(id: id, editingRecordID: editingRecordID, content: content, savedAt: savedAt); value.revision = revision
        if kind == .workout, weightText != nil || repsText != nil || minutesText != nil {
            var fields = WorkoutDraftFields()
            for (key, text) in weightText ?? [:] { guard let id = UUID(uuidString: key) else { throw DomainError.corruptStore }; fields.weightText[id] = text }
            for (key, text) in repsText ?? [:] { guard let id = UUID(uuidString: key) else { throw DomainError.corruptStore }; fields.repsText[id] = text }
            fields.minutesText = minutesText ?? ""; fields.intensity = intensity ?? .regular; fields.reestimate = reestimate ?? false
            value.workoutFields = fields
        }
        return value
    }
}
public struct PackageFile: Codable, Equatable, Sendable {
    public var path: String
    public var byteCount: Int
    public var sha256: String
    enum CodingKeys: String, CodingKey { case path, byteCount = "byte_count", sha256 }
}
public struct PackageManifest: Codable, Equatable, Sendable {
    public var schemaVersion = PackageVersion.current
    public var datasetID: UUID
    public var exportID: UUID
    public var createdAt: Date
    public var revision: Int64
    public var units: [String: String] = ["energy":"kcal", "mass":"kg", "food_mass":"g", "height":"cm", "duration":"minute"]
    public var timeConvention = "Date values: Unix seconds UTC; record localDay/hour/minute and IANA timeZoneIdentifier preserve recording calendar."
    public var counts: [String: Int]
    public var files: [PackageFile]
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", datasetID = "dataset_id", exportID = "export_id", createdAt = "created_at", revision, units, timeConvention = "time_convention", counts, files
    }
}
public struct PackageContents: Sendable {
    public var records: PackageRecords
    public var profiles: [ProfileVersion]
    public var goals: [GoalStage]
    public var estimates: [EstimateRevision]
    public var drafts: [PackageDraft]
    public var trash: PackageTrash
    public init(snapshot: DatasetSnapshot) throws {
        try ExportPolicy.requirePersonalDataset(snapshot)
        let photoIDs = Set(snapshot.meals.flatMap(\.photoIDs) + snapshot.drafts.flatMap { $0.content.photoIDs })
        let dates = Set(snapshot.meals.map { $0.time.localDay } + snapshot.workouts.map { $0.time.localDay } + snapshot.confirmations.map(\.day))
        records = PackageRecords(meals: snapshot.meals.filter { $0.deletedAt == nil }, workouts: snapshot.workouts.filter { $0.deletedAt == nil },
                                 photos: snapshot.photos.filter { photoIDs.contains($0.id) }, confirmations: snapshot.confirmations,
                                 daySummaries: dates.sorted().map { ReviewRules.day($0, in: snapshot) }, origins: snapshot.importOrigins)
        profiles = snapshot.profiles; goals = snapshot.goals; estimates = snapshot.estimates
        drafts = snapshot.drafts.map(PackageDraft.init)
        trash = PackageTrash(meals: snapshot.meals.filter { $0.deletedAt != nil }, workouts: snapshot.workouts.filter { $0.deletedAt != nil }, tombstones: snapshot.tombstones)
    }
    public func snapshot(manifest: PackageManifest) throws -> DatasetSnapshot {
        var value = DatasetSnapshot(dataset: Dataset(id: manifest.datasetID))
        value.dataset.revision = manifest.revision
        value.meals = (records.meals + trash.meals).sorted { $0.id.uuidString < $1.id.uuidString }
        value.workouts = (records.workouts + trash.workouts).sorted { $0.id.uuidString < $1.id.uuidString }
        value.photos = records.photos; value.profiles = profiles; value.goals = goals; value.estimates = estimates
        value.drafts = try drafts.map { try $0.domain() }; value.confirmations = records.confirmations; value.tombstones = trash.tombstones
        value.importOrigins = records.origins ?? []
        return value
    }
    public var counts: [String: Int] { ["meals":records.meals.count,"workouts":records.workouts.count,"photos":records.photos.count,"profiles":profiles.count,"goals":goals.count,"estimates":estimates.count,"drafts":drafts.count,"trash_meals":trash.meals.count,"trash_workouts":trash.workouts.count,"tombstones":trash.tombstones.count,"confirmations":records.confirmations.count] }
    public func dataFiles() throws -> [String: Data] {
        ["records.json":try PackageCodec.encode(records),"profiles.json":try PackageCodec.encode(profiles),"goals.json":try PackageCodec.encode(goals),"estimates.json":try PackageCodec.encode(estimates),"drafts.json":try PackageCodec.encode(drafts),"trash.json":try PackageCodec.encode(trash),"README.md":Data(PackageReadingGuide.readme.utf8),"agent-prompt.txt":Data(PackageReadingGuide.agentPrompt.utf8)]
    }
}
public enum PackageCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]; encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970; return try decoder.decode(type, from: data)
    }
}
