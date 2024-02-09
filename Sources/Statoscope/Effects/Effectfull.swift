//
//  EffectsContainer.swift
//  
//
//  Created by Sergi Hernanz on 28/1/24.
//

import Foundation

/// An object that handles or controls a group of effects
public protocol Effectfull {
    /// Returns currently pending or ongoing effects
    var effects: [any Effect] { get }
}
