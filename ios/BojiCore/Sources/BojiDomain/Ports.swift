import Foundation

public enum DomainError: Error, Equatable, Sendable {
    case invalidDate
    case invalidValue(String)
    case notConfigured
    case demoOperationDisabled
    case conflict
    case corruptStore
    case unsupportedSchema(Int)
    case missingPhoto(UUID)
}

public protocol RecordRepository: Sendable {
    associatedtype Snapshot: Sendable
    func snapshot() async throws -> Snapshot
}

public protocol FileAccess: Sendable {
    func read(_ url: URL) throws -> Data
    func writeAtomically(_ data: Data, to url: URL) throws
}

public struct EstimationConfiguration: Codable, Equatable, Sendable {
    public let provider: String
    public let model: String
    public let policyVersion: String
    public init(provider: String, model: String, policyVersion: String) {
        self.provider = provider; self.model = model; self.policyVersion = policyVersion
    }
}

public protocol FoodEstimationService: Sendable {
    func configuration() async throws -> EstimationConfiguration
}

public protocol DataPackageExporter: Sendable {
    associatedtype Snapshot: Sendable
    func export(_ snapshot: Snapshot, to destination: URL) async throws -> URL
}
