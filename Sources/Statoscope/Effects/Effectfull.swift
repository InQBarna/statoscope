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
    associatedtype When: Sendable
    /// Returns currently pending or ongoing effects
    var effectsState: EffectsState<When> { get }
    /// Returns a prefix so this is identified in the logs
    var _logPrefix: String { get }
}

public protocol EffectfullImplementation: Effectfull {
    func _completedEffect(_ uuid: UUID, _ effect: AnyEffect<When>, _ when: When?)
}

extension Effectfull {
    public var effects: [any Effect] {
        effectsState.effects
    }
}

extension Effectfull where Self: AnyObject {
    public var _logPrefix: String {
        "\(type(of: self)) (\(Unmanaged.passUnretained(self).toOpaque())): "
    }
}
