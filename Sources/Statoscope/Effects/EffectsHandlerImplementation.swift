//
//  EffectsHandlerImplementation.swift
//  
//
//  Created by Sergi Hernanz on 28/1/24.
//

import Foundation

private actor RunnerTasks<When: Sendable> {
    var runningTasks: [UUID: Task<When?, Error>] = [:]
    func addTask(_ uuid: UUID, task: Task<When?, Error>) {
        runningTasks[uuid] = task
    }
    func removeTask(_ uuid: UUID) {
        runningTasks.removeValue(forKey: uuid)
    }
    func cancelAndRemoveAll() {
        runningTasks.forEach { $0.value.cancel() }
        runningTasks.removeAll()
    }
    func count() -> Int {
        return runningTasks.count
    }
    func cancel(_ uuid: UUID) {
        runningTasks.forEach { (taskUuid, task) in
            if taskUuid == uuid {
                task.cancel()
            }
        }
    }
}

internal final class EffectsHandlerImplementation<When: Sendable>: Effectfull {

    // TODO: Use actors, pendingEffects and ongoingEffects are only edited from main actor now
    // private var pendingEffects: [AnyEffect<When>] = []
    private(set) var ongoingEffects: [(UUID, AnyEffect<When>)] = []
    private var tasks: RunnerTasks<When> = RunnerTasks()
    let logPrefix: String
    internal var currentSnapshot: EffectsState<When>?

    init(logPrefix: String) {
        self.logPrefix = logPrefix
    }

    var effects: [any Effect] {
        assert(Thread.current.isMainThread, "For pending/ongoingEffects thread safety")
        return ongoingEffects
            .map { $0.1.pristine }
    }

    // TODO: should we move to main actor ? retains self and fails to detect deinit
    // @MainActor
    func runEnqueuedEffectAndGetWhenResults(
        newSnapshot: EffectsState<When>,
        safeSend: @escaping (AnyEffect<When>, When) async -> Void
    ) throws {
        assert(Thread.current.isMainThread, "For pending/ongoingEffects thread safety")
        cancelEffects(uuids: newSnapshot.cancelledEffects)
        var copiedEffects: [(UUID, AnyEffect<When>)] = newSnapshot.enquedEffects
        ongoingEffects.append(contentsOf: copiedEffects)
        
        guard !scopeEffectsDisabledInUnitTests else {
            return
        }
        guard !scopeEffectsDisabledInPreviews else {
            throw StatoscopeErrors.effectsDisabledForPreviews
        }
        
        let currentCount = ongoingEffects.count
        var enqueued = 0
        while copiedEffects.count > 0 {
            let effect = copiedEffects.removeFirst()
            let handler = self
            let newCount = currentCount + enqueued
            if newCount > 1 {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 ↗ \(effect.1) (ongoing \(newCount)x🪃)")
            } else {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 ↗ \(effect.1)")
            }
            enqueued += 1
            Task { [weak handler] in
                guard let result = try await handler?.triggerEffect(effect.0, effect: effect.1) else {
                    return
                }
                switch result {
                case .success(let optionalWhen):
                    if let when = optionalWhen {
                        guard !Task.isCancelled else {
                            assertionFailure("Creo que es imposible cancelar esta task,,, " +
                                             "se puede borrar este isCancelled ??")
                            StatoscopeLogger.LOG(prefix: logPrefix,
                                                 "🪃 🚫 CANCELLED \(effect.1) (right before sending result)")
                            throw CancellationError()
                        }
                        await safeSend(effect.1, when)
                    }
                case .failure(let error):
                    StatoscopeLogger.LOG(prefix: logPrefix,
                                         "🪃 💥 Unhandled throw (use mapToResult to handle): \(effect): \(error).")
                }
            }
        }
    }

