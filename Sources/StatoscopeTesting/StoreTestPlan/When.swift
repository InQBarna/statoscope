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
                sut.effectsHandler.cancelAllEffects()
                try sut.sendUnsafe($0)
            }
        }
    }

    @discardableResult
    public func WHEN<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.State, Subscope>,
                                              file: StaticString = #file, line: UInt = #line,
                                              _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            try sut.when(childScope: sut.state[keyPath: keyPath], file: file, line: line, whens)
        }
    }

    @discardableResult
    public func WHEN<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.State, Subscope?>,
                                              file: StaticString = #file, line: UInt = #line,
                                              _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            guard let childScope = sut.state[keyPath: keyPath] else {
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
            sut.cancelAllEffects()
            XCTAssertThrowsError(try sut.sendUnsafe(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.State, Subscope>,
                                                    file: StaticString = #file, line: UInt = #line,
                                                    _ when: Subscope.When) throws -> Self {
        addStep { sut in
            sut.cancelAllEffects()
            XCTAssertThrowsError(try sut.state[keyPath: keyPath].sendUnsafe(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.State, Subscope?>,
                                                    file: StaticString = #file, line: UInt = #line,
                                                    _ when: Subscope.When) throws -> Self {
        addStep { sut in
            guard let childScope = sut.state[keyPath: keyPath] else {
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
    public func AND<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.State, Subscope>,
                                             file: StaticString = #file, line: UInt = #line,
                                             _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            try sut.when(childScope: sut.state[keyPath: keyPath], file: file, line: line, whens)
        }
    }

    @discardableResult
    public func AND<Subscope: StoreProtocol>(_ keyPath: KeyPath<T.State, Subscope?>,
                                             file: StaticString = #file, line: UInt = #line,
                                             _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            guard let childScope = sut.state[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            try sut.when(childScope: childScope, file: file, line: line, whens)
        }
    }
}
