//
//  Statetoscope.swift
//  familymealplan
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

public protocol Scope:
    EffectsHandlerImplementation
{
    associatedtype State: EffectsContainer & InjectionTreeNode
    associatedtype When
    var state: State { get }
    static func update(state: State, when: When, effectsHandler: EffectsHandler<When>) throws
    func addMiddleWare(_ update: @escaping (Self, When) throws -> When?)
}

fileprivate var middleWareHandlerStoreKey: UInt8 = 0
fileprivate final class MiddleWareHandler<S: Scope> {
    let middleWare: ((S, S.When) throws -> S.When?)
    init(middleWare: @escaping (S, S.When) throws -> S.When?) {
        self.middleWare = middleWare
    }
}

extension Scope where Self: AnyObject {
    
    public func addMiddleWare(_ update: @escaping (Self, When) throws -> When?) {
        if let existingMiddleware = middleWare {
            middleWare = MiddleWareHandler(middleWare: { scope, when in
                guard let mappedWhen = try update(scope, when) else {
                    return nil
                }
                return try existingMiddleware.middleWare(scope, mappedWhen)
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
    
    internal func updateUsingMiddlewares(_ when: When) throws {
        if let middleware = middleWare {
            guard let mappedWhen = try middleware.middleWare(self, when) else {
                return
            }
            try Self.update(state: state, when: mappedWhen, effectsHandler: effectsHandler)
        } else {
            try Self.update(state: state, when: when, effectsHandler: effectsHandler)
        }
    }
}

/// Part of the ``Statoscope`` protocol. When adopted forces the implementation of the update method to mutate the store state
public protocol NaiveReducer {
    associatedtype When: Sendable
    func update(_ when: When) throws
}

/// Protocol to provide conformance to many aspects of the statoscope architecture
///
/// * Store: provides a public interface to receive When events via the  send method, and a default implementation to handle this events
/// * NaiveReducer: forces conformed classes to implement the update method to mutate the scope state
/// * EffectsContainer: provides public interface to enqueue and handle Effects, and the default implementation
/// * InjectionTreeNode: provides public interface to manage dependency injection, and the default implementation for injects and resolve methods
public protocol Statoscope:
    Scope,
    EffectsContainer,               // Public interface to dispatch effect + default forwarding and implementation
    InjectionTreeNode,              // Public interface for dependency injection and retrieval
    
        // includes EffectsHandlerImplementation:apable of handle effects
    NaiveReducer,                   // Forces inheriting class to implement the update business logic
    AnyObject
    where Self == State
{
}

extension Statoscope {
    
    static public func update(state: State, when: When, effectsHandler: EffectsHandler<When>) throws {
        try state.update(when)
    }
    
    public var state: State {
        return self
    }
    
    public func set<T>(_ keyPath: ReferenceWritableKeyPath<Self, T>, _ value: T) -> Self {
        self[keyPath: keyPath] = value
        return self
    }
}

// <LIBRARY>
// Reducer: this is a baseline approach to separate state and store
/*
public protocol StatoscopeProtocol {
    associatedtype State
    func state() -> State
}

public protocol StatoscopeImplementation: Statostore {
    associatedtype MutableState
    func mutableState() -> MutableState
    static func update(state: MutableState, when: When, effects: EffectsHandler<Self.When>) throws
}

protocol Statoscope: StatoscopeProtocol, StatoscopeImplementation { }

extension Statoscope {
    func update(_ when: When) throws {
        try Self.update(state: mutableState(), when: when, effects: effectsHandler)
    }
}
*/