    private func triggerEffect(_ uuid: UUID, effect: AnyEffect<When>) async throws -> Result<When?, Error> {

        let taskUUID = uuid // UUID()
        let tasks = self.tasks
        let newTask: Task<When?, Error> = Task { [weak tasks] in
            guard nil != tasks else {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 🚫 CANCELLED \(effect) (not even started)")
                await removeOngoingEffect(uuid)
                throw CancellationError()
            }
            let result = try await effect.runEffect()
            if Task.isCancelled {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 🚫 CANCELLED \(effect)")
                await removeOngoingEffect(uuid)
                return nil
            }
            await tasks?.removeTask(taskUUID)
            if Task.isCancelled {
                StatoscopeLogger.LOG(prefix: logPrefix,
                                     "🪃 🚫 CANCELLED \(effect) (complete executed though, " +
                                     "cancelled right before sending result back to scope)")
                await removeOngoingEffect(uuid)
                return nil
            }
            return result
        }
        await tasks.addTask(taskUUID, task: newTask)
        let returnResult = await newTask.result
        await removeOngoingEffect(uuid)
        return returnResult
    }

    func cancelEffects(uuids: [UUID]) {
        assert(Thread.current.isMainThread, "For pending/ongoingEffects thread safety")
        let cancellables = ongoingEffects
            .filter { uuids.contains($0.0) }
        cancellables.forEach { effect in
            StatoscopeLogger.LOG(prefix: logPrefix, "🪃 ✋ CANCELLING \(effect)")
        }
        Task(priority: .high, operation: {
            for cancellable in cancellables {
                await tasks.cancel(cancellable.0)
            }
        })
    }
    
    func cancelAllEffects() {
        let retainedTasks = tasks
        ongoingEffects
            .map { ($0.0, $0.1.pristine) }
            .forEach { effect in
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 ✋ CANCELLING \(effect)")
            }
        ongoingEffects.removeAll()
        Task(priority: .high, operation: {
            let count = await retainedTasks.count()
            if count > 0 {
                await retainedTasks.cancelAndRemoveAll()
            }
        })
    }
    
    deinit {
        cancelAllEffects()
    }

    @MainActor
    func removeOngoingEffect(_ uuid: UUID) {
        assert(Thread.current.isMainThread, "For pending/ongoingEffects thread safety")
        if let idx = ongoingEffects.firstIndex(where: { uuid == $0.0 }) {
            ongoingEffects.remove(at: idx)
        }
    }
}

extension EffectsHandlerImplementation {
    
    public var snapshot: EffectsState<When> {
        get {
            if let currentSnapshot {
                return currentSnapshot
            }
            let newSnapshot = buildSnapshot()
            currentSnapshot = newSnapshot
            return newSnapshot
        }
        set {
            currentSnapshot = newValue
        }
    }
    
    internal func cleanupSnapshot() {
        currentSnapshot = nil
    }
    
    internal func buildSnapshot() -> EffectsState<When> {
        assert(Thread.current.isMainThread, "For pending/ongoingEffects thread safety")
        return EffectsState(snapshotEffects: ongoingEffects)
    }
    

}

// TODO: To be used when we have Reducer-style Scopes

/*
/// A helper class to spy the effects launched by an Statoscope
public final class EffectsHandlerSpy<When: Sendable>: EffectsHandler<When> {

    private var privateEffects: [AnyEffect<When>] = []
    private var privateCancelledEffects: [AnyEffect<When>] = []

    /// returns the recently cancelled effects
    public var cancelledEffects: [any Effect] {
        privateCancelledEffects
    }

    /// Returns enqueued effects
    public override var effects: [any Effect] {
        privateEffects.map { $0.pristine }
    }

    /// Enqueues an effect, but it never runs it
    public override func enqueue<E: Effect>(
        _ effect: E
    ) where E.ResultType == When {
        privateEffects.append(AnyEffect(effect: effect))
    }

    /// Updates the cancelledEffects variable with the provided closure
    public override func cancelEffect(where whereBlock: (any Effect) -> Bool) {
        privateCancelledEffects.removeAll()
        let newCancelled = privateEffects.filter(whereBlock)
        privateCancelledEffects.append(contentsOf: newCancelled)
    }

    /// Updates the cancelledEffects with all current effects
    public override func cancelAllEffects() {
        privateCancelledEffects.removeAll()
        privateCancelledEffects.append(contentsOf: privateEffects)
        privateEffects.removeAll()
    }
}

*/
