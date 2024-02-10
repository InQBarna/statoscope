//
//  EffectsContainer.swift
//  
//
//  Created by Sergi Hernanz on 28/1/24.
//

import Foundation

/// An object that handles or controls a group of effects
public protocol Effectfull {
    /// The shared type returned by the group of effects
    associatedtype When
    /// Returns currently pending or ongoing effects
    var effectsState: EffectsState<When> { get }
}

extension Effectfull {
    public var effects: [any Effect] {
        effectsState.effects
    }
}
