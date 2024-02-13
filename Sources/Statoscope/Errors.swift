//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 19/1/24.
//

import Foundation

/// Error to be thrown in an update method when the received When event
/// should not be received given the current state
///
/// See:  ``StoreImplementation/update(state:when:effects:)``
public struct InvalidStateError: Error, Equatable {
    public init() {}
}

/// Error tthrown by the injection property wrappers.
///
/// It is catched internally, but should stop your debugger if Swift errors exception
/// breakpoint is enabled
///
/// See:  ``StoreImplementation/update(state:when:effects:)``
public struct NoInjectedValueFound: Error {
    let type: String
    let injectionTreeDescription: [String]?
    init<T>(_ type: T, injectionTreeDescription: [String]? = nil) {
        self.type = String(describing: type).removeOptionalDescription
        self.injectionTreeDescription = injectionTreeDescription
    }
    var debugDescription: String {
        let msg = "No injected value found: \"\(type)\""
        // Add keypath if possible ... at: \"\(keyPath ?? String(describing: type(of: self)))\"")
        return [[msg], injectionTreeDescription ?? []]
            .flatMap { $0 }
            .joined(separator: "\n")
    }
}

public enum StatoscopeErrors: Error {
    case effectsDisabledForPreviews
}

/// An error that can be thrown by an effect
///
/// See:  ``Effect/mapToResultWithErrorType(_:)``
public protocol EffectError: Error {
    /// The value an effect will return in case the mapping does not succeed
    static var unknownError: Self { get }
}
