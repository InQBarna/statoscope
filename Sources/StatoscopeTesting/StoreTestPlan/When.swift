//
//  When.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
@_spi(SCT) import Statoscope
import XCTest

public enum ClearEffects {
    case all
    case allOnCurrentScope
    case none
    case some((any Effect) -> Bool)
    case someInCurrentAndSubscopes((any Effect, any ScopeImplementation) -> Bool)
}

extension ScopeImplementation {
    func clear(_ clearEffects: ClearEffects, scope: any ScopeImplementation) {
        effectsState.clear(clearEffects, scope: self)
    }
}

extension EffectsState {
    mutating func clear(_ clearEffects: ClearEffects, scope: any ScopeImplementation) {
        switch clearEffects {
        case .none:
            return
        case .all:
            reset(scope: scope)
            scope._allChildScopes().forEach { subscope in
                subscope.clear(.allOnCurrentScope, scope: subscope)
            }
        case .allOnCurrentScope:
            reset(scope: scope)
        case .some(let filter):
            reset(clearing: { effect, _ in filter(effect) }, scope: scope)
        case .someInCurrentAndSubscopes(let filter):
            reset(clearing: filter, scope: scope)
            scope._allChildScopes().forEach { subscope in
                subscope.clear(.some({ filter($0, subscope) }), scope: subscope)
            }
        }
    }
}

extension StoreTestPlan {

    internal func addWhenStep(_ description: String? = nil, _ step: @escaping (T) throws -> Void) -> Self {
        addStep(Step(type: .when(description), run: step))
    }

    @discardableResult
    public func WHEN(
        _ when: T.When
    ) throws -> Self {
        try privateWHEN(when)
    }

    @discardableResult
    public func WHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(keyPath, when, file: file, line: line)
    }

    @discardableResult
    public func WHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(keyPath, when, file: file, line: line)
    }

    @discardableResult
    public func throwsWHEN(
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ when: T.When
    ) -> Self {
        addWhenStep { sut in
            sut.effectsState.clear(clearEffects, scope: sut)
            XCTAssertThrowsError(try sut._unsafeSendImplementation(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ when: Subscope.When
    ) throws -> Self {
        addWhenStep { sut in
            sut.effectsState.clear(clearEffects, scope: sut)
            XCTAssertThrowsError(try sut[keyPath: keyPath]._unsafeSendImplementation(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ when: Subscope.When
    ) throws -> Self {
        addWhenStep { sut in
            guard let childScope = sut[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            childScope.effectsState.clear(clearEffects, scope: sut)
            XCTAssertThrowsError(try childScope._unsafeSendImplementation(when), file: file, line: line)
        }
    }
}

extension StoreTestPlan {

    @discardableResult
    public func AND(_ when: T.When) throws -> Self {
        try privateWHEN(when)
    }

    @discardableResult
    public func AND<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(keyPath, when, file: file, line: line)
    }

    @discardableResult
    public func AND<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(keyPath, when, file: file, line: line)
    }
}

private extension StoreTestPlan {

    func privateWHEN(
        _ when: T.When
    ) throws -> Self {
        addWhenStep { [clearEffectsOnWhen = self.clearEffectsOnWhen] sut in
            sut.effectsState.clear(clearEffectsOnWhen, scope: sut)
            try sut._unsafeSendImplementation(when)
        }
    }

    @discardableResult
    func privateWHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        addWhenStep(String(describing: when)) { [clearEffectsOnWhen = self.clearEffectsOnWhen] sut in
            let child = sut[keyPath: keyPath]
            child.effectsState.clear(clearEffectsOnWhen, scope: sut)
            try sut.when(childScope: child, file: file, line: line, [when])
        }
    }

    @discardableResult
    func privateWHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        addWhenStep(String(describing: when)) { [clearEffectsOnWhen = self.clearEffectsOnWhen] sut in
            guard let childScope = sut[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            childScope.effectsState.clear(clearEffectsOnWhen, scope: sut)
            try sut.when(childScope: childScope, file: file, line: line, [when])
        }
    }

}
