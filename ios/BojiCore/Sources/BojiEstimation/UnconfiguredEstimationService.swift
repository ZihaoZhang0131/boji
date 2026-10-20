import BojiDomain

/// No request and no estimate are possible before a real service is configured.
public struct UnconfiguredEstimationService: FoodEstimationService {
    public init() {}
    public func configuration() async throws -> EstimationConfiguration { throw DomainError.notConfigured }
}

public struct DemoDisabledEstimationService: FoodEstimationService {
    public init() {}
    public func configuration() async throws -> EstimationConfiguration { throw DomainError.demoOperationDisabled }
}
