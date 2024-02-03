//
//  Store.swift
//  
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation


/// Part of the ``Scope`` protocol. When adopted forces the implementation of the update method to mutate the store state
public protocol StoreImplementation {
    associatedtype When: Sendable
    func update(_ when: When) throws
}

/// Part of the ``Scope`` protocol. 
/// When conformed, an object automatcally provides
/// * public send method to forward When events to the store implementation
/// * public addMiddleware and synthesized properties to enable interception of messages
/// * conformance to EffectsHandlerImplementation to trigger effects with the 
public protocol Store: 
    EffectsHandlerImplementation,   // Capable of handle effects, TODO: should be private
    EffectsContainer,               // Expose effects functionality, TODO: should use effectsHandler
    StoreImplementation             // Forces conformed object to implement update()
{
    @discardableResult
    func send(_ when: When) -> Self
    @discardableResult
    func sendUnsafe(_ when: When) throws -> Self
    @discardableResult
    func addMiddleWare(_ update: @escaping (Self, When) throws -> When?) -> Self
}

extension Store where Self: AnyObject {

    var logPrefix: String {
        "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
    }

    func LOG(_ string: String) {
        StatoscopeLogger.LOG(prefix: logPrefix, string)
    }
}

extension Store where Self: AnyObject {

    @discardableResult
    public func send(_ when: When) -> Self {
        LOG("\(when)")
        do {
            return try sendUnsafe(when)
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

extension Store where Self: AnyObject {

    @discardableResult
    public func sendUnsafe(_ when: When) throws -> Self {
        if let middleware = middleWare {
            guard let mappedWhen = try middleware.middleWare(self, when) else {
                return self
            }
            try update(mappedWhen)
        } else {
            try update(when)
        }
        guard !scopeEffectsDisabledInUnitTests else {
            return self
        }
        guard !scopeEffectsDisabledInPreviews else {
            throw StatoscopeErrors.effectsDisabledForPreviews
        }
        try runEnqueuedEffectAndGetWhenResults() { [weak self] effect, when in
            await self?.safeMainActorSend(effect, when)
        }
        return self
    }
    
    @discardableResult
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
    
    @MainActor
    fileprivate func safeMainActorSend(_ effect: AnyEffect<When>, _ when: When) {
        let count = effectsHandler.effects.count
        if count > 0 {
            LOG("🪃 ↩ \(effect) (ongoing \(count)x🪃)")
        } else {
            LOG("🪃 ↩ \(effect)")
        }
        send(when)
    }
}

fileprivate var middleWareHandlerStoreKey: UInt8 = 0
fileprivate final class MiddleWareHandler<S: Store> {
    let middleWare: ((S, S.When) throws -> S.When?)
    init(middleWare: @escaping (S, S.When) throws -> S.When?) {
        self.middleWare = middleWare
    }
}

fileprivate extension Store where Self: AnyObject {
    var middleWare: MiddleWareHandler<Self>? {
        get {
            optionalAssociatedObject(base: self, key: &middleWareHandlerStoreKey, initialiser: { nil })
        }
        set {
            associateOptionalObject(base: self, key: &middleWareHandlerStoreKey, value: newValue)
        }
    }
}

/*
 Reducer: No longer provide store as EffectsContainer, force usage of effectsHandler ??
 */
public extension Store where Self: AnyObject {
    
    func enqueue<E: Effect>(_ effect: E) where E.ResType == When {
        effectsHandler.enqueue(effect)
    }
    
    var effects: [any Effect] {
        return effectsHandler.effects
    }
    
    func clearPending() {
        effectsHandler.clearPending()
    }
    
    func cancelEffect(where whereBlock: (any Effect) -> Bool) {
        effectsHandler.cancelEffect(where: whereBlock)
    }
    
    func cancelAllEffects() {
        effectsHandler.cancelAllEffects()
    }
    
}
