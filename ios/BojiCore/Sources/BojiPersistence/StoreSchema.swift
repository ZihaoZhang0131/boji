import Foundation
import SwiftData

enum StoreSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Entity.self, Metadata.self, Receipt.self] }

    /// One row per domain entity. Ordered collections are encoded within their owning row;
    /// their order must not depend on SwiftData's unordered to-many relationships.
    @Model final class Entity {
        @Attribute(.unique) var key: String
        var kind: String
        var payload: Data
        init(key: String, kind: String, payload: Data) { self.key = key; self.kind = kind; self.payload = payload }
    }

    @Model final class Metadata {
        @Attribute(.unique) var key: String
        var payload: Data
        var aiSettings: Data
        var backup: Data
        init(payload: Data, aiSettings: Data, backup: Data) {
            key = "primary"; self.payload = payload; self.aiSettings = aiSettings; self.backup = backup
        }
    }

    @Model final class Receipt {
        @Attribute(.unique) var id: UUID
        var revision: Int64
        init(id: UUID, revision: Int64) { self.id = id; self.revision = revision }
    }
}

enum StoreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [StoreSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
