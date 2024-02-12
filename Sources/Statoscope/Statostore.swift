//
//  Statetoscope.swift
//  familymealplan
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

public protocol NaiveReducer {
    associatedtype When: Sendable
    func update(_ when: When) throws
}

/// An Statostore is the Naive's solution to implement State + Store + Reducer combination
///
/// The same class-type object, may provide all features in
/// * State: Using member variables
/// * When: forcing definition
/// * NaiveReducer: forcing implementation of the update method
/// * InjectionTreeNode: Enabling communication with other statoscopes
public protocol Statostore:
    Scope,
    NaiveReducer,
    StoreProtocol
    where State == Self { }

public extension Statostore {

    static func update(state: State, when: State.When, effects: inout EffectsState<State.When>) throws {
        // Passed effects are not used, but implementor will use self.effectsController to manage effects
        try state.update(when)
        effects = state.effectsState
    }

    var state: State {
        return self
    }

    func set<T>(_ keyPath: ReferenceWritableKeyPath<Self, T>, _ value: T) -> Self {
        self[keyPath: keyPath] = value
        return self
    }
}
