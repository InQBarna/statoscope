//
//  StoreTestPlan.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope
import XCTest

enum TestPlanErrors: Error {
    case unwrappingNonOptionalSubscope
}

public class StoreTestPlan<T: ScopeImplementation> {
    let given: () throws -> T
    internal var steps: [(T) throws -> Void] = []
    internal var forks: [StoreTestPlan<T>] = []
    internal var clearEffectsOnWhen: ClearEffects = .all
    func addStep(_ step: @escaping (T) throws -> Void) -> Self {
        steps.append(step)
        return self
    }

    public init(given: @escaping () throws -> T) {
        self.given = given
    }

    internal init(parent: StoreTestPlan<T>) {
        self.given = parent.given
        self.steps = parent.steps
    }

    internal init<FF: ScopeImplementation>(
        parent: StoreTestPlan<FF>,
        sut: FF,
        keyPath: KeyPath<FF, T>
    ) {
        self.given = { sut[keyPath: keyPath] }
        self.steps = []
    }

    /*
    internal init<FF: ScopeImplementation>(
        parent: StoreTestPlan<FF>,
        sut: FF,
        keyPath: KeyPath<FF, T?>,
        file: StaticString = #file, line: UInt = #line
    ) {
        self.given = {
            guard let childScope: T = sut[keyPath: keyPath] else {
                XCTFail("WITH: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: T.self))",
                        file: file, line: line)
                throw TestPlanErrors.unwrappingNonOptionalSubscope
            }
            return childScope
        }
        self.steps = []
    }
     */

    var snapshot: ((T) -> Void)?

    // Possible parameters
    //  1.- Taking screenshots
    //   1.1.- Record screenshots
    //  2.- Memory release check
    //  3.- Force check effects after every WHEN? WHEN is the "clear" trigger!
    //  4.- ?
    public func runTest(
        file: StaticString = #file, line: UInt = #line,
        assertRelease: Bool = false
    ) throws {
        try runAllSteps(file: file, line: line, assertRelease: assertRelease)
        try forks.forEach { childFlow in
            childFlow.snapshot = snapshot
            try childFlow.runTest(file: file, line: line, assertRelease: assertRelease)
        }
    }
    
    public func configure(clearEffects: ClearEffects) -> Self {
        self.clearEffectsOnWhen = clearEffects
        return self
    }

    private func runAllSteps(
        file: StaticString,
        line: UInt,
        assertRelease: Bool
    ) throws {
        if assertRelease {
            try assertChildScopesReleased(file: file, line: line) {
                try runAllSteps()
            }
        } else {
            _ = try runAllSteps()
        }
    }

    private func runAllSteps() throws -> T {
        let sut: T = try given()
        snapshot?(sut)
        for step in steps {
            try step(sut)
            snapshot?(sut)
        }
        return sut
    }
}

internal extension ScopeImplementation {
    @discardableResult
    func when<Subscope: ScopeImplementation>(
        childScope: Subscope,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: [Subscope.When]
    ) throws -> Self {
        // assertNoDeepEffects(file: file, line: line)
        try whens.forEach {
            childScope.effectsState.reset()
            try childScope._unsafeSendImplementation($0)
        }
        return self
    }
}

public class WithStoreTestPlan<W: ScopeImplementation, S: ScopeImplementation>: StoreTestPlan<W> {
    public let keyPath: KeyPath<S, W>
    public let parentPlan: StoreTestPlan<S>

    internal init(parent: StoreTestPlan<S>, keyPath: KeyPath<S, W>) {
        self.keyPath = keyPath
        self.parentPlan = parent
        super.init {
            fatalError("This is never called")
        }
    }
    
    override func addStep(_ step: @escaping (W) throws -> Void) -> Self {
        _ = parentPlan.addStep { [keyPath] sut in
            try step(sut[keyPath: keyPath])
        }
        return self
    }
    
    func POP() -> StoreTestPlan<S> {
        return parentPlan
    }
}

public class WithOptStoreTestPlan<W: ScopeImplementation, S: ScopeImplementation>: StoreTestPlan<W> {
    public let keyPath: KeyPath<S, W?>
    public let parentPlan: StoreTestPlan<S>

    internal init(parent: StoreTestPlan<S>, keyPath: KeyPath<S, W?>) {
        self.keyPath = keyPath
        self.parentPlan = parent
        super.init {
            fatalError("This is never called")
        }
    }
    
    override func addStep(_ step: @escaping (W) throws -> Void) -> Self {
        _ = parentPlan.addStep { [keyPath] sut in
            guard let childScope: W = sut[keyPath: keyPath] else {
                XCTFail("WITH: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: W.self)) : \(type(of: W.self))")
                // TODO: correct file and line
                // file: file, line: line)
                throw TestPlanErrors.unwrappingNonOptionalSubscope
            }
            try step(childScope)
        }
        return self
    }
    
    public func POP() -> StoreTestPlan<S> {
        return parentPlan
    }
    
    override public func runTest(file: StaticString = #file, line: UInt = #line, assertRelease: Bool = false) throws {
        try parentPlan.runTest(file: file, line: line, assertRelease: assertRelease)
    }
}
