import Foundation
import Testing
import BojiDomain
import BojiPersistence
import BojiEstimation

private let serviceURL = URL(string: "https://fixture.invalid")!
private func fixturePolicy(_ version: String = "fixture-v1") -> AIServicePolicy {
    AIServicePolicy(available: true, version: version, provider: "fixture-only", model: "fixture-model", sentData: ["照片", "备注"], providerRetention: "仅协议测试", rawRetentionHours: 24, metadataRetentionDays: 7, feePayer: "fixture", dailyAttempts: 50)
}
private actor FixtureCredentials: ServiceCredentials {
    var value: String? = String(repeating: "fixture", count: 8)
    func token(for url: URL) -> String? { value }
    func setToken(_ token: String?, for url: URL) { value = token }
}
private actor FixtureHTTP: ServiceHTTPTransport {
    var requests: [URLRequest] = []
    var jobs: [String: Data] = [:]
    var providerCalls = 0
    var loseSubmissionResponse = false
    var version = "fixture-v1"
    func loseNextResponse() { loseSubmissionResponse = true }
    func changePolicy() { version = "fixture-v2" }
    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        requests.append(request)
        let path = request.url!.path
        var body: [String: Any]
        if path == "/v1/config" {
            body = ["available":true,"policy_version":version,"provider":"fixture-only","model":"fixture-model","sent_data":["照片","备注"],"provider_retention":"仅协议测试","server_raw_retention_hours":24,"metadata_retention_days":7,"fee_payer":"fixture","limits":["attempts_per_utc_day":50]]
        } else if path == "/v1/uploads" {
            body = ["image_ref":UUID().uuidString]
        } else if path == "/v1/food-estimates" {
            let input = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let id = input["request_id"] as! String
            if jobs[id] == nil {
                providerCalls += 1
                let result: [String: Any] = ["items":[["name":"fixture meal","estimated_grams":NSNull(),"kcal":500,"assumptions":["fixture only"]]],"total_kcal":500,"estimate_range":NSNull(),"questions":[],"source":"model_estimate","provider":"fixture-only","model":"fixture-model","prompt_version":"food-v1","created_at":"2026-10-20T12:00:00.000Z"]
                body = ["job_id":UUID().uuidString,"record_id":input["record_id"]!,"input_revision":input["input_revision"]!,"lifecycle_epoch":input["lifecycle_epoch"]!,"status":"succeeded","result":result]
                jobs[id] = try JSONSerialization.data(withJSONObject: body)
            }
            if loseSubmissionResponse { loseSubmissionResponse = false; throw URLError(.networkConnectionLost) }
            return ServiceHTTPResponse(status: 202, data: jobs[id]!)
        } else if request.httpMethod == "DELETE" { body = ["status":"cancelled"] }
        else { throw ServiceFailure("not_found") }
        return ServiceHTTPResponse(status: 200, data: try JSONSerialization.data(withJSONObject: body))
    }
    func uploadCount() -> Int { requests.filter { $0.url?.path == "/v1/uploads" }.count }
    func submissionBodies() -> [Data] { requests.filter { $0.url?.path == "/v1/food-estimates" }.compactMap(\.httpBody) }
}

private func configuredStore(_ root: URL) async throws -> LocalRepository {
    let repository = try await LocalRepository.open(at: root)
    try await repository.configureEstimation(url: serviceURL, policy: fixturePolicy())
    try await repository.acceptEstimationPolicy("fixture-v1")
    return repository
}
private func modelRevision(_ job: EstimateJob) -> EstimateRevision {
    var revision = EstimateRevision(id: job.id, recordID: job.recordID, inputRevision: job.inputRevision, source: .model, items: [FoodItem(name: "fixture", grams: nil, kcal: 500)], totalKcal: 500, createdAt: Date(timeIntervalSince1970: 0))
    revision.provider = "fixture-only"; revision.model = "fixture-model"; return revision
}

