//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope
import XCTest

extension StoreTestPlan {

    @discardableResult
    public func WHEN(file: StaticString = #file, line: UInt = #line, _ whens: T.When...) throws -> Self {
        addStep { sut in
            // assertNoDeepEffects(file: file, line: line)
            try whens.forEach {
                sut.effectsState.reset()
                try sut.sendUnsafe($0)
            }
        }
    }

    @discardableResult
    public func WHEN<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.StoreState, Subscope>,
                                              file: StaticString = #file, line: UInt = #line,
                                              _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            try sut.when(childScope: sut._storeState[keyPath: keyPath], file: file, line: line, whens)
        }
    }

    @discardableResult
    public func WHEN<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.StoreState, Subscope?>,
                                              file: StaticString = #file, line: UInt = #line,
                                              _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            guard let childScope = sut._storeState[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            try sut.when(childScope: childScope, file: file, line: line, whens)
        }
    }
    
    @discardableResult
    public func throwsWHEN(file: StaticString = #file, line: UInt = #line, _ when: T.When) -> Self {
        addStep { sut in
            // assertNoDeepEffects(file: file, line: line)
            sut.effectsState.reset()
            XCTAssertThrowsError(try sut.sendUnsafe(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.StoreState, Subscope>,
                                                    file: StaticString = #file, line: UInt = #line,
                                                    _ when: Subscope.When) throws -> Self {
        addStep { sut in
            sut.effectsState.reset()
            XCTAssertThrowsError(try sut._storeState[keyPath: keyPath].sendUnsafe(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.StoreState, Subscope?>,
                                                    file: StaticString = #file, line: UInt = #line,
                                                    _ when: Subscope.When) throws -> Self {
        addStep { sut in
            guard let childScope = sut._storeState[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            XCTAssertThrowsError(try childScope.sendUnsafe(when), file: file, line: line)
        }
    }
}

extension StoreTestPlan {

    @discardableResult
    public func AND(file: StaticString = #file, line: UInt = #line, _ whens: T.When...) throws -> Self {
        addStep { sut in
            try whens.forEach {
                try sut.sendUnsafe($0)
            }
        }
    }

    @discardableResult
    public func AND<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.StoreState, Subscope>,
                                             file: StaticString = #file, line: UInt = #line,
                                             _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            try sut.when(childScope: sut._storeState[keyPath: keyPath], file: file, line: line, whens)
        }
    }

    @discardableResult
    public func AND<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.StoreState, Subscope?>,
                                             file: StaticString = #file, line: UInt = #line,
                                             _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            guard let childScope = sut._storeState[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            try sut.when(childScope: childScope, file: file, line: line, whens)
        }
    }
}
