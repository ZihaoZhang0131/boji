import Foundation
import BojiDomain
import BojiPersistence

/// One foreground worker. All network boundaries re-check persisted eligibility.
public actor EstimateQueue {
    private let repository: LocalRepository
    private let remote: any EstimationRemote
    private let clock: any AppClock
    private var running = false
    private var suspended = false
    public private(set) var storageFailed = false
    public init(repository: LocalRepository, remote: any EstimationRemote, clock: any AppClock) { self.repository = repository; self.remote = remote; self.clock = clock }

    public func runOnce(networkAvailable: Bool) async {
        guard !running, !suspended, networkAvailable else { return }
        storageFailed = false
        running = true; defer { running = false }
        do {
            guard try await repository.snapshot().dataset.mode == .personal else { return }
            try await repository.invalidateEstimateJobs()
            var state = try await repository.snapshot()
            for job in state.jobs where job.remoteCancellationPending == true {
                guard !suspended, !Task.isCancelled else { return }
                do { try await remote.cancel(job); try await repository.acknowledgedRemoteCancellation(id: job.id) }
                catch { /* Already-sent data cannot be recalled with certainty. Keep a bounded retry window. */
                    if clock.now.timeIntervalSince(job.requestCreatedAt ?? job.queuedAt) >= 7 * 24 * 60 * 60 { try await repository.acknowledgedRemoteCancellation(id: job.id) }
                }
            }
            state = try await repository.snapshot()
            if let direct = remote as? any DirectEstimationRemote {
                for old in state.jobs where old.status == .running && old.requestCreatedAt != nil && old.serviceURL.map({ direct.supportsDirect($0) }) == true {
                    var unknown = old
                    unknown.status = .failed; unknown.errorCode = "upstream_outcome_unknown"; unknown.nextAttemptAt = nil
                    try await repository.updateEstimateJob(unknown)
                }
                state = try await repository.snapshot()
            }
            let jobs = state.jobs.filter { !$0.status.isTerminal && ($0.nextAttemptAt ?? .distantPast) <= clock.now }.sorted { $0.queuedAt < $1.queuedAt }
            guard !jobs.isEmpty else { return }
            for initial in jobs {
                guard !Task.isCancelled, !suspended else { return }
                do {
                    guard let url = initial.serviceURL else { throw ServiceFailure("not_configured") }
                    let policy = try await remote.policy(url: url)
                    let latest = try await repository.snapshot()
                    guard !suspended, let persisted = latest.jobs.first(where: { $0.id == initial.id }), !persisted.status.isTerminal,
                          latest.aiSettings.serviceURL == url, latest.aiSettings.consentEpoch == initial.consentEpoch else { continue }
                    try await repository.configureEstimation(url: url, policy: policy)
                    if let direct = remote as? any DirectEstimationRemote, direct.supportsDirect(url) {
                        guard policy.available, initial.requestCreatedAt == nil else { throw ServiceFailure("upstream_outcome_unknown") }
                        let calendar = Calendar(identifier: .gregorian)
                        let utc = TimeZone(secondsFromGMT: 0)!
                        let day = calendar.dateComponents(in: utc, from: clock.now)
                        let sentToday = latest.jobs.filter { item in
                            guard item.serviceURL == url, let sent = item.requestCreatedAt else { return false }
                            let other = calendar.dateComponents(in: utc, from: sent)
                            return (other.year, other.month, other.day) == (day.year, day.month, day.day)
                        }.count
                        guard sentToday < policy.dailyAttempts else { throw ServiceFailure("quota_exceeded") }
                        var images: [Data] = []
                        for id in initial.photoIDs {
                            guard let photo = latest.photos.first(where: { $0.id == id }) else { throw ServiceFailure("missing_photo") }
                            images.append(try UploadImage.jpeg(await repository.readPhoto(photo)))
                        }
                        guard try await eligible(initial), var job = try await repository.prepareEstimateSend(id: initial.id, at: clock.now) else { continue }
                        job.status = .running; job.nextAttemptAt = nil
                        try await repository.updateEstimateJob(job)
                        let response = try await direct.estimateDirect(job, images: images)
                        guard response.status == "succeeded", let result = response.result else { throw ServiceFailure("invalid_model_output") }
                        _ = try await repository.applyEstimate(jobID: job.id, revision: result.revision(for: job))
                        continue
                    }
                    guard var job = try await repository.prepareEstimateSend(id: initial.id, at: clock.now) else { continue }
                    if let deadline = job.deadline, deadline <= clock.now { throw ServiceFailure("expired") }
                    var references = job.uploadedReferences ?? []
                    while references.count < job.photoIDs.count {
                        guard try await eligible(job) else { break }
                        let photoID = job.photoIDs[references.count]
                        let snapshot = try await repository.snapshot()
                        guard let photo = snapshot.photos.first(where: { $0.id == photoID }) else { throw ServiceFailure("missing_photo") }
                        let bytes = try UploadImage.jpeg(await repository.readPhoto(photo))
                        guard try await eligible(job) else { break }
                        let reference = try await remote.upload(data: bytes, job: job)
                        references.append(reference); job.uploadedReferences = references
                        try await repository.updateEstimateJob(job)
                    }
                    guard try await eligible(job) else { continue }
                    job.uploadedReferences = references
                    try await repository.updateEstimateJob(job)
                    guard try await eligible(job) else { continue }
                    let response = try await (job.remoteJobID == nil ? remote.submit(job) : remote.poll(job))
                    job.remoteJobID = response.jobID; job.attempts = 0; job.errorCode = nil
                    switch response.status {
                    case "queued", "running":
                        job.status = response.status == "queued" ? .queued : .running
                        job.nextAttemptAt = clock.now.addingTimeInterval(3)
                        try await repository.updateEstimateJob(job)
                    case "succeeded":
                        job.status = .running
                        try await repository.updateEstimateJob(job)
                        guard let result = response.result else { throw ServiceFailure("invalid_model_output") }
                        _ = try await repository.applyEstimate(jobID: job.id, revision: result.revision(for: job))
                    case "failed", "cancelled", "expired":
                        job.status = response.status == "cancelled" ? .cancelled : .failed
                        job.errorCode = response.errorCode ?? response.status
                        try await repository.updateEstimateJob(job)
                    default: throw ServiceFailure("invalid_response")
                    }
                } catch { try await recordFailure(error, id: initial.id) }
            }
        } catch { storageFailed = true }
    }
    public func setSuspended(_ value: Bool) { suspended = value }
    private func eligible(_ job: EstimateJob) async throws -> Bool {
        guard !suspended else { return false }
        let state = try await repository.snapshot()
        guard let persisted = state.jobs.first(where: { $0.id == job.id }), !persisted.status.isTerminal else { return false }
        return EstimationRules.eligible(persisted, in: state)
    }
    private func recordFailure(_ error: Error, id: UUID) async throws {
        let state = try await repository.snapshot()
        guard var job = state.jobs.first(where: { $0.id == id }), !job.status.isTerminal else { return }
        if Task.isCancelled { return }
        let failure = error as? ServiceFailure
        if let direct = remote as? any DirectEstimationRemote, let url = job.serviceURL, direct.supportsDirect(url), job.status == .running {
            job.status = .failed; job.nextAttemptAt = nil
            let definitive = ["unauthorized", "provider_unauthorized", "rate_limited", "invalid_input", "quota_exceeded", "invalid_model_output", "cannot_recognize"]
            job.errorCode = failure.flatMap { definitive.contains($0.code) ? $0.code : nil } ?? "upstream_outcome_unknown"
            try await repository.updateEstimateJob(job)
            return
        }
        if failure?.code == "policy_changed" {
            let policy = if let url = job.serviceURL { try? await remote.policy(url: url) } else { nil as AIServicePolicy? }
            let latest = try await repository.snapshot()
            guard !suspended, latest.aiSettings.serviceURL == job.serviceURL,
                  latest.aiSettings.consentEpoch == job.consentEpoch else { return }
            if let policy { try await repository.configureEstimation(url: job.serviceURL, policy: policy) }
            else { try await repository.revokeEstimationConsent() }
            return
        }
        let network = error is URLError
        let retryable = network || failure?.code == "rate_limited"
        job.errorCode = network ? "network_unavailable" : (failure?.code ?? "invalid_response")
        job.attempts += 1
        if retryable && job.attempts <= 6 {
            job.status = .pendingNetwork
            let serverDelay = failure?.retryAfter.flatMap { $0.isFinite && $0 > 0 ? min($0, 3600) : nil } ?? 0
            job.nextAttemptAt = clock.now.addingTimeInterval(max(serverDelay, min(60, pow(2, Double(job.attempts)))))
        } else { job.status = .failed; job.nextAttemptAt = nil }
        try await repository.updateEstimateJob(job)
    }
}
