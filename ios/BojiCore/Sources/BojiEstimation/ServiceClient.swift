import Foundation
import Security
import BojiDomain

public struct ServiceFailure: Error, Equatable, Sendable {
    public var code: String
    public var retryAfter: TimeInterval?
    public init(_ code: String, retryAfter: TimeInterval? = nil) { self.code = code; self.retryAfter = retryAfter }
}
public protocol ServiceCredentials: Sendable {
    func token(for url: URL) async throws -> String?
    func setToken(_ token: String?, for url: URL) async throws
}
public actor KeychainCredentials: ServiceCredentials {
    public init() {}
    private func query(_ url: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.boji.personal.food-estimation", kSecAttrAccount as String: url.absoluteString, kSecAttrSynchronizable as String: false]
    }
    public func token(for url: URL) throws -> String? {
        var values = query(url); values[kSecReturnData as String] = true; values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(values as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw ServiceFailure("credentials_unavailable") }
        return value
    }
    public func setToken(_ token: String?, for url: URL) throws {
        let query = query(url)
        guard let token else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ServiceFailure("credentials_unavailable") }; return
        }
        let minimumLength = QwenDirectClient.supports(url) ? 16 : 43
        guard token.utf8.count >= minimumLength, token.utf8.count <= 1017, !token.contains(where: \.isWhitespace) else { throw ServiceFailure("invalid_token") }
        let updates: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(updates, uniquingKeysWith: { _,new in new }) as CFDictionary, nil) }
        guard status == errSecSuccess else { throw ServiceFailure("credentials_unavailable") }
    }
}
public struct ServiceHTTPResponse: Sendable {
    public var status: Int
    public var data: Data
    public var retryAfter: TimeInterval?
    public init(status: Int, data: Data, retryAfter: TimeInterval? = nil) { self.status = status; self.data = data; self.retryAfter = retryAfter }
}
public protocol ServiceHTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> ServiceHTTPResponse }
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
public final class URLSessionServiceTransport: ServiceHTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init(requestTimeout: TimeInterval = 30, resourceTimeout: TimeInterval = 45) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = requestTimeout; config.timeoutIntervalForResource = resourceTimeout
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ServiceFailure("invalid_response") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1024 * 1024 else { throw ServiceFailure("invalid_response") }
            data.append(byte)
        }
        return ServiceHTTPResponse(status: response.statusCode, data: data, retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
    }
}
public struct RemoteEstimate: Decodable, Sendable {
    public var jobID: String
    public var recordID: UUID
    public var inputRevision: Int64
    public var lifecycleEpoch: Int64
    public var status: String
    public var errorCode: String?
    public var result: RemoteFoodResult?
    enum CodingKeys: String, CodingKey { case jobID = "job_id", recordID = "record_id", inputRevision = "input_revision", lifecycleEpoch = "lifecycle_epoch", status, errorCode = "error_code", result }
}
public struct RemoteFoodResult: Decodable, Sendable {
    public struct Item: Decodable, Sendable {
        var name: String; var grams: Decimal?; var kcal: Decimal; var assumptions: [String]
        enum CodingKeys: String, CodingKey { case name, grams = "estimated_grams", kcal, assumptions }
    }
    var items: [Item]; var total: Decimal; var range: EstimateRange?; var questions: [String]
    var source: String; var provider: String; var model: String; var prompt: String; var created: String
    enum CodingKeys: String, CodingKey { case items, total = "total_kcal", range = "estimate_range", questions, source, provider, model, prompt = "prompt_version", created = "created_at" }
    public func revision(for job: EstimateJob) throws -> EstimateRevision {
        guard source == "model_estimate", !provider.isEmpty, !model.isEmpty, let date = ServiceDates.parse(created) else { throw ServiceFailure("invalid_model_output") }
        let foods = items.map { item in var food = FoodItem(name: item.name, grams: item.grams, kcal: item.kcal); food.assumptions = item.assumptions; return food }
        var revision = EstimateRevision(id: job.id, recordID: job.recordID, inputRevision: job.inputRevision, source: .model, items: foods, totalKcal: total, createdAt: date)
        revision.range = range; revision.questions = questions; revision.provider = provider; revision.model = model; revision.promptVersion = prompt
        try FoodEstimateRules.validate(revision); return revision
    }
}
enum ServiceDates {
    static func format(_ date: Date) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.string(from: date) }
    static func parse(_ value: String) -> Date? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
}
public protocol EstimationRemote: Sendable {
    func policy(url: URL) async throws -> AIServicePolicy
    func upload(data: Data, job: EstimateJob) async throws -> String
    func submit(_ job: EstimateJob) async throws -> RemoteEstimate
    func poll(_ job: EstimateJob) async throws -> RemoteEstimate
    func cancel(_ job: EstimateJob) async throws
}
public protocol DirectEstimationRemote: EstimationRemote {
    func supportsDirect(_ url: URL) -> Bool
    func estimateDirect(_ job: EstimateJob, images: [Data]) async throws -> RemoteEstimate
}
public struct ServiceClient: EstimationRemote {
    public let transport: any ServiceHTTPTransport
    public let credentials: any ServiceCredentials
    public init(transport: any ServiceHTTPTransport = URLSessionServiceTransport(), credentials: any ServiceCredentials) { self.transport = transport; self.credentials = credentials }
    public static func validateURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw ServiceFailure("https_required") }
    }
    private func call(url: URL, path: String, method: String = "GET", body: Data? = nil, mime: String = "application/json", policy: String? = nil) async throws -> Data {
        try Self.validateURL(url)
        guard let token = try await credentials.token(for: url) else { throw ServiceFailure("unauthorized") }
        var request = URLRequest(url: url.appendingPathComponent(path)); request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        if let policy { request.setValue(policy, forHTTPHeaderField: "X-Boji-Policy-Version") }
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            struct Failure: Decodable { struct Detail: Decodable { var code: String }; var error: Detail }
            let code = (try? JSONDecoder().decode(Failure.self, from: response.data).error.code) ?? "invalid_response"
            throw ServiceFailure(code, retryAfter: response.retryAfter)
        }
        return response.data
    }
    public func policy(url: URL) async throws -> AIServicePolicy {
        struct Policy: Decodable {
            struct Limits: Decodable { var attempts_per_utc_day: Int }
            var available: Bool; var policy_version: String; var provider: String?; var model: String?; var sent_data: [String]; var provider_retention: String
            var server_raw_retention_hours: Int; var metadata_retention_days: Int; var fee_payer: String; var limits: Limits
        }
        let p = try JSONDecoder().decode(Policy.self, from: await call(url: url, path: "v1/config"))
        guard !p.policy_version.isEmpty, p.policy_version.count <= 200, p.server_raw_retention_hours >= 0, p.metadata_retention_days >= 0,
              p.limits.attempts_per_utc_day > 0, !p.available || (p.provider?.isEmpty == false && p.model?.isEmpty == false) else { throw ServiceFailure("invalid_response") }
        return AIServicePolicy(available: p.available, version: p.policy_version, provider: p.provider, model: p.model, sentData: p.sent_data, providerRetention: p.provider_retention, rawRetentionHours: p.server_raw_retention_hours, metadataRetentionDays: p.metadata_retention_days, feePayer: p.fee_payer, dailyAttempts: p.limits.attempts_per_utc_day)
    }
    public func upload(data: Data, job: EstimateJob) async throws -> String {
        guard let url = job.serviceURL, data.count <= 2 * 1024 * 1024 else { throw ServiceFailure("invalid_input") }
        struct Upload: Decodable { var image_ref: String }
        let result = try JSONDecoder().decode(Upload.self, from: await call(url: url, path: "v1/uploads", method: "POST", body: data, mime: "image/jpeg", policy: job.policyVersion))
        guard UUID(uuidString: result.image_ref) != nil else { throw ServiceFailure("invalid_response") }; return result.image_ref
    }
    public func submit(_ job: EstimateJob) async throws -> RemoteEstimate {
        guard let url = job.serviceURL, let firstSend = job.requestCreatedAt, let refs = job.uploadedReferences, refs.count == job.photoIDs.count else { throw ServiceFailure("invalid_input") }
        struct Body: Encodable {
            var request_id: String; var request_created_at: String; var record_id: String; var input_revision: Int64; var lifecycle_epoch: Int64
            var image_refs: [String]; var note: String; var locale = "zh-Hans"; var policy_version: String; var retry_of: String?
        }
        let data = try JSONEncoder().encode(Body(request_id: job.id.uuidString, request_created_at: ServiceDates.format(firstSend), record_id: job.recordID.uuidString, input_revision: job.inputRevision, lifecycle_epoch: job.lifecycleEpoch, image_refs: refs, note: job.note, policy_version: job.policyVersion, retry_of: job.retryOf))
        return try decode(await call(url: url, path: "v1/food-estimates", method: "POST", body: data), for: job)
    }
    public func poll(_ job: EstimateJob) async throws -> RemoteEstimate {
        guard let url = job.serviceURL, let id = job.remoteJobID, UUID(uuidString: id) != nil else { throw ServiceFailure("invalid_input") }
        return try decode(await call(url: url, path: "v1/food-estimates/" + id), for: job)
    }
    public func cancel(_ job: EstimateJob) async throws {
        guard let url = job.serviceURL, let id = job.remoteJobID, UUID(uuidString: id) != nil else { return }
        _ = try await call(url: url, path: "v1/food-estimates/" + id, method: "DELETE")
    }
    private func decode(_ data: Data, for job: EstimateJob) throws -> RemoteEstimate {
        let value = try JSONDecoder().decode(RemoteEstimate.self, from: data)
        guard UUID(uuidString: value.jobID) != nil, value.recordID == job.recordID, value.inputRevision == job.inputRevision, value.lifecycleEpoch == job.lifecycleEpoch,
              job.remoteJobID == nil || job.remoteJobID == value.jobID else { throw ServiceFailure("invalid_response") }
        return value
    }
}
