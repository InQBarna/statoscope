//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation

public extension EffectsHandlerImplementation where Self: AnyObject {
    
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
    
    func runEnqueuedEffectAndGetWhenResults(safeSend: @escaping (AnyEffect<When>, When) async -> Void) throws {
        ensureSetupDeinitObserver()
        try effectsHandler.runEnqueuedEffectAndGetWhenResults(safeSend: safeSend)
    }
}

fileprivate var effectsHandlerStoreKey: UInt8 = 0
internal extension EffectsHandlerImplementation where Self: AnyObject {
    
    var logPrefix: String {
        "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
    }
    
    var effectsHandler: EffectsHandler<When> {
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

fileprivate extension EffectsHandlerImplementation where Self: AnyObject {
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
                handler?.cancelAllEffects()
            }
        }
    }
}

