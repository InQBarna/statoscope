//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 19/1/24.
//

import Foundation

public struct InvalidStateError: Error {
    public init() {}
}

public struct NoInjectedValueFound: Error {
    let type: String
    init<T>(_ type: T) {
        self.type = String(describing: type).removeOptionalDescription
    }
}

public enum StatoscopeErrors: Error {
    case effectsDisabledForPreviews
}

public protocol EffectError {
    static var unknownError: Self { get }
}

