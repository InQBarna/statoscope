//
//  Statetoscope.swift
//  familymealplan
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

public protocol ScopeProtocol: AnyObject {
    var effects: [any Effect] { get }
    func clearEffects()
}

public protocol Statoscope: AnyObject {
    associatedtype When: Sendable
    func update(_ when: When) throws
    @discardableResult
    func send(_ when: When) -> Self
    @discardableResult
    func unsafeSend(_ when: When) throws -> Self
}

public protocol EffectError {
    static var unknownError: Self { get }
}

public protocol Scope: Statoscope & ScopeProtocol & ChainLink { }

extension Statoscope {
    func LOG(_ string: String) {
        let prefix = "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
        StatoscopeLogger.LOG(prefix: prefix, string)
    }
}

extension Statoscope {
    @discardableResult
    public func send(_ when: When) -> Self {
        LOG("\(when)")
        do {
            return try unsafeSend(when)
        } catch {
            LOG("‼️ Exception on send method: \(error)")
            return self
        }
    }
    var typeDescription: String {
        "\(type(of: self))"
    }
}

public var scopeEffectsDisabledInUnitTests: Bool = nil != NSClassFromString("XCTest")
fileprivate let scopeEffectsDisabledInPreviews: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

extension Scope {
    public func unsafeSend(_ when: When) throws -> Self {
        try update(when)
        try runEffectAndSendResult()
        return self
    }
    #if false
    func enqueueAnonymous(_ effect: AnyEffect<When>) {
        effectsHandler.enqueueAnonymous(effect)
        try? runEffectAndSendResult()
    }
    #endif
    public func enqueue<E: Effect>(_ effect: E) where E.ResType == When {
        effectsHandler.enqueue(effect)
        try? runEffectAndSendResult()
    }
    
    private func runEffectAndSendResult() throws {
        guard !scopeEffectsDisabledInUnitTests else {
            return
        }
        guard !scopeEffectsDisabledInPreviews else {
            throw StatoscopeErrors.effectsDisabledForPreviews
        }
        assert(Thread.current.isMainThread, "For pending/ongoingEffects thread safety")
        let logPrefix = "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
        var copiedEffects: [(UUID, AnyEffect<When>)] = effectsHandler.pendingEffects.map { (UUID(), $0) }
        effectsHandler.clearPending()
        effectsHandler.ongoingEffects.append(contentsOf: copiedEffects)
        ensureSetupDeinitObserver()
        let currentCount = effectsHandler.ongoingEffects.count
        var enqueued = 0
        while copiedEffects.count > 0 {
            let effect = copiedEffects.removeFirst()
            let handler = effectsHandler
            let safeSend: ((AnyEffect<When>, When) async -> Void) = { [weak self] effect, when in
                await self?.safeMainActorSend(effect, when)
            }
            let newCount = currentCount + enqueued
            if newCount > 1 {
                LOG("🪃 ↗ \(effect.1) (ongoing \(newCount)x🪃)")
            } else {
                LOG("🪃 ↗ \(effect.1)")
            }
            enqueued += 1
            Task { [weak self, weak handler] in
                
                guard let result = try await handler?.runEffectOnHandler(effect.0, effect: effect.1, logPrefix: logPrefix) else {
                    await handler?.removeOngoingEffect(effect.0)
                    return
                }
                switch result {
                case .success(let optionalWhen):
                    if let when = optionalWhen {
                        await handler?.removeOngoingEffect(effect.0)
                        guard !Task.isCancelled else {
                            assertionFailure("Creo que es imposible cancelar esta task,,, se puede borrar este isCancelled ??")
                            self?.LOG("🪃 🚫 CANCELLED \(effect.1) (right before sending result)")
                            throw CancellationError()
                        }
                        await safeSend(effect.1, when)
                    }
                case .failure(let error):
                    self?.LOG("🪃 💥 Unhandled throw (use mapToResult to handle): \(effect): \(error).")
                    await handler?.removeOngoingEffect(effect.0)
                }
            }
        }
    }
    public var effects: [any Effect] {
        return (effectsHandler.pendingEffects + effectsHandler.ongoingEffects.map { $0.1 })
            .map { $0.wrappedEffect }
    }
    public func clearEffects() {
        effectsHandler.clearPending()
    }

