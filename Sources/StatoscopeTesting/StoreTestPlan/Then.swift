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
        file: StaticString = #file, line: UInt = #line,
        _ checker: @escaping (_ sut: T) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            try checker(sut)
            // assertNoDeepEffects(file: file, line: line)
            // sut.cancelAllEffects()
        }
    }

    @discardableResult
    public func THEN<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope>,
        file: StaticString = #file, line: UInt = #line,
        checker: @escaping (_ sut: Subscope) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            let childScope = sut._storeState[keyPath: keyPath]
            try checker(childScope)
            // childScope.assertNoDeepEffects(file: file, line: line)
            // childScope.cancelAllEffects() // only cleared on next WHEN
        }
    }
    @discardableResult
    public func THEN<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope?>,
        file: StaticString = #file, line: UInt = #line,
        checker: @escaping (_ sut: Subscope) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            guard let childScope = sut._storeState[keyPath: keyPath] else {
                XCTFail("THEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            try checker(childScope)
            // childScope.assertNoDeepEffects(file: file, line: line)
            // childScope.cancelAllEffects() // only cleared on next WHEN
        }
    }

    @discardableResult
    public func THEN<AcceptableKP: Equatable>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T.StoreState, AcceptableKP>,
        equals expectedValue: AcceptableKP
    ) throws -> Self {
        addStep { sut in
            XCTAssertEqual(sut._storeState[keyPath: keyPath], expectedValue, file: file, line: line)
            // assertNoDeepEffects(file: file, line: line)
            // sut.cancelAllEffects() // only cleared on next WHEN
        }
    }

    @discardableResult
    public func THEN_NotNil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T.StoreState, AcceptableKP>
    ) throws -> Self {
        addStep { sut in
            XCTAssertNotNil(sut._storeState[keyPath: keyPath], file: file, line: line)
            // assertNoDeepEffects(file: file, line: line)
            // sut.cancelAllEffects() // only cleared on next WHEN
        }
    }

    @discardableResult
    public func THEN_NotNil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T.StoreState, AcceptableKP?>
    ) throws -> Self {
        addStep { sut in
            XCTAssertNotNil(sut._storeState[keyPath: keyPath], file: file, line: line)
            // assertNoDeepEffects(file: file, line: line)
            // sut.cancelAllEffects() // only cleared on next WHEN
        }
    }

    @discardableResult
    public func THEN_Nil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T.StoreState, AcceptableKP?>
    ) throws -> Self {
        addStep { sut in
            XCTAssertNil(sut._storeState[keyPath: keyPath], file: file, line: line)
            // assertNoDeepEffects(file: file, line: line)
            // sut.cancelAllEffects() // only cleared on next WHEN
        }
    }

}
