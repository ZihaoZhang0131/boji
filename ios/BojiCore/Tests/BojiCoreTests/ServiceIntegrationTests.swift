#if os(macOS)
import Foundation
import Security
import Testing
import BojiDomain
import BojiPersistence
import BojiEstimation

/// Only trusts this run's temporary CA; TLS hostname and trust evaluation remain enabled.
private final class FixtureTLS: NSObject, URLSessionDelegate, @unchecked Sendable {
    let certificate: SecCertificate
    init(certificate: SecCertificate) { self.certificate = certificate }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { completionHandler(.performDefaultHandling, nil); return }
        SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var trustError: CFError?
        if SecTrustEvaluateWithError(trust, &trustError) { completionHandler(.useCredential, URLCredential(trust: trust)) }
        else { print("Fixture TLS validation:", String(describing: trustError)); completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}
private final class FixtureTLSHTTP: ServiceHTTPTransport, @unchecked Sendable {
    let session: URLSession
    init(certificate: SecCertificate) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        session = URLSession(configuration: configuration, delegate: FixtureTLS(certificate: certificate), delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        let (data, response) = try await session.data(for: request)
        return ServiceHTTPResponse(status: (response as! HTTPURLResponse).statusCode, data: data)
    }
}
private actor IntegrationCredentials: ServiceCredentials {
    let value: String
    init(_ value: String) { self.value = value }
    func token(for url: URL) -> String? { value }
    func setToken(_ token: String?, for url: URL) {}
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["BOJI_RUN_SERVICE_INTEGRATION"] == "1"))
func realSwiftClientUsesHTTPSServiceAndRetainsIdempotencyAfterLostResponse() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    var repo = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { repo.deleteLastPathComponent() }
    let script = repo.appendingPathComponent("services/food-estimation/dist/test/swift-fixture.js")
    #expect(FileManager.default.fileExists(atPath: script.path))
    let token = UUID().uuidString + UUID().uuidString
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/local/bin/node"); process.arguments = [script.path]
    process.environment = ProcessInfo.processInfo.environment.merging(["BOJI_FIXTURE_DIR":root.path,"BOJI_FIXTURE_TOKEN":token], uniquingKeysWith: { _,new in new })
    let log = root.appendingPathComponent("process.log"); FileManager.default.createFile(atPath: log.path, contents: nil)
    let handle = try FileHandle(forWritingTo: log); process.standardOutput = handle; process.standardError = handle
    try process.run()
    defer { if process.isRunning { process.terminate(); process.waitUntilExit() }; try? handle.close() }
    let ready = root.appendingPathComponent("ready.json")
    for _ in 0..<200 { if FileManager.default.fileExists(atPath: ready.path) { break }; try await Task.sleep(for: .milliseconds(25)) }
    struct Ready: Decodable { var url: URL }
    let url = try JSONDecoder().decode(Ready.self, from: Data(contentsOf: ready)).url
    let cert = try #require(SecCertificateCreateWithData(nil, Data(contentsOf: root.appendingPathComponent("cert.der")) as CFData))
    let client = ServiceClient(transport: FixtureTLSHTTP(certificate: cert), credentials: IntegrationCredentials(token))
    let policy = try await client.policy(url: url)
    #expect(policy.provider == "swift-local-fixture" && policy.model == "protocol-only")
    let store = try await LocalRepository.open(at: root.appendingPathComponent("client"))
    try await store.configureEstimation(url: url, policy: policy)
    let photo = try await store.preparePhoto(imageFixture())
    var meal = Meal(time: RecordTime(clock: SystemClock())); meal.photoIDs = [photo.id]; meal.note = "synthetic Swift fixture"
    try await store.saveMeal(meal, draftID: nil, photos: [photo], operationID: UUID())
    // Actual endpoint remains uncontacted for uploads until explicit consent.
    await #expect(throws: DomainError.self) { try await store.enqueueEstimate(recordID: meal.id, automatic: false, at: Date()) }
    await EstimateQueue(repository: store, remote: client, clock: SystemClock()).runOnce(networkAvailable: true)
    struct Counts: Decodable { var calls: Int; var uploads: Int }
    func counts() throws -> Counts { try JSONDecoder().decode(Counts.self, from: Data(contentsOf: root.appendingPathComponent("counts.json"))) }
    #expect(try counts().uploads == 0)
    try await store.acceptEstimationPolicy(policy.version)
    let id = try await store.enqueueEstimate(recordID: meal.id, automatic: false, at: Date())
    let prepared = try #require(await store.prepareEstimateSend(id: id, at: Date()))
    var job = prepared; job.uploadedReferences = [try await client.upload(data: UploadImage.jpeg(imageFixture()), job: job)]
    try await store.updateEstimateJob(job)
    // The HTTPS proxy accepts the first submit then drops the response.
    do { _ = try await client.submit(job); Issue.record("Expected intentionally lost response") } catch is URLError {}
    let submitted = try await client.submit(job); job.remoteJobID = submitted.jobID
    try await store.updateEstimateJob(job)
    let reopened = try await LocalRepository.open(at: root.appendingPathComponent("client"))
    var response = try await client.poll(job)
    for _ in 0..<100 {
        if response.status == "succeeded" { break }
        try await Task.sleep(for: .milliseconds(20)); response = try await client.poll(job)
    }
    #expect(response.status == "succeeded")
    #expect(try await reopened.applyEstimate(jobID: id, revision: #require(response.result).revision(for: job)))
    #expect(try await reopened.snapshot().estimates.first?.totalKcal == 123)
    #expect(try counts().calls == 1 && counts().uploads == 1)
    #expect(try await client.submit(job).jobID == submitted.jobID)
    try await client.cancel(job)
    #expect(try await client.poll(job).status == "cancelled")
    let output = try String(contentsOf: log, encoding: .utf8)
    #expect(!output.contains(token) && !output.contains(meal.note))
}
#endif