@Test func offlineFirstSendAndLostResponseKeepInputAndRequestIdentityAcrossRestart() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await configuredStore(root), queuedClock = FixedClock("2026-10-17T12:00:00Z")
    let photo = try await store.preparePhoto(imageFixture())
    var meal = Meal(time: RecordTime(clock: queuedClock)); meal.note = "fixture"; meal.photoIDs = [photo.id]
    try await store.saveMeal(meal, draftID: nil, photos: [photo], operationID: UUID())
    let id = try await store.enqueueEstimate(recordID: meal.id, automatic: false, at: queuedClock.now)
    #expect(try await store.enqueueEstimate(recordID: meal.id, automatic: false, at: queuedClock.now) == id)
    let http = FixtureHTTP(), client = ServiceClient(transport: http, credentials: FixtureCredentials())
    await EstimateQueue(repository: store, remote: client, clock: queuedClock).runOnce(networkAvailable: false)
    #expect(try await store.snapshot().jobs[0].requestCreatedAt == nil)
    #expect(await http.uploadCount() == 0)
    let firstClock = FixedClock("2026-10-20T12:00:00Z")
    await http.loseNextResponse()
    await EstimateQueue(repository: store, remote: client, clock: firstClock).runOnce(networkAvailable: true)
    let pending = try #require(await store.snapshot().jobs.first { $0.id == id })
    #expect(pending.requestCreatedAt == firstClock.now && pending.remoteJobID == nil && pending.uploadedReferences?.count == 1)
    let reopened = try await LocalRepository.open(at: root)
    await EstimateQueue(repository: reopened, remote: client, clock: FixedClock("2026-10-20T12:00:05Z")).runOnce(networkAvailable: true)
    let state = try await reopened.snapshot()
    #expect(state.jobs[0].status == .succeeded && state.estimates.count == 1 && state.estimates[0].source == .model)
    #expect(await http.providerCalls == 1)
    #expect(await http.uploadCount() == 1)
    let bodies = await http.submissionBodies()
    let first = try JSONSerialization.jsonObject(with: bodies[0]) as! NSDictionary
    let second = try JSONSerialization.jsonObject(with: bodies[1]) as! NSDictionary
    #expect(first == second)
}

@Test func noConsentDemoAndChangedPolicyNeverUploadPhotos() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await configuredStore(root), clock = FixedClock("2026-10-17T12:00:00Z")
    let photo = try await store.preparePhoto(imageFixture())
    var meal = Meal(time: RecordTime(clock: clock)); meal.photoIDs = [photo.id]
    try await store.saveMeal(meal, draftID: nil, photos: [photo], operationID: UUID())
    try await store.setAutomaticEstimation(true); try await store.revokeEstimationConsent()
    await #expect(throws: DomainError.self) { try await store.enqueueEstimate(recordID: meal.id, automatic: true, at: clock.now) }
    let http = FixtureHTTP(), client = ServiceClient(transport: http, credentials: FixtureCredentials())
    await EstimateQueue(repository: store, remote: client, clock: clock).runOnce(networkAvailable: true)
    #expect(await http.requests.isEmpty)
    try await store.acceptEstimationPolicy("fixture-v1")
    try await store.enqueueEstimate(recordID: meal.id, automatic: true, at: clock.now)
    await http.changePolicy()
    await EstimateQueue(repository: store, remote: client, clock: clock).runOnce(networkAvailable: true)
    #expect(await http.uploadCount() == 0)
    #expect(try await store.snapshot().aiSettings.acceptedPolicy == nil)
    let session = WorkspaceSession(personal: store, clock: clock); try await session.enterDemo()
    let count = await http.requests.count
    await EstimateQueue(repository: session.activeRepository(), remote: client, clock: clock).runOnce(networkAvailable: true)
    #expect(await http.requests.count == count)
}

@Test func turningAutomaticOffCancelsOnlyUnsentAutomaticWork() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await configuredStore(root), clock = FixedClock("2026-10-17T12:00:00Z")
    let photo = try await store.preparePhoto(imageFixture())
    var first = Meal(time: RecordTime(clock: clock)); first.photoIDs = [photo.id]
    var second = Meal(time: first.time); second.note = "manual fixture"
    try await store.saveMeal(first, draftID: nil, photos: [photo], operationID: UUID()); try await store.saveMeal(second, draftID: nil, operationID: UUID())
    try await store.setAutomaticEstimation(true)
    let automatic = try await store.enqueueEstimate(recordID: first.id, automatic: true, at: clock.now)
    let manual = try await store.enqueueEstimate(recordID: second.id, automatic: false, at: clock.now)
    try await store.setAutomaticEstimation(false)
    let state = try await store.snapshot()
    #expect(state.jobs.first { $0.id == automatic }?.status == .cancelled)
    #expect(state.jobs.first { $0.id == manual }?.status == .pendingNetwork && state.aiSettings.acceptedPolicy != nil)
    try await store.revokeEstimationConsent()
    #expect(try await store.snapshot().jobs.allSatisfy { $0.status == .cancelled })
}

