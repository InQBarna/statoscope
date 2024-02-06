//
//  Store.swift
//  
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation

public protocol StoreImplementation:
    EffectsHandlerImplementation,
    AnyObject {
    associatedtype State: Scope where State.When == When
    var state: State { get }
    static func update(state: State, when: State.When, effectsHandler: EffectsHandler<State.When>) throws
    func addMiddleWare(_ update: @escaping (State, State.When) throws -> State.When?)
}

public protocol StorePublicProtocol {
    associatedtype State: Scope
    var state: State { get }
    func send(_ when: State.When)
    func sendUnsafe(_ when: State.When) throws
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

    public func send(_ when: State.When) {
        LOG("\(when)")
        do {
            try sendUnsafe(when)
        } catch {
            LOG("‼️ Exception on send method: \(error)")
        }
    }

    public func sendUnsafe(_ when: State.When) throws {
        try updateUsingMiddlewares(when)
        guard !scopeEffectsDisabledInUnitTests else {
            return
        }
        guard !scopeEffectsDisabledInPreviews else {
            throw StatoscopeErrors.effectsDisabledForPreviews
        }
        try self.runEnqueuedEffectAndGetWhenResults { [weak self] effect, when in
            await self?.safeMainActorSend(effect, when)
        }
        return
    }

    private var logPrefix: String {
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
            try Self.update(state: state, when: mappedWhen, effectsHandler: effectsHandler)
        } else {
            try Self.update(state: state, when: when, effectsHandler: effectsHandler)
        }
    }

    @MainActor
    private func safeMainActorSend(_ effect: AnyEffect<State.When>, _ when: State.When) {
        let count = effectsHandler.effects.count
        if count > 0 {
            LOG("🪃 ↩ \(effect) (ongoing \(count)x🪃)")
        } else {
            LOG("🪃 ↩ \(effect)")
        }
        send(when)
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

    public func addMiddleWare(_ update: @escaping (State, State.When) throws -> State.When?) {
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
