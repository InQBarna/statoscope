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

internal final class EffectsHandlerImplementation<When: Sendable> {

    private var requestedEffects: [(UUID, AnyEffect<When>)] = []
    private var tasks: RunnerTasks<When> = RunnerTasks()
    let logPrefix: String

    init(logPrefix: String) {
        self.logPrefix = logPrefix
    }
    
    func runEnqueuedEffectAndGetWhenResults(
        newSnapshot: EffectsState<When>,
        safeSend: @escaping (AnyEffect<When>, When?, [(UUID, AnyEffect<When>)]) async -> Void
    ) throws -> [(UUID, AnyEffect<When>)] {
        
        cancelEffects(effects: newSnapshot.cancelledEffects)
        
        assert(Thread.current.isMainThread, "For requestedEffects thread safety")
        requestedEffects.append(contentsOf: newSnapshot.enquedEffects)

        guard !scopeEffectsDisabledInUnitTests else {
            return requestedEffects
        }
        guard !scopeEffectsDisabledInPreviews else {
            throw StatoscopeErrors.effectsDisabledForPreviews
        }

        var toEnqueueEffects: [(UUID, AnyEffect<When>)] = newSnapshot.enquedEffects
        let currentCount = newSnapshot.snapshotEffects.count
        var enqueued = 0
        while toEnqueueEffects.count > 0 {
            let effect = toEnqueueEffects.removeFirst()
            let handler = self
            let newCount = currentCount + enqueued
            if newCount > 1 {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 ↗ \(effect.1) (ongoing \(newCount)x🪃)")
            } else {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 ↗ \(effect.1)")
            }
            enqueued += 1
            Task { [weak handler] in
                do {
                    guard let result = try await handler?.triggerEffect(effect.0, effect: effect.1) else {
                        return
                    }
                    switch result {
                    case .success(let optionalWhen):
                        if let when = optionalWhen {
                            guard !Task.isCancelled else {
                                assertionFailure("Can we ever get here ? I don't think so. Delete if never fails?")
                                StatoscopeLogger.LOG(prefix: logPrefix,
                                                     "🪃 🚫 CANCELLED \(effect.1) (right before sending result)")
                                throw CancellationError()
                            }
                            await safeSend(effect.1, when, handler?.requestedEffects ?? [])
                        }
                    case .failure(let error):
                        StatoscopeLogger.LOG(prefix: logPrefix,
                                             "🪃 💥 Unhandled throw (use mapToResult to handle): \(effect): \(error).")
                    }
                } catch {
                    await safeSend(effect.1, nil, handler?.requestedEffects ?? [])
                }
            }
        }
        return requestedEffects
    }

    internal func buildSnapshot() -> EffectsState<When> {
        EffectsState(snapshotEffects: requestedEffects)
    }

    private func triggerEffect(_ uuid: UUID, effect: AnyEffect<When>) async throws -> Result<When?, Error> {

        let taskUUID = uuid // UUID()
        let tasks = self.tasks
        let newTask: Task<When?, Error> = Task { [weak tasks] in
            guard nil != tasks else {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 🚫 CANCELLED \(effect) (not even started)")
                await removeRequestedEffect(uuid)
                throw CancellationError()
            }
            let result = try await effect.runEffect()
            if Task.isCancelled {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 🚫 CANCELLED \(effect)")
                await removeRequestedEffect(uuid)
                return nil
            }
            await tasks?.removeTask(taskUUID)
            if Task.isCancelled {
                StatoscopeLogger.LOG(prefix: logPrefix,
                                     "🪃 🚫 CANCELLED \(effect) (complete executed though, " +
                                     "cancelled right before sending result back to scope)")
                await removeRequestedEffect(uuid)
                return nil
            }
            return result
        }
        await tasks.addTask(taskUUID, task: newTask)
        let returnResult = await newTask.result
        await removeRequestedEffect(uuid)
        return returnResult
    }

    private func cancelEffects(
        effects: [(UUID, AnyEffect<When>)]
    ) {
        let cancellableUUIDs = effects.map { $0.0 }
        requestedEffects = requestedEffects.filter { currentlyRequested in
            !cancellableUUIDs.contains(currentlyRequested.0)
        }
        effects.forEach { effect in
            StatoscopeLogger.LOG(prefix: logPrefix, "🪃 ✋ CANCELLING \(effect)")
        }
        let retainedTasks = tasks
        Task(priority: .high, operation: {
            for cancellable in effects {
                await retainedTasks.cancel(cancellable.0)
            }
        })
    }
    
    func cancelAllEffects() {
        assert(Thread.current.isMainThread, "For requestedEffects thread safety")
        requestedEffects
            .map { ($0.0, $0.1.pristine) }
            .forEach { effect in
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 ✋ CANCELLING \(effect)")
            }
        requestedEffects.removeAll()
        cancelAllTasks()
    }
    
    private func cancelAllTasks() {
        let retainedTasks = tasks
        Task(priority: .high, operation: {
            let count = await retainedTasks.count()
            if count > 0 {
                await retainedTasks.cancelAndRemoveAll()
            }
        })
    }
    
    deinit {
        cancelAllTasks()
    }

    @MainActor
    private func removeRequestedEffect(_ uuid: UUID) {
        assert(Thread.current.isMainThread, "For requestedEffects thread safety")
        if let idx = requestedEffects.firstIndex(where: { uuid == $0.0 }) {
            requestedEffects.remove(at: idx)
        }
    }
}

/*
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
 assert(Thread.current.isMainThread, "For requestedEffects thread safety")
 return EffectsState(snapshotEffects: requestedEffects)
 }
 
 
 }
 */
