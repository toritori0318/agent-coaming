import Foundation

public actor Refresher {
    private let providers: [any UsageProvider]
    private var previous: [ProviderID: ProviderSnapshot]
    private var generatedAt: Date
    private let backoff: any BackoffStore
    private var inFlight: Task<Snapshot, Never>?

    init(providers: [any UsageProvider], previous: Snapshot?, backoff: any BackoffStore) {
        self.providers = providers
        self.previous = Dictionary(uniqueKeysWithValues: (previous?.providers ?? []).map { ($0.id, $0) })
        self.generatedAt = previous?.generatedAt ?? Date()
        self.backoff = backoff
    }

    public func refresh(force: Bool = false, enabled: Set<ProviderID> = Set(ProviderID.included)) async -> Snapshot {
        await refresh(at: Date(), force: force, enabled: enabled)
    }

    func refresh(at now: Date, force: Bool, enabled: Set<ProviderID> = Set(ProviderID.included)) async -> Snapshot {
        // Join an in-flight refresh so the timer and a manual refresh do not run twice.
        if let inFlight { return await inFlight.value }
        let task = Task { await perform(at: now, force: force, enabled: enabled) }
        inFlight = task
        defer { inFlight = nil }
        return await task.value
    }

    private func perform(at now: Date, force: Bool, enabled: Set<ProviderID>) async -> Snapshot {
        struct Job: Sendable {
            var provider: any UsageProvider
            var shouldFetch: Bool
        }
        var jobs: [Job] = []
        for provider in providers {
            let state = backoff.load(provider.id)
            let blocked = state.blockedUntil.map { now < $0 } ?? false
            let tooSoon = state.lastAttemptAt.map { now.timeIntervalSince($0) < Constants.manualRefreshMinInterval } ?? false
            // A manual refresh may proceed during a block once 60 seconds have passed.
            // A process with no previous snapshot (the coaming CLI) is not treated as manual, so repeated launches do not hammer a 429.
            let manual = force && previous[provider.id] != nil
            let shouldFetch = enabled.contains(provider.id) && (manual ? !tooSoon : !blocked)
            jobs.append(Job(provider: provider, shouldFetch: shouldFetch))
        }

        let fetched = await withTaskGroup(of: (ProviderID, ProviderAttempt).self) { group in
            for job in jobs where job.shouldFetch {
                let provider = job.provider
                group.addTask {
                    let attempt = await provider.fetch(now: now)
                    return (provider.id, attempt)
                }
            }
            var results: [ProviderID: ProviderAttempt] = [:]
            for await (id, attempt) in group {
                results[id] = attempt
            }
            return results
        }

        if fetched.isEmpty {
            return snapshot(at: generatedAt, enabled: enabled)
        }

        for (id, attempt) in fetched {
            var state = backoff.load(id)
            state.lastAttemptAt = now
            if attempt.rateLimited {
                state.consecutive429 += 1
                let delay: TimeInterval
                if let retryAfter = attempt.retryAfter {
                    delay = min(max(retryAfter, 0), Constants.retryAfterMax)
                } else if state.consecutive429 >= 2 {
                    delay = Constants.retryAfterConsecutive
                } else {
                    delay = Constants.retryAfterDefault
                }
                state.blockedUntil = now.addingTimeInterval(delay)
            } else if attempt.snapshot.status == .ok {
                state.consecutive429 = 0
                state.blockedUntil = nil
            }
            backoff.save(id, state)
            previous[id] = merge(attempt, id: id)
        }
        generatedAt = now
        return snapshot(at: now, enabled: enabled)
    }

    func backoffState(_ id: ProviderID) -> BackoffState {
        backoff.load(id)
    }

    private func merge(_ attempt: ProviderAttempt, id: ProviderID) -> ProviderSnapshot {
        var snapshot = attempt.snapshot
        guard attempt.keepPrevious, let prior = previous[id] else { return snapshot }
        let hasPrior = prior.fetchedAt != nil || !prior.windows.isEmpty
        guard hasPrior else { return snapshot }
        snapshot.windows = prior.windows
        snapshot.fetchedAt = prior.fetchedAt
        if snapshot.planLabel == nil {
            snapshot.planLabel = prior.planLabel
        }
        snapshot.status = .stale
        if snapshot.staleReason == nil {
            snapshot.staleReason = prior.staleReason
        }
        return snapshot
    }

    /// Disabled providers are omitted from the written snapshot. Their previous values stay in memory for re-enable.
    private func snapshot(at now: Date, enabled: Set<ProviderID>) -> Snapshot {
        let providers = ProviderID.included.map { id in
            enabled.contains(id) ? previous[id] ?? .make(id, status: .notInstalled) : .make(id, status: .notInstalled)
        }
        return Snapshot(schemaVersion: Snapshot.currentSchemaVersion, generatedAt: now, providers: providers)
    }
}
