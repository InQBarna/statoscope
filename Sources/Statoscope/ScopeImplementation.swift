//
//  ScopeImplementation.swift
//
//
//  Created by Sergi Hernanz on 2/2/24.
//

import Foundation

public protocol ScopeImplementation:
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
    @_spi(Internal) func update(_ when: When) throws

    @discardableResult
    func addMiddleWare(_ update: @escaping (Self, When, (When) throws -> Void) throws -> Void) -> Self
}

extension ScopeImplementation {

    public func _sendImplementation(_ when: When) {
        do {
            if shouldUseParentEnclosedHierarchialUpdate() {
                try callParentEnclosedHierarchialUpdate(when)
            } else {
                try _unsafeSendImplementation(when)
            }
        } catch {
            LOG(.errors, "‼️ Exception on send method: \(error)")
        }
    }

    @_transparent
    private func logStateAndDiffIfEnabled(_ _updateUsingMiddlewares: () throws -> Void) rethrows {
        if StatoscopeLogger.logEnabled(.stateDiff) {
            let currentState = String(describing: self)
            LOG(.state, currentState)
            try _updateUsingMiddlewares()
            let newState = String(describing: self)
            LOG(.state, newState)
            logStateDiff(previousDescribingSelf: currentState, newDescribingSelf: newState)
        } else {
            LOG(.state, describing: self)
            try _updateUsingMiddlewares()
            LOG(.state, describing: self)
        }
    }

    public func _unsafeSendImplementation(_ when: When) throws {

        // For Statoscope, we store the snapshot in effectsHandler
        //  during update process
        LOG(.when, describing: when)
        assert(effectsState.enquedEffects.count == 0)
        assert(effectsState.cancelledEffects.count == 0)
        effectsState._updating = true
        try logStateAndDiffIfEnabled {
            try updateUsingMiddlewares(when)
        }
        effectsState._updating = false
        let copiedSnapshot = effectsState
        effectsState = EffectsState(snapshotEffects: effectsState.currentRequestedEffects)
        ensureSetupDeinitObserver()
        let injectionTreenode = self as? InjectionTreeNode
        if nil == injectionTreenode {
            LOG(.errors, "‼️ InjectionTreeNode not found for effects")
        }
        Task { [weak self] in
            try await self?.effectsHandler.triggerNewEffectsState(
                newSnapshot: copiedSnapshot,
                injectionTreeNode: self as? InjectionTreeNode
            )
        }
    }

    @inline(__always)
    internal func LOG(_ level: LogLevel, describing: Any) {
        StatoscopeLogger.LOG(level, prefix: logPrefix, describing: describing)
    }

    @inline(__always)
    internal func LOG(_ level: LogLevel, _ string: String) {
        StatoscopeLogger.LOG(level, prefix: logPrefix, string)
    }

    private var logPrefix: String {
        "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())):"
    }

    public func _completedEffect(_ uuid: UInt, _ effect: AnyEffect<When>, _ when: When?) {
        if let when {
            Task {
                let newEffects = effectsState.currentRequestedEffects.filter { $0.0 != uuid }
                effectsState = EffectsState(snapshotEffects: newEffects)
                await safeMainActorSend(uuid, effect, when)
            }
        }
    }

    @MainActor
    private func safeMainActorSend(_ uuid: UInt, _ effect: AnyEffect<When>, _ when: When) {
        let count = effects.count
        if count > 0 {
            LOG(.effects, "🪃 ↩ [\(uuid)] (x\(count))\t\(describeObject(effect))")
        } else {
            LOG(.effects, "🪃 ↩ [\(uuid)]\t\(describeObject(effect))")
        }
        _sendImplementation(when)
    }

    internal func resetEffects() {
        effectsState.reset(scope: self)
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

    @discardableResult
    public func addMiddleWare(_ update: @escaping (Self, When, (When) throws -> Void) throws -> Void) -> Self {
        if let existingMiddleware = middleWare {
            middleWare = MiddleWareHandler(middleWare: { state, when, updateClosure in
                try update(state, when) { mappedWhen in
                    try existingMiddleware.middleWare(state, mappedWhen, updateClosure)
                }
            })
        } else {
            middleWare = MiddleWareHandler(middleWare: update)
        }
        return self
    }

    private var middleWare: MiddleWareHandler<Self>? {
        get {
            optionalAssociatedObject(base: self, key: &middleWareHandlerStoreKey, initialiser: { nil })
        }
        set {
            associateOptionalObject(base: self, key: &middleWareHandlerStoreKey, value: newValue)
        }
    }

    @inline(__always)
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
    /// It can enforce, filter or enclose events like a middleware
    ///
    /// * Parameter child: the child scope sending the event
    /// * Parameter when: the event from the child scope
    /// * Parameter keyPath: the keypath from parent to child
    func updateSubscope<Child: ScopeImplementation>(
        _ child: Child,
        _ when: Child.When,
        _ keyPath: AnyKeyPath
    ) throws
}

private extension ScopeImplementation {

    func firstHierarchialScopeMiddlewareParent() -> HierarchialScopeMiddleWare? {
        var iterator: InjectionTreeNodeProtocol? = self as? InjectionTreeNodeProtocol
        while iterator != nil {
            if let iteratorIsHierarchialMiddleware = iterator as? HierarchialScopeMiddleWare {
                return iteratorIsHierarchialMiddleware
            }
            iterator = iterator?._parentNode
        }
        return nil
    }

    @inline(__always)
    func shouldUseParentEnclosedHierarchialUpdate() -> Bool {
        return firstHierarchialScopeMiddlewareParent() != nil
    }

    @inline(__always)
    func callParentEnclosedHierarchialUpdate(_ when: When) throws {
        guard let parent = firstHierarchialScopeMiddlewareParent(),
              let selfAsInjectionNode = self as? InjectionTreeNode else {
            return
        }
        /// this is an internal method so it should be safe if retaining some scopes
        let selfKeyPathOnParent = selfAsInjectionNode._keyPathToSelfOnParent ?? \Self.self
        // Direct call - no closure allocation!
        try parent.updateSubscope(self, when, selfKeyPathOnParent)
    }
}
