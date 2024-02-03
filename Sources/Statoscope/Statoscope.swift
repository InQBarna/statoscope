//
//  Statetoscope.swift
//  familymealplan
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// Protocol to provide conformance to many aspects of the statoscope architecture
///
/// * Store: provides a public interface to receive When events via the  send method, and a default implementation to handle this events
/// * StoreImplementation: forces conformed classes to implement the update method to mutate the scope state
/// * EffectsContainer: provides public interface to enqueue and handle Effects, and the default implementation
/// * InjectionTreeNode: provides public interface to manage dependency injection, and the default implementation for injects and resolve methods
public protocol Scope:
    Store                           // Public interface receiving When events + default dispatch implementation
    & StoreImplementation           // Forces inheriting class to implement the update business logic
    & EffectsContainer              // Public interface to dispatch effect + default forwarding and implementation
    & InjectionTreeNode             // Public interface for dependency injection and retrieval
    & AnyObject
{ }

extension Scope {
    public func set<T>(_ keyPath: ReferenceWritableKeyPath<Self, T>, _ value: T) -> Self {
        self[keyPath: keyPath] = value
        return self
    }
}

// <LIBRARY>
// Reducer: this is a baseline approach to separate state and store
public protocol StatoscopeProtocol {
    associatedtype State
    func state() -> State
}

public protocol StatoscopeImplementation: Scope {
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

@propertyWrapper
public class StateVar<Value> {
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    public var wrappedValue: Value
}
// <LIBRARY>

