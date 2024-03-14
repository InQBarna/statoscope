//
//  Store.swift
//  
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation

public protocol ScopeImplementation:
    EffectfullImplementation,
    AnyObject {
    associatedtype When

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
    func update(_ when: When) throws

    func addMiddleWare(_ update: @escaping (Self, When) throws -> When?) -> Self
}

public var scopeEffectsDisabledInUnitTests: Bool = nil != NSClassFromString("XCTest")
let scopeEffectsDisabledInPreviews: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

extension ScopeImplementation {

    @discardableResult
    func _scopeSend(_ when: When) -> Self {
        do {
            return try _scopeSendUnsafe(when)
        } catch {
            LOG(.errors, "‼️ Exception on send method: \(error)")
            return self
        }
    }

    @discardableResult
    public func _scopeSendUnsafe(_ when: When) throws -> Self {

        // For Statoscope, we store the snapshot in effectsHandler
        //  during update process
        LOG(.when, "\(when)")
        assert(effectsState.enquedEffects.count == 0)
        assert(effectsState.cancelledEffects.count == 0)
        let currentState = String(describing: self)
        for stateLine in currentState.split(separator: "\n") {
            LOG(.state, "[STATE] " + stateLine)
        }
        try updateUsingMiddlewares(when)
        let newState = String(describing: self)
        for stateLine in newState.split(separator: "\n") {
            LOG(.state, "[STATE] " + stateLine)
        }
        let differences = newState.split(separator: "\n").difference(from: currentState.split(separator: "\n"))
        for difference in differences {
            switch difference {
            case .remove(_, let element, _):
                LOG(.stateDiff, "[STATE] [DIFF] - " + element)
            case .insert(_, let element, _):
                LOG(.stateDiff, "[STATE] [DIFF] + " + element)
            }
        }
        let copiedSnapshot = effectsState
        effectsState = EffectsState(snapshotEffects: effectsState.currentRequestedEffects)
        ensureSetupDeinitObserver()
        Task { [weak self] in
            try await self?.effectsHandler.triggerNewEffectsState(newSnapshot: copiedSnapshot)
        }
        return self
    }

    private func LOG(_ level: LogLevel, _ string: String) {
        StatoscopeLogger.LOG(level, prefix: logPrefix, string)
    }

    private var logPrefix: String {
        "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
    }

    private func updateUsingMiddlewares(_ when: When) throws {
        if let middleware = middleWare {
            guard let mappedWhen = try middleware.middleWare(self, when) else {
                return
            }
            try update(mappedWhen)
        } else {
            try update(when)
        }
    }

    public func _completedEffect(_ uuid: UUID, _ effect: AnyEffect<When>, _ when: When?) {
        if let when {
            Task {
                let newEffects = effectsState.currentRequestedEffects.filter { $0.0 != uuid }
                effectsState = EffectsState(snapshotEffects: newEffects)
                await safeMainActorSend(effect, when)
            }
        }
    }

    @MainActor
    func safeMainActorSend(_ effect: AnyEffect<When>, _ when: When) {
        let count = effects.count
        if count > 0 {
            LOG(.effects, "🪃 ↩ \(effect) (ongoing \(count)x🪃)")
        } else {
            LOG(.effects, "🪃 ↩ \(effect)")
        }
        _scopeSend(when)
    }

    internal func resetEffects() {
        effectsState.reset()
    }
}

private var middleWareHandlerStoreKey: UInt8 = 0
private final class MiddleWareHandler<S: ScopeImplementation> {
    let middleWare: ((S, S.When) throws -> S.When?)
    init(middleWare: @escaping (S, S.When) throws -> S.When?) {
        self.middleWare = middleWare
    }
}

extension ScopeImplementation {

    public func addMiddleWare(_ update: @escaping (Self, When) throws -> When?) -> Self {
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
