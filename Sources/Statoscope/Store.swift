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
    
    /// The state handled by the store.
    ///
    /// The state object should implement the ``Scope`` protocol, providing
    /// * Usable inside injection tree
    /// * Member variables with the Scope's state
    var state: State { get }
    
    /// Implements the business logic for this scope of the state
    ///
    /// Method responsible or receiving the current State of your app's scope
    /// and transform it according to the received when. When necessary, effects
    /// can be enqueued, queried or cancelled using the provided EffectsState.
    ///  Runs allways on the main thread.
    ///
    /// * Parameter state: the current state of the scope
    /// * Parameter when: the received event
    /// * Parameter effects: an EffectsState object to enqueue, query or cancel effects
    func update(_ when: State.When) throws
    
    func addMiddleWare(_ update: @escaping (State, State.When) throws -> State.When?) -> Self
}

public protocol StorePublicProtocol:
    Effectfull
{
    associatedtype State: Scope
    
    /// The state handled by the store.
    ///
    /// The state object should implement the ``Scope`` protocol, providing
    /// * Usable inside injection tree
    /// * Member variables with the Scope's state
    var state: State { get }
    
    /// Public method to send events to the store
    ///
    /// Usually UI or system notitications send messages to stores using a When case
    /// * Parameter when: the typed event case to send to the store
    @discardableResult
    func send(_ when: State.When) -> Self
    
    /// Public method to send events to the store
    ///
    /// Usually UI or system notitications send messages to stores using a When case
    ///
    /// # Discussion
    /// Different from ``send(_:)`` because this method throws any unexpected
    /// exception. Use this method for debugging or unit testing
    ///
    /// * Parameter when: the typed event case to send to the store
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
        assert(effectsState.enquedEffects.count == 0)
        assert(effectsState.cancelledEffects.count == 0)
        try updateUsingMiddlewares(when)
        let copiedSnapshot = effectsState
        effectsState = EffectsState(snapshotEffects: effectsState.currentRequestedEffects)
        ensureSetupDeinitObserver()
        Task { [weak self] in
            try await self?.effectsHandler.triggerNewEffectsState(newSnapshot: copiedSnapshot)
        }
        return self
    }

    var logPrefix: String {
        "\(type(of: state)) (\(Unmanaged.passUnretained(state).toOpaque())): "
    }

    private func LOG(_ string: String) {
        StatoscopeLogger.LOG(prefix: logPrefix, string)
    }

    private func updateUsingMiddlewares(_ when: State.When) throws {
        if let middleware = middleWare {
            guard let mappedWhen = try middleware.middleWare(self.state, when) else {
                return
            }
            try update(mappedWhen)
        } else {
            try update(when)
        }
    }
    
    func completedEffect(_ uuid: UUID, _ effect: AnyEffect<State.When>, _ when: State.When?) {
        if let when {
            Task {
                let newEffects = effectsState.currentRequestedEffects.filter { $0.0 != uuid }
                effectsState = EffectsState(snapshotEffects: newEffects)
                await safeMainActorSend(effect, when)
            }
        }
    }

    @MainActor
    func safeMainActorSend(_ effect: AnyEffect<State.When>, _ when: State.When) {
        let count = effects.count
        if count > 0 {
            LOG("🪃 ↩ \(effect) (ongoing \(count)x🪃)")
        } else {
            LOG("🪃 ↩ \(effect)")
        }
        send(when)
    }
    
    internal func resetEffects() {
        effectsState.reset()
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
