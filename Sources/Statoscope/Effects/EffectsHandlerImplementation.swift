//
//  EffectsHandlerImplementation.swift
//  
//
//  Created by Sergi Hernanz on 28/1/24.
//

import Foundation

public var scopeEffectsDisabledInUnitTests: Bool = nil != NSClassFromString("XCTest")
let scopeEffectsDisabledInPreviews: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

// Internal actor to handle effects
actor EffectsHandlerImplementation<When: Sendable> {

    private var requestedEffects: [(UInt, AnyEffect<When>)] = []
    private var runningTasks: [UInt: Task<When?, Error>] = [:]
    let logPrefix: String
    let effectCompleted: (UInt, AnyEffect<When>, When?) -> Void

    init(
        logPrefix: String,
        effectCompleted: @escaping (UInt, AnyEffect<When>, When?) -> Void
    ) {
        self.logPrefix = logPrefix
        self.effectCompleted = effectCompleted
    }

    func triggerNewEffectsState(
        newSnapshot: EffectsState<When>,
        injectionTreeNode: InjectionTreeNode?
    ) async throws {

        removeCancelledEffectsAndCancelTasks(effects: newSnapshot.cancelledEffects)
        requestedEffects.append(contentsOf: newSnapshot.enquedEffects)

        guard !scopeEffectsDisabledInUnitTests else {
            return
        }
        guard !scopeEffectsDisabledInPreviews else {
            throw StatoscopeErrors.effectsDisabledForPreviews
        }

        try await runNewEffects(
            newSnapshot: newSnapshot,
            injectionTreeNode: injectionTreeNode
        )
    }

    private func runNewEffects(
        newSnapshot: EffectsState<When>,
        injectionTreeNode: InjectionTreeNode?
    ) async throws {
        var toEnqueueEffects: [(UInt, AnyEffect<When>)] = newSnapshot.enquedEffects
        let currentCount = newSnapshot.snapshotEffects.count
        var enqueued = 0
        while toEnqueueEffects.count > 0 {
            let uuidAndEffect = toEnqueueEffects.removeFirst()
            let uuid = uuidAndEffect.0
            let effect = uuidAndEffect.1
            if let injectionTreeNode {
                effect._injectNode(injectionTreeNode)
            }
            let newCount = currentCount + enqueued
            StatoscopeLogger.LOG(
                .effects,
                prefix: logPrefix,
                newCount > 1 ? "🪃 ↗ [\(uuid)] (x\(newCount))\t\(describeObject(effect))" :
                    "🪃 ↗ [\(uuid)] \t\(describeObject(effect))"
            )
            enqueued += 1
            let task = await buildEffectTask(logPrefix: logPrefix, uuid: uuid, effect: effect)
            runningTasks[uuid] = task
            Task {
                let result = await task.result
                removeRequestedEffect(uuid)
                runningTasks.removeValue(forKey: uuid)
                switch result {
                case .success(let when):
                    guard !Task.isCancelled else {
                        assertionFailure("Can we ever get here ? I don't think so. Delete if never fails?")
                        StatoscopeLogger.LOG(
                            .effects,
                            prefix: logPrefix,
                            "🪃 🚫 [\(uuid)] CANCELLED (right before sending result)\n" +
                            describeObject(effect)
                        )
                        throw CancellationError()
                    }
                    effectCompleted(uuid, effect, when)
                case .failure(let error):
                    StatoscopeLogger.LOG(
                        .effects,
                        prefix: logPrefix,
                        "🪃 💥 [\(uuid)] Unhandled throw (use mapToResult to handle)\n" +
                        describeObject(effect) +
                        "\nError: \(error)."
                    )
                    effectCompleted(uuid, effect, nil)
                }
            }
        }
    }

    func buildSnapshot() -> EffectsState<When> {
        EffectsState(snapshotEffects: requestedEffects)
    }

    var effects: [any Effect] {
        requestedEffects.map { $0.1.pristine }
    }

    func buildEffectTask(logPrefix: String, uuid: UInt, effect: AnyEffect<When>) async -> Task<When?, Error> {
        let newTask: Task<When?, Error> = Task { [weak self] in
            guard nil != self else {
                StatoscopeLogger.LOG(
                    .effects,
                    prefix: logPrefix,
                    "🪃 🚫 [\(uuid)] CANCELLED (not even started)" + .newLine + "\(describeObject(effect))"
                )
                throw CancellationError()
            }
            let result = try await effect.runEffect()
            if Task.isCancelled {
                StatoscopeLogger.LOG(
                    .effects,
                    prefix: logPrefix,
                    "🪃 🚫 [\(uuid)] CANCELLED (completely executed though, " +
                    "cancelled right before sending result back to scope)" +
                        .newLine +
                    "\(describeObject(effect))"
                )
                return nil
            }
            return result
        }
        return newTask
    }

    private func removeCancelledEffectsAndCancelTasks(
        effects: [(UInt, AnyEffect<When>)]
    ) {
        let cancellableUUIDs = effects.map { $0.0 }
        requestedEffects = requestedEffects.filter { currentlyRequested in
            !cancellableUUIDs.contains(currentlyRequested.0)
        }
        effects.forEach { effect in
            StatoscopeLogger.LOG(.effects, prefix: logPrefix, "🪃 ✋ [\(effect.0)] CANCELLING\n\(describeObject(effect))")
        }
        for cancellable in effects {
            if let (_, task) = runningTasks.first(where: { (taskUuid, _) in taskUuid == cancellable.0 }) {
                task.cancel()
            }
        }
    }

    func cancelAllEffects() {
        requestedEffects
            .map { ($0.0, $0.1.pristine) }
            .forEach { effect in
                StatoscopeLogger.LOG(
                    .effects,
                    prefix: logPrefix,
                    "🪃 ✋ [\(effect.0)] CANCELLING\n\(describeObject(effect))"
                )
            }
        requestedEffects.removeAll()
        cancelAllTasks()
    }

    private func cancelAllTasks() {
        let retainedTasks: [Task<When?, Error>] = Array(runningTasks.values)
        runningTasks.removeAll()
        Task(priority: .high, operation: {
            retainedTasks
                .forEach {
                    $0.cancel()
                }
        })
    }

    private func removeRequestedEffect(_ uuid: UInt) {
        if let idx = requestedEffects.firstIndex(where: { uuid == $0.0 }) {
            requestedEffects.remove(at: idx)
        }
    }
}