    public func cancelEffect(where whereBlock: (any Effect) -> Bool) {
        let logPrefix = "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
        effectsHandler.cancelEffect(logPrefix: logPrefix, where: whereBlock)
    }
    
    @MainActor
    fileprivate func safeMainActorSend(_ effect: AnyEffect<When>, _ when: When) {
        let count = effects.count
        if count > 0 {
            LOG("🪃 ↩ \(effect) (ongoing \(count)x🪃)")
        } else {
            LOG("🪃 ↩ \(effect)")
        }
        send(when)
    }
}

extension Statoscope {
    public func set<T>(_ keyPath: WritableKeyPath<Self, T>, _ value: T) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}

fileprivate var effectsHandlerStoreKey: UInt8 = 0
private extension Scope {
    var effectsHandler: EffectsHandler<When> {
        get {
            return associatedObject(base: self, key: &effectsHandlerStoreKey, initialiser: { EffectsHandler<When>() })
        }
    }
}

final class EffectsHandler<When: Sendable> {
    fileprivate var pendingEffects: [AnyEffect<When>] = []
    fileprivate var ongoingEffects: [(UUID, AnyEffect<When>)] = []
    #if false
    fileprivate func enqueueAnonymous(_ effect: AnyEffect<When>) {
        pendingEffects.append(effect)
    }
    #endif
    fileprivate func enqueue<E: Effect>(_ effect: E) where E.ResType == When {
        pendingEffects.append(AnyEffect(effect: effect))
    }
    func clearPending() {
        pendingEffects.removeAll()
    }
    
    private actor RunnerTasks {
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
    private var tasks = RunnerTasks()
    fileprivate func runEffectOnHandler(_ uuid: UUID, effect: AnyEffect<When>, logPrefix: String) async throws -> Result<When?, Error> {
        let taskUUID = uuid // UUID()
        let tasks = self.tasks
        let newTask: Task<When?, Error> = Task { [weak tasks] in
            guard nil != tasks else {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 🚫 CANCELLED \(effect) (not even started)")
                throw CancellationError()
            }
            let result = try await effect.runEffect()
            if Task.isCancelled {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 🚫 CANCELLED \(effect)")
                return nil
            }
            await tasks?.removeTask(taskUUID)
            if Task.isCancelled {
                StatoscopeLogger.LOG(prefix: logPrefix, "🪃 🚫 CANCELLED \(effect) (complete executed though, cancelled right before sending result back to scope)")
                return nil
            }
            return result
        }
        await tasks.addTask(taskUUID, task: newTask)
        return await newTask.result
    }
    
    @discardableResult
    fileprivate func cancelEffect(logPrefix: String, where whereBlock: (any Effect) -> Bool) -> [(UUID, any Effect)] {
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
        return cancellables
    }
    
    fileprivate func cancellAllTasks() {
        let retainedTasks = tasks
        Task(priority: .high, operation: {
            let count = await retainedTasks.count()
            if count > 0 {
                await retainedTasks.cancelAndRemoveAll()
            }
        })

    }
    
    deinit {
        cancellAllTasks()
    }

    @MainActor
    fileprivate func removeOngoingEffect(_ uuid: UUID) {
        assert(Thread.current.isMainThread, "For pending/ongoingEffects thread safety")
        if let idx = ongoingEffects.firstIndex(where: { uuid == $0.0 }) {
            ongoingEffects.remove(at: idx)
        }
    }
}

// Helper so we detect Scope release and cancel effects on deinit
fileprivate var deinitObserverStoreKey: UInt8 = 0
fileprivate class DeinitObserver {
    let execute: () -> ()
    init(execute: @escaping () -> ()) {
        self.execute = execute
    }
    deinit {
        execute()
    }
}

fileprivate extension Scope {
    var deinitObserver: DeinitObserver? {
        get {
            optionalAssociatedObject(base: self, key: &deinitObserverStoreKey, initialiser: { nil })
        }
        set {
            associateOptionalObject(base: self, key: &deinitObserverStoreKey, value: newValue)
        }
    }
    func ensureSetupDeinitObserver() {
        if deinitObserver == nil {
            let handler = effectsHandler
            deinitObserver = DeinitObserver { [weak handler] in
                handler?.cancellAllTasks()
            }
        }
    }
}
