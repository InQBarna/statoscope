//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation

// AnyObject conforming to EffectsHandlerImplementation will
//  1. synthesize an EffectsHandlerImpl member instance to handle effects
fileprivate var effectsHandlerStoreKey: UInt8 = 0
internal extension EffectsHandlerImplementation where Self: AnyObject {
    
    var logPrefix: String {
        "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
    }
}
    
public extension EffectsHandlerImplementation where Self: AnyObject {
    var effectsHandler: EffectsHandler<When> {
        get {
            return associatedObject(base: self, key: &effectsHandlerStoreKey, initialiser: {
                EffectsHandlerImpl<When>(logPrefix: logPrefix)
            })
        }
    }
}

//  2. synthesize a DeinitObserver member instance
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
}

//  3. provide a method runEnqueuedEffectAndGetWhenResults to rule the effectsHandler
internal extension EffectsHandlerImplementation where Self: AnyObject {
    
    func ensureSetupDeinitObserver() {
        if deinitObserver == nil {
            let handler = effectsHandler
            deinitObserver = DeinitObserver { [weak handler] in
                handler?.cancelAllEffects()
            }
        }
    }
}

// ... and ... Conform to InternalEffectsHandlerImplementation implicitly
extension EffectsHandlerImplementation where Self: AnyObject {
    func runEnqueuedEffectAndGetWhenResults(safeSend: @escaping (AnyEffect<When>, When) async -> Void) throws {
        ensureSetupDeinitObserver()
        guard let impl = effectsHandler as? EffectsHandlerImpl<When> else {
            // May have been overwritten to a spy for testing purposes ?
            return
        }
        try impl.runEnqueuedEffectAndGetWhenResults(safeSend: safeSend)
    }
}

