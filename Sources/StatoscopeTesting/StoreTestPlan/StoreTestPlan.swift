//
//  StoreTestPlan.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope

public final class StoreTestPlan<T: StoreProtocol> {
    let given: () throws -> T
    internal var steps: [(T) throws -> Void] = []
    internal var forks: [StoreTestPlan<T>] = []
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

internal extension StoreImplementation {
    @discardableResult
    func when<Subscope: StoreProtocol>(childScope: Subscope,
                                                   file: StaticString = #file, line: UInt = #line,
                                                   _ whens: [Subscope.When]) throws -> Self {
        // assertNoDeepEffects(file: file, line: line)
        try whens.forEach {
            childScope.effectsState.reset()
            try childScope.sendUnsafe($0)
        }
        return self
    }
}
