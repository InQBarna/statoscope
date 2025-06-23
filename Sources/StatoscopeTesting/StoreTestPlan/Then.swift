//
//  Then.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import XCTest
import Statoscope

extension StoreTestPlan {

    internal func addThenStep(_ step: @escaping (T) throws -> Void) -> Self {
        addStep(Step(type: .then, run: step))
    }

    @discardableResult
    public func THEN(
        _ checker: @escaping (_ sut: T) throws -> Void
    ) rethrows -> Self {
        addThenStep { sut in
            try checker(sut)
        }
    }

    @discardableResult
    public func THEN<S>(
        _ keyPath: KeyPath<T, S> = \T.self,
        checker: @escaping (_ sut: S) throws -> Void
    ) rethrows -> Self {
        addThenStep { sut in
            let childScope = sut[keyPath: keyPath]
            try checker(childScope)
        }
    }

    @discardableResult
    public func THEN<S>(
        _ keyPath: KeyPath<T, S?>,
        file: StaticString = #file, line: UInt = #line,
        checker: @escaping (_ sut: S) throws -> Void
    ) rethrows -> Self {
        addThenStep { sut in
            guard let unwrapped = sut[keyPath: keyPath] else {
                XCTFail("THEN: Error unwrapping optional property" +
                        " \(keyPath) : \(type(of: S.self))",
                        file: file, line: line)
                return
            }
            try checker(unwrapped)
        }
    }

    @discardableResult
    public func THEN<AcceptableKP: Equatable>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP>,
        equals expectedValue: AcceptableKP
    ) throws -> Self {
        addThenStep { sut in
            if sut[keyPath: keyPath] != expectedValue {
                // TODO: decide whether to use equalDiff or just !=
                XCTFail(
                    "[\(keyPath): \n" + (
                        try equalDiff(expected: expectedValue, asserted: sut[keyPath: keyPath])
                    ) + "\n]",
                    file: file,
                    line: line
                )
                // XCTFail("[\(keyPath): '\(sut[keyPath: keyPath])' != '\(expectedValue)']", file: file, line: line)
            }
        }
    }

    @discardableResult
    public func THEN_NotNil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP?>
    ) throws -> Self {
        addThenStep { sut in
            XCTAssertNotNil(sut[keyPath: keyPath], file: file, line: line)
        }
    }

    @discardableResult
    public func THEN_Nil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP?>
    ) throws -> Self {
        addThenStep { sut in
            XCTAssertNil(sut[keyPath: keyPath], file: file, line: line)
        }
    }

}
