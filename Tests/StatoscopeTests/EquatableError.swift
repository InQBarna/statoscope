//
//  EquatableError.swift
//
//
//  Created by Sergi Hernanz on 13/10/24.
//

import Foundation
@testable import Statoscope

struct EquatableError: Error, Equatable, CustomStringConvertible, LocalizedError {
    let base: Error
    private let equals: (Error) -> Bool

    init<Base: Error>(_ base: Base) {
        self.base = base
        self.equals = { String(reflecting: $0) == String(reflecting: base) }
    }

    init<Base: Error & Equatable>(_ base: Base) {
        self.base = base
        self.equals = { ($0 as? Base) == base }
    }

    static func ==(lhs: EquatableError, rhs: EquatableError) -> Bool {
        lhs.equals(rhs.base)
    }

    var description: String {
        "\(self.base)"
    }

    func asError<Base: Error>(type: Base.Type) -> Base? {
        self.base as? Base
    }

    var errorDescription: String? {
        return self.base.localizedDescription
    }
}

extension Error {
    func toEquatableError() -> EquatableError {
        if let selfEquatable = self as? EquatableError {
            return selfEquatable
        } else {
            return EquatableError(self)
        }
    }
}

extension Result {
    func toEquatableError() -> Result<Success, EquatableError> {
        mapError { error in
            error.toEquatableError()
        }
    }
}

struct UnknownEquatableError: Error { }

extension EquatableError: EffectError {
    static var unknownError: Self {
        UnknownEquatableError().toEquatableError()
    }
}