@Test(arguments: ["input", "deleteRestore", "consent", "manual", "dataset", "policy", "discard"])
func lateModelResultsNeverOverwriteNewerFacts(race: String) async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await configuredStore(root), clock = FixedClock("2026-10-17T12:00:00Z")
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "fixture"
    let draft = RecordDraft(content: .meal(meal), savedAt: clock.now)
    if race == "discard" { try await store.saveDraft(draft, operationID: UUID()) }
    else { try await store.saveMeal(meal, draftID: nil, operationID: UUID()) }
    let id = try await store.enqueueEstimate(recordID: meal.id, draftID: race == "discard" ? draft.id : nil, automatic: false, at: clock.now)
    let job = try #require(await store.prepareEstimateSend(id: id, at: clock.now))
    switch race {
    case "input": meal.note += " changed"; try await store.saveMeal(meal, draftID: nil, operationID: UUID())
    case "deleteRestore": try await store.moveToTrash(kind: .meal, id: meal.id, at: clock.now, operationID: UUID()); try await store.restore(kind: .meal, id: meal.id, at: clock.now, operationID: UUID())
    case "consent": try await store.revokeEstimationConsent()
    case "manual": try await store.saveManualEstimate(recordID: meal.id, expectedInputRevision: 0, items: [FoodItem(name: "manual", grams: nil, kcal: 600)], at: clock.now, operationID: UUID(), estimateID: UUID())
    case "dataset": try await store.commit(id: UUID()) { $0.jobs[0].datasetID = UUID() }
    case "policy": try await store.configureEstimation(url: serviceURL, policy: fixturePolicy("fixture-v2"))
    case "discard": try await store.discardDraft(id: draft.id, at: clock.now, operationID: UUID())
    default: break
    }
    #expect(try await store.applyEstimate(jobID: id, revision: modelRevision(job)) == false)
    let state = try await store.snapshot()
    #expect(state.estimates.allSatisfy { $0.source != .model })
    if race == "manual" { #expect(state.estimates.first?.totalKcal == 600 && state.meals.first?.currentEstimateID == state.estimates.first?.id) }
}

@Test(arguments: [true, false])
func draftEstimateKeepsIdentityWhenSavedBeforeOrAfterResult(saveFirst: Bool) async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await configuredStore(root), clock = FixedClock("2026-10-17T12:00:00Z")
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "draft fixture"
    var draft = RecordDraft(content: .meal(meal), savedAt: clock.now)
    try await store.saveDraft(draft, operationID: UUID())
    let id = try await store.enqueueEstimate(recordID: meal.id, draftID: draft.id, automatic: false, at: clock.now)
    let job = try #require(await store.prepareEstimateSend(id: id, at: clock.now))
    if saveFirst { try await store.saveMeal(meal, draftID: draft.id, operationID: UUID()) }
    #expect(try await store.applyEstimate(jobID: id, revision: modelRevision(job)))
    if !saveFirst {
        draft.revision += 1; try await store.saveDraft(draft, operationID: UUID())
        let refreshed = try #require(await store.snapshot().drafts.first { $0.id == draft.id })
        guard case .meal(let current) = refreshed.content else { Issue.record("Wrong draft kind"); return }
        #expect(current.currentEstimateID == id)
        try await store.saveMeal(current, draftID: draft.id, operationID: UUID())
    }
    let state = try await store.snapshot()
    #expect(state.meals.count == 1 && state.meals[0].id == meal.id && state.meals[0].currentEstimateID == id)
}

@Test func editingDraftCannotOverwriteAnInterveningFormalManualCorrection() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await configuredStore(root), clock = FixedClock("2026-10-17T12:00:00Z")
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "fixture"
    try await store.saveMeal(meal, draftID: nil, operationID: UUID())
    let draft = RecordDraft(editingRecordID: meal.id, content: .meal(meal), savedAt: clock.now)
    try await store.saveDraft(draft, operationID: UUID())
    let id = try await store.enqueueEstimate(recordID: meal.id, draftID: draft.id, automatic: false, at: clock.now)
    let job = try #require(await store.prepareEstimateSend(id: id, at: clock.now))
    try await store.saveManualEstimate(recordID: meal.id, expectedInputRevision: 0, items: [FoodItem(name: "manual", grams: nil, kcal: 600)], at: clock.now, operationID: UUID(), estimateID: UUID())
    #expect(try await store.applyEstimate(jobID: id, revision: modelRevision(job)) == false)
    try await store.saveMeal(meal, draftID: draft.id, operationID: UUID())
    let state = try await store.snapshot()
    #expect(state.meals[0].currentEstimateID == state.estimates[0].id && state.estimates[0].totalKcal == 600)
}

