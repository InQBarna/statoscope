//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation

// StoreProtocol will handle events by
//  1. synthesize an EffectsHandlerImplementation member instance to handle effects
private var effectsHandlerStoreKey: UInt8 = 0
extension StoreProtocol where Self: AnyObject {
    var effectsHandler: EffectsHandlerImplementation<When> {
        return associatedObject(base: self, key: &effectsHandlerStoreKey, initialiser: {
            EffectsHandlerImplementation<When>(logPrefix: logPrefix) { [weak self] uuid, effect, when in
                self?.completedEffect(uuid, effect, when)
            }
        })
    }
}

//  2. synthesize a DeinitObserver member instance
private var deinitObserverStoreKey: UInt8 = 0
private class DeinitObserver {
    let execute: () -> Void
    init(execute: @escaping () -> Void) {
        self.execute = execute
    }
    deinit {
        execute()
    }
}

internal extension StoreProtocol where Self: AnyObject {
    fileprivate var deinitObserver: DeinitObserver? {
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
                guard let handler else { return }
                Task {
                    await handler.cancelAllEffects()
                }
            }
        }
    }
}

private class AssociatedValue<T> {
    var value: T
    init(value: T) {
        self.value = value
    }
}

private var effectsStateStoreKey: UInt8 = 0
extension StoreProtocol where Self: AnyObject {
    public var effectsState: EffectsState<Self.When> {
        get {
            associatedObject(base: self, key: &effectsStateStoreKey, initialiser: {
                AssociatedValue(value: EffectsState<Self.When>(snapshotEffects: []))
            }).value
        }
        set {
            associatedObject(base: self, key: &effectsStateStoreKey, initialiser: {
                AssociatedValue(value: EffectsState<Self.When>(snapshotEffects: []))
            }).value = newValue
        }
    }
}
