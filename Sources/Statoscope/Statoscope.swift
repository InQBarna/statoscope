//
//  Statetoscope.swift
//  familymealplan
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// Part of the ``Scope`` protocol. When adopted forces the implementation of the update method to mutate the store state
public protocol StoreImplementation {
    associatedtype When: Sendable
    func update(_ when: When) throws
}

/// Part of the ``Scope`` protocol. When conformed, an object automatcally synthesizes
public protocol Store {
    associatedtype When: Sendable
    @discardableResult
    func send(_ when: When) -> Self
    @discardableResult
    func unsafeSend(_ when: When) throws -> Self
}

public protocol Scope:
    Store                   // Public interface receiving When events + default dispatch implementation
    & StoreImplementation   // Forces inheriting class to implement the update business logic
    & EffectsContainer      // Public interface to dispatch effect + default forwarding and implementation
    & InjectionTreeNode     // Public interface for dependency injection and retrieval
    & AnyObject
{ }

extension Scope {
    var logPrefix: String {
        "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
    }
    func LOG(_ string: String) {
        StatoscopeLogger.LOG(prefix: logPrefix, string)
    }
}

extension Scope {
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
        if let middleware = middleWare {
            guard let mappedWhen = try middleware.middleWare(self, when) else {
                return self
            }
            try update(mappedWhen)
        } else {
            try update(when)
        }
        try runEnqueuedEffectAndGetWhenResults()
        return self
    }

    #if false
    func enqueueAnonymous(_ effect: AnyEffect<When>) {
        effectsHandler.enqueueAnonymous(effect)
        try? runEnqueuedEffectAndGetWhenResults()
    }
    #endif

    public func enqueue<E: Effect>(_ effect: E) where E.ResType == When {
        effectsHandler.enqueue(effect)
        try? runEnqueuedEffectAndGetWhenResults()
    }
    
    public func addMiddleWare(_ update: @escaping (Self, When) throws -> When?) -> Self {
        if let existingMiddleware = middleWare {
            middleWare = MiddleWareHandler(middleWare: { scope, when in
                guard let mappedWhen = try update(scope, when) else {
                    return nil
                }
                return try existingMiddleware.middleWare(scope, mappedWhen)
            })
        } else {
            middleWare = MiddleWareHandler(middleWare: update)
        }
        return self
    }
    
    func runEnqueuedEffectAndGetWhenResults() throws {
        guard !scopeEffectsDisabledInUnitTests else {
            return
        }
        guard !scopeEffectsDisabledInPreviews else {
            throw StatoscopeErrors.effectsDisabledForPreviews
        }
        ensureSetupDeinitObserver()
        try effectsHandler.runEnqueuedEffectAndGetWhenResults() { [weak self] effect, when in
            await self?.safeMainActorSend(effect, when)
        }
    }

    public var effects: [any Effect] {
        return effectsHandler.effects
    }

    public func clearPending() {
        effectsHandler.clearPending()
    }

    public func cancelEffect(where whereBlock: (any Effect) -> Bool) {
        effectsHandler.cancelEffect(where: whereBlock)
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

extension Scope {
    public func set<T>(_ keyPath: ReferenceWritableKeyPath<Self, T>, _ value: T) -> Self {
        self[keyPath: keyPath] = value
        return self
    }
}

fileprivate var effectsHandlerStoreKey: UInt8 = 0
private extension Scope {
    var effectsHandler: EffectsHandlerImpl<When> {
        get {
            return associatedObject(base: self, key: &effectsHandlerStoreKey, initialiser: {
                EffectsHandlerImpl<When>(logPrefix: logPrefix)
            })
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

fileprivate var middleWareHandlerStoreKey: UInt8 = 0
fileprivate final class MiddleWareHandler<S: Scope> {
    let middleWare: ((S, S.When) throws -> S.When?)
    init(middleWare: @escaping (S, S.When) throws -> S.When?) {
        self.middleWare = middleWare
    }
}

fileprivate extension Scope {
    var middleWare: MiddleWareHandler<Self>? {
        get {
            optionalAssociatedObject(base: self, key: &middleWareHandlerStoreKey, initialiser: { nil })
        }
        set {
            associateOptionalObject(base: self, key: &middleWareHandlerStoreKey, value: newValue)
        }
    }
}

// <LIBRARY>
public protocol StatoscopeProtocol {
    associatedtype State
    func state() -> State
}

public protocol StatoscopeImplementation: Scope {
    associatedtype MutableState
    func mutableState() -> MutableState
    static func update(state: MutableState, when: When, effects: EffectsHandler<Self.When>) throws
}

protocol Statoscope: StatoscopeProtocol, StatoscopeImplementation { }

extension StatoscopeImplementation {
    func update(_ when: When) throws {
        try Self.update(state: mutableState(), when: when, effects: effectsHandler)
    }
}

@propertyWrapper
public class StateVar<Value> {
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    public var wrappedValue: Value
}

// <LIBRARY>

