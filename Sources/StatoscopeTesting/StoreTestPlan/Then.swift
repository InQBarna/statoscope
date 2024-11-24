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

    @discardableResult
    public func THEN(
        _ checker: @escaping (_ sut: T) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            try checker(sut)
        }
    }

    @discardableResult
    public func THEN<S>(
        _ keyPath: KeyPath<T, S> = \T.self,
        checker: @escaping (_ sut: S) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            let childScope = sut[keyPath: keyPath]
            try checker(childScope)
        }
    }

    @discardableResult
    public func THEN<AcceptableKP: Equatable>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP>,
        equals expectedValue: AcceptableKP
    ) throws -> Self {
        addStep { sut in
            if sut[keyPath: keyPath] != expectedValue {
                XCTFail("[\(keyPath): '\(sut[keyPath: keyPath])' != '\(expectedValue)']", file: file, line: line)
            }
        }
    }

    @discardableResult
    public func THEN_NotNil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP?>
    ) throws -> Self {
        addStep { sut in
            XCTAssertNotNil(sut[keyPath: keyPath], file: file, line: line)
        }
    }

    @discardableResult
    public func THEN_Nil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP?>
    ) throws -> Self {
        addStep { sut in
            XCTAssertNil(sut[keyPath: keyPath], file: file, line: line)
        }
    }

}
