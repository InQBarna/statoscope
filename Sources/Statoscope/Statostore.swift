//
//  Statetoscope.swift
//  familymealplan
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// An Statostore is the Naive's solution to implement State + Store + Reducer combination
///
/// The same class-type object, may provide all features in
/// * State: Using member variables
/// * When: forcing definition
/// * NaiveReducer: forcing implementation of the update method
/// * InjectionTreeNode: Enabling communication with other statoscopes
public protocol Statostore:
    Scope,
    StoreProtocol
    where State == Self { }

public extension Statostore {

    var state: State {
        return self
    }

    func set<T>(_ keyPath: ReferenceWritableKeyPath<Self, T>, _ value: T) -> Self {
        self[keyPath: keyPath] = value
        return self
    }
}
