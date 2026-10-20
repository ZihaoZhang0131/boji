import BojiDomain

public enum PackageVersion {
    /// Public exchange format, independent of the internal database schema.
    public static let current = 2
}

public enum ExportPolicy {
    public static func requirePersonalDataset(_ snapshot: DatasetSnapshot) throws {
        guard snapshot.dataset.mode == .personal else { throw DomainError.demoOperationDisabled }
    }
}
