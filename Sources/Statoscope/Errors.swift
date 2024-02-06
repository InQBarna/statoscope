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

public protocol EffectError {
    static var unknownError: Self { get }
}
