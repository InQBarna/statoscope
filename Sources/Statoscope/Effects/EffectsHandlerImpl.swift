//
//  EffectsHandlerImpl.swift
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

// TODO: rename to EffectsBouncer ?

/// A base class to handle Effects. Capable of launching an Effect and keep it working during all the lifespan
///  of the EffectsHandler. All ongoing effects can be cleared before triggered (good for testing purposes),
///  read or cancelled
public class EffectsHandler<When: Sendable>: EffectsContainer {
    public var effects: [any Effect] { fatalError() }
    public func clearPending() { fatalError() }
    public func enqueue<E: Effect>(_ effect: E) where E.ResType == When { fatalError() }
    public func cancelEffect(where whereBlock: (any Effect) -> Bool) { fatalError() }
    public func cancelAllEffects() { fatalError() }
    internal init() { }
}

internal final class EffectsHandlerImpl<When: Sendable>: EffectsHandler<When> {

    // Status
    private var pendingEffects: [AnyEffect<When>] = []
    private var ongoingEffects: [(UUID, AnyEffect<When>)] = []
    private var tasks: RunnerTasks<When> = RunnerTasks()
    let logPrefix: String

    init(logPrefix: String) {
        self.logPrefix = logPrefix
    }

    public override var effects: [any Effect] {
        return (pendingEffects + ongoingEffects.map { $0.1 })
            .map { $0.wrappedEffect }
    }

    override func enqueue<E: Effect>(
        _ effect: E
    ) where E.ResType == When {
        pendingEffects.append(AnyEffect(effect: effect))
    }

    func runEnqueuedEffectAndGetWhenResults(
        safeSend: @escaping (AnyEffect<When>, When) async -> Void
    ) throws {
        assert(Thread.current.isMainThread, "For pending/ongoingEffects thread safety")
        var copiedEffects: [(UUID, AnyEffect<When>)] = pendingEffects.map { (UUID(), $0) }
        clearPending()
        ongoingEffects.append(contentsOf: copiedEffects)
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

    override func clearPending() {
        pendingEffects.removeAll()
    }

    override func cancelEffect(where whereBlock: (any Effect) -> Bool) {
        let cancellables = ongoingEffects
            .map { ($0.0, $0.1.wrappedEffect) }
            .filter { whereBlock($0.1) }
        cancellables.forEach { effect in
            StatoscopeLogger.LOG(prefix: logPrefix, "🪃 ✋ CANCELLING \(effect)")
        }
        Task(priority: .high, operation: {
            for cancellable in cancellables {
                await tasks.cancel(cancellable.0)
            }
        })
    }

    override func cancelAllEffects() {
        let retainedTasks = tasks
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

// TODO: To be used when we have Reducer-style Scopes

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
        privateEffects.map { $0.wrappedEffect }
    }

    /// Clears all enqueued effects
    public override func clearPending() {
        privateEffects.removeAll()
    }

    /// Enqueues an effect, but it never runs it
    public override func enqueue<E: Effect>(
        _ effect: E
    ) where E.ResType == When {
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
