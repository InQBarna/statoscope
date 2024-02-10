//
//  Store.swift
//  
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation

public protocol StoreImplementation:
    AnyObject {
    associatedtype When
    associatedtype State: Scope where State.When == When
    var state: State { get }
    static func update(state: State, when: State.When, effects: inout EffectsState<State.When>) throws
    func addMiddleWare(_ update: @escaping (State, State.When) throws -> State.When?) -> Self
}

public protocol StorePublicProtocol:
    Effectfull
{
    associatedtype State: Scope
    var state: State { get }
    @discardableResult
    func send(_ when: State.When) -> Self
    @discardableResult
    func sendUnsafe(_ when: State.When) throws -> Self
}

/// The StoreProtocol defines the implementation of an scope of the app's state and business logic
///
/// It is made up of 2 different protocols
/// * StorePublicProtocol: meant for Views that should only read the state and send When events
/// * StoreImplementation: meant for developer's implementation logic
public protocol StoreProtocol:
    StorePublicProtocol,
    StoreImplementation { }

public var scopeEffectsDisabledInUnitTests: Bool = nil != NSClassFromString("XCTest")
let scopeEffectsDisabledInPreviews: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

extension StoreProtocol {
    
    @discardableResult
    public func send(_ when: State.When) -> Self {
        LOG("\(when)")
        do {
            return try sendUnsafe(when)
        } catch {
            LOG("‼️ Exception on send method: \(error)")
            return self
        }
    }

    @discardableResult
    public func sendUnsafe(_ when: State.When) throws -> Self {
        
        // For Statoscope, we store the snapshot in effectsHandler
        //  during update process
        var snapshot = effectsState
        try updateUsingMiddlewares(when, effects: &snapshot)
        let newEffects = try runEnqueuedEffectAndGetWhenResults(newSnapshot: snapshot) { [weak self] effect, when, newEffectsState in
            self?.effectsState = EffectsState(snapshotEffects: newEffectsState)
            if let when {
                await self?.safeMainActorSend(effect, when)
            }
        }
        effectsState = EffectsState(snapshotEffects: newEffects)
        return self
    }

    var logPrefix: String {
        "\(type(of: state)) (\(Unmanaged.passUnretained(state).toOpaque())): "
    }

    private func LOG(_ string: String) {
        StatoscopeLogger.LOG(prefix: logPrefix, string)
    }

    private func updateUsingMiddlewares(_ when: State.When, effects: inout EffectsState<When>) throws {
        if let middleware = middleWare {
            guard let mappedWhen = try middleware.middleWare(self.state, when) else {
                return
            }
            try Self.update(state: state, when: mappedWhen, effects: &effects)
        } else {
            try Self.update(state: state, when: when, effects: &effects)
        }
    }

    @MainActor
    private func safeMainActorSend(_ effect: AnyEffect<State.When>, _ when: State.When) {
        let count = effects.count
        if count > 0 {
            LOG("🪃 ↩ \(effect) (ongoing \(count)x🪃)")
        } else {
            LOG("🪃 ↩ \(effect)")
        }
        send(when)
    }
    
    // TODO: Make it only available to StatoscopeTesting
    public func privateCancelAllEffects() {
        effectsHandler.cancelAllEffects()
    }
}

private var middleWareHandlerStoreKey: UInt8 = 0
private final class MiddleWareHandler<S: StoreImplementation> {
    let middleWare: ((S.State, S.When) throws -> S.When?)
    init(middleWare: @escaping (S.State, S.When) throws -> S.When?) {
        self.middleWare = middleWare
    }
}

extension StoreImplementation {

    public func addMiddleWare(_ update: @escaping (State, State.When) throws -> State.When?) -> Self {
        if let existingMiddleware = middleWare {
            middleWare = MiddleWareHandler(middleWare: { state, when in
                guard let mappedWhen = try update(state, when) else {
                    return nil
                }
                return try existingMiddleware.middleWare(state, mappedWhen)
            })
        } else {
            middleWare = MiddleWareHandler(middleWare: update)
        }
        return self
    }

    fileprivate var middleWare: MiddleWareHandler<Self>? {
        get {
            optionalAssociatedObject(base: self, key: &middleWareHandlerStoreKey, initialiser: { nil })
        }
        set {
            associateOptionalObject(base: self, key: &middleWareHandlerStoreKey, value: newValue)
        }
    }
    
}
