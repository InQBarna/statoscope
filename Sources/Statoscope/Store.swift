//
//  Store.swift
//  
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation

public protocol StoreProtocol {
    associatedtype ScopeType: Scope
    var scope: ScopeType { get }
    func send(_ when: ScopeType.When)
    func sendUnsafe(_ when: ScopeType.When) throws
}

public var scopeEffectsDisabledInUnitTests: Bool = nil != NSClassFromString("XCTest")
let scopeEffectsDisabledInPreviews: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

public extension StoreProtocol where ScopeType: AnyObject ,
    Self: AnyObject // TODO: se puede borrar ? lo necesitamos para liberar las tasks correctamente en deinit
{
    
    var logPrefix: String {
        "\(type(of: scope)) (\(Unmanaged.passUnretained(scope).toOpaque())): "
    }
    
    func LOG(_ string: String) {
        StatoscopeLogger.LOG(prefix: logPrefix, string)
    }
    
    func send(_ when: ScopeType.When) {
        LOG("\(when)")
        do {
            try sendUnsafe(when)
        } catch {
            LOG("‼️ Exception on send method: \(error)")
        }
    }
    
    func sendUnsafe(_ when: ScopeType.When) throws {
        try scope.updateUsingMiddlewares(when)
        guard !scopeEffectsDisabledInUnitTests else {
            return
        }
        guard !scopeEffectsDisabledInPreviews else {
            throw StatoscopeErrors.effectsDisabledForPreviews
        }
        try scope.runEnqueuedEffectAndGetWhenResults() { [weak self] effect, when in
            await self?.safeMainActorSend(effect, when)
        }
        return
    }
}

/// Part of the ``Statoscope`` protocol.
/// When conformed, an object automatcally provides
/// * public send method to forward When events to the store implementation
/// * public addMiddleware and synthesized properties to enable interception of messages
/// * conformance to EffectsHandlerImplementation to trigger effects with the 
extension StoreProtocol where ScopeType: AnyObject,
    Self: AnyObject // TODO: se puede borrar ?
{
    
    @MainActor
    fileprivate func safeMainActorSend(_ effect: AnyEffect<ScopeType.When>, _ when: ScopeType.When) {
        let count = scope.effectsHandler.effects.count
        if count > 0 {
            LOG("🪃 ↩ \(effect) (ongoing \(count)x🪃)")
        } else {
            LOG("🪃 ↩ \(effect)")
        }
        send(when)
    }
}


public protocol Statostore:
    Statoscope,
    StoreProtocol
    where ScopeType == Self
{ }

public extension Statostore {
    var scope: ScopeType { return self }
}


