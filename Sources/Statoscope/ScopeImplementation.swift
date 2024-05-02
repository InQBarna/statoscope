//
//  ScopeImplementation.swift
//
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation

public protocol ScopeImplementation:
    _AnyScopeImplementation,
    EffectfullImplementation,
    AnyObject {

    /// Implements the business logic for this scope of the state
    ///
    /// Method responsible of mutating the current State (properties of this same object)
    /// of your app's scope and transform it according to the received when. 
    /// When necessary, effects can be enqueued, queried or cancelled using the provided EffectsState.
    /// Runs allways on the main thread.
    ///
    /// * Parameter when: the received event
    func update(_ when: When) throws

    func addMiddleWare(_ update: @escaping (Self, When, (When) throws -> Void) throws -> Void)
}

extension ScopeImplementation {

    public func _sendImplementation(_ when: When) {
        do {
            if let parentEnclosedUpdateMethod = parentEnclosedHierarchialUpdateMethod(when) {
                try parentEnclosedUpdateMethod()
            } else {
                try _unsafeSendImplementation(when)
            }
        } catch {
            LOG(.errors, "‼️ Exception on send method: \(error)")
        }
    }

    public func _unsafeSendImplementation(_ when: When) throws {

        // For Statoscope, we store the snapshot in effectsHandler
        //  during update process
        LOG(.when, "\(when)")
        assert(effectsState.enquedEffects.count == 0)
        assert(effectsState.cancelledEffects.count == 0)
        let currentState = String(describing: self)
        logState(describingSelf: currentState)
        try updateUsingMiddlewares(when)
        let newState = String(describing: self)
        logState(describingSelf: newState)
        logStateDiff(previousDescribingSelf: currentState, newDescribingSelf: newState)
        let copiedSnapshot = effectsState
        effectsState = EffectsState(snapshotEffects: effectsState.currentRequestedEffects)
        ensureSetupDeinitObserver()
        Task { [weak self] in
            try await self?.effectsHandler.triggerNewEffectsState(newSnapshot: copiedSnapshot)
        }
    }

    internal func LOG(_ level: LogLevel, _ string: String) {
        StatoscopeLogger.LOG(level, prefix: logPrefix, string)
    }

    private var logPrefix: String {
        "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
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
    private func safeMainActorSend(_ effect: AnyEffect<When>, _ when: When) {
        let count = effects.count
        if count > 0 {
            LOG(.effects, "🪃 ↩ \(effect) (ongoing \(count)x🪃)")
        } else {
            LOG(.effects, "🪃 ↩ \(effect)")
        }
        _sendImplementation(when)
    }

    internal func resetEffects() {
        effectsState.reset()
    }
}

// MARK: Middleware functionality
private var middleWareHandlerStoreKey: UInt8 = 0
private final class MiddleWareHandler<S: ScopeImplementation> {
    let middleWare: ((S, S.When, (S.When) throws -> Void) throws -> Void)
    init(middleWare: @escaping (S, S.When, (S.When) throws -> Void) throws -> Void) {
        self.middleWare = middleWare
    }
}

extension ScopeImplementation {

    public func addMiddleWare(_ update: @escaping (Self, When, (When) throws -> Void) throws -> Void) {
        if let existingMiddleware = middleWare {
            middleWare = MiddleWareHandler(middleWare: { state, when, updateClosure in
                try update(state, when) { mappedWhen in
                    try existingMiddleware.middleWare(state, mappedWhen, updateClosure)
                }
            })
        } else {
            middleWare = MiddleWareHandler(middleWare: update)
        }
    }

    private var middleWare: MiddleWareHandler<Self>? {
        get {
            optionalAssociatedObject(base: self, key: &middleWareHandlerStoreKey, initialiser: { nil })
        }
        set {
            associateOptionalObject(base: self, key: &middleWareHandlerStoreKey, value: newValue)
        }
    }

    private func updateUsingMiddlewares(_ when: When) throws {
        if let middleware = middleWare {
            try middleware.middleWare(self, when) { mappedWhen in
                try update(mappedWhen)
            }
        } else {
            try update(when)
        }
    }
}

// MARK: HierarchyMiddleware functionality
public protocol HierarchialScopeMiddleWare {
    /// Intercepts the business logic for this scope and subscopes of the state
    ///
    /// Method responsible of enclosing the update method of this object's subscopes
    /// It can enforce, filer or enclose events like a middleware
    ///
    /// * Parameter whenFromSubscope: the received event
    func updateSubscope<SubWhen: Sendable>(_ whenFromSubscope: WhenFromSubscope<SubWhen>) throws
}

public struct WhenFromSubscope<When: Sendable> {
    public let subscopeKeyPath: AnyKeyPath
    public let subscope: () -> AnyScopeImplementation<When>
    public let when: When
}

public protocol _AnyScopeImplementation {
    associatedtype When: Sendable
    func _unsafeSendImplementation(_ when: When) throws
}

public struct AnyScopeImplementation<When: Sendable>: _AnyScopeImplementation {
    let scopeSendUnsafe: (When) throws -> Void
    public func _unsafeSendImplementation(_ when: When) throws {
        try scopeSendUnsafe(when)
    }
}

extension _AnyScopeImplementation {
    func eraseToAnyScopeImpl<AnyWhen: Sendable>() -> AnyScopeImplementation<AnyWhen>? {
        guard let scopeSendUnsafe = self._unsafeSendImplementation as? ((AnyWhen) throws -> Void) else {
            return nil
        }
        return AnyScopeImplementation(
            scopeSendUnsafe: scopeSendUnsafe
        )
    }
}

private extension ScopeImplementation {

    func firstHierarchialScopeMiddlewareParent() -> HierarchialScopeMiddleWare? {
        var iterator: InjectionTreeNodeProtocol? = self as? InjectionTreeNodeProtocol
        while iterator != nil {
            if let iteratorIsHierarchialMiddleware = iterator as? HierarchialScopeMiddleWare {
                return iteratorIsHierarchialMiddleware
            }
            iterator = iterator?.parentNode
        }
        return nil
    }

    func parentEnclosedHierarchialUpdateMethod(_ when: When) -> (() throws -> Void)? {
        guard let parent = firstHierarchialScopeMiddlewareParent(),
              let selfAsInjectionNode = self as? InjectionTreeNode,
              let erased: AnyScopeImplementation<When> = self.eraseToAnyScopeImpl() else {
            return nil
        }
        /// this is an internal method so it should be safe if retaining some scopes
        let selfKeyPathOnParent = selfAsInjectionNode.keyPathToSelfOnParent ?? \Self.self
        let whenFromSubscope = WhenFromSubscope(
            subscopeKeyPath: selfKeyPathOnParent,
            subscope: { erased },
            when: when
        )
        return {
            try parent.updateSubscope(whenFromSubscope)
        }
    }
}