private actor QueueFixture: EstimationRemote {
    var submissions = 0, polls = 0, cancellations = 0
    let failure: String?
    let remoteID = UUID().uuidString
    init(failure: String? = nil) { self.failure = failure }
    func policy(url: URL) -> AIServicePolicy { fixturePolicy() }
    func upload(data: Data, job: EstimateJob) -> String { UUID().uuidString }
    func submit(_ job: EstimateJob) throws -> RemoteEstimate {
        submissions += 1
        if let failure { if failure == "network" { throw URLError(.notConnectedToInternet) }; throw ServiceFailure(failure, retryAfter: 30) }
        return try response(job, status: "queued")
    }
    func poll(_ job: EstimateJob) throws -> RemoteEstimate { polls += 1; return try response(job, status: "running") }
    func cancel(_ job: EstimateJob) { cancellations += 1 }
    private func response(_ job: EstimateJob, status: String) throws -> RemoteEstimate {
        let value: [String: Any] = ["job_id": remoteID, "record_id":job.recordID.uuidString,"input_revision":job.inputRevision,"lifecycle_epoch":job.lifecycleEpoch,"status":status]
        return try JSONDecoder().decode(RemoteEstimate.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
@Test func onlyLatestOfflineInputSendsAndRestartPollsWithoutResubmitting() async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await configuredStore(root), clock = FixedClock("2026-10-17T12:00:00Z")
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "first"
    try await store.saveMeal(meal, draftID: nil, operationID: UUID())
    try await store.enqueueEstimate(recordID: meal.id, automatic: false, at: clock.now)
    for note in ["second", "third"] {
        meal = try #require(await store.snapshot().activeMeals.first); meal.note = note
        try await store.saveMeal(meal, draftID: nil, operationID: UUID())
        try await store.enqueueEstimate(recordID: meal.id, automatic: false, at: clock.now)
    }
    let remote = QueueFixture()
    await EstimateQueue(repository: store, remote: remote, clock: clock).runOnce(networkAvailable: true)
    #expect(await remote.submissions == 1)
    #expect(try await store.snapshot().jobs.filter { $0.status == .cancelled }.count == 2)
    let reopened = try await LocalRepository.open(at: root)
    await EstimateQueue(repository: reopened, remote: remote, clock: FixedClock("2026-10-17T12:00:05Z")).runOnce(networkAvailable: true)
    #expect(await remote.polls == 1)
    #expect(await remote.submissions == 1)
    let active = try #require(await reopened.snapshot().jobs.first { !$0.status.isTerminal })
    #expect(active.note == "third" && active.status == .running)
    try await reopened.cancelEstimate(id: active.id)
    await EstimateQueue(repository: reopened, remote: remote, clock: clock).runOnce(networkAvailable: true)
    #expect(await remote.cancellations == 1)
    #expect(try await reopened.snapshot().jobs.first { $0.id == active.id }?.remoteCancellationPending == false)
}
@Test(arguments: ["network", "rate_limited", "quota_exceeded", "provider_timeout"])
func retriesAreBoundedAndPermanentFailuresStayVisible(code: String) async throws {
    let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await configuredStore(root), clock = FixedClock("2026-10-17T12:00:00Z")
    var meal = Meal(time: RecordTime(clock: clock)); meal.note = "fixture"
    try await store.saveMeal(meal, draftID: nil, operationID: UUID())
    try await store.enqueueEstimate(recordID: meal.id, automatic: false, at: clock.now)
    let remote = QueueFixture(failure: code)
    for offset in 0..<8 {
        var next = clock; next.now = clock.now.addingTimeInterval(Double(offset) * 120)
        await EstimateQueue(repository: store, remote: remote, clock: next).runOnce(networkAvailable: true)
    }
    let state = try await store.snapshot(), job = try #require(state.jobs.first)
    #expect(job.status == .failed && state.estimates.isEmpty && state.activeMeals.count == 1)
    #expect(job.errorCode == (code == "network" ? "network_unavailable" : code))
    #expect(await remote.submissions == (code == "network" || code == "rate_limited" ? 7 : 1))
}
