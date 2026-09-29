//
//  HierarchicalMiddlewareErrorTests.swift
//  Statoscope
//
//  Does a root-level HierarchialScopeMiddleWare see (and can it capture) an error thrown by a
//  grandchild's own update()? Classic Statostore counterpart to
//  ReducerUpdateSubstateErrorTests — see that file for the Reducer-pattern answer, which turns
//  out to be the opposite.
//

import Foundation
import XCTest
@_spi(Internal) @testable import Statoscope

private struct DeliberateTestError: Error, Equatable {
    let context: String
}

/// Root scope, two levels above the throwing scope. Its own updateSubscope wraps
/// `event.forward()` in a do/catch — in the classic pattern, that's a real choice available to
/// the implementer, unlike the Reducer pattern's macro-generated updateSubscope (see the other
/// test file, where no such choice exists).
private final class ErrorCaptureRootScope: Statostore, HierarchialScopeMiddleWare, ObservableObject {
    @Subscope var parent: ErrorCaptureParentScope?
    private(set) var interceptionCount = 0
    private(set) var capturedErrors: [Error] = []

    enum When { case noop }
    func update(_ when: When) throws { }

    func updateSubscope<Child: ScopeImplementation>(_ event: SubscopeEvent<Child>) throws {
        interceptionCount += 1
        do {
            try event.forward()
        } catch {
            // The middleware IS the error boundary here — deliberately swallows rather than
            // rethrowing, exactly the "one global error handler" shape a root middleware is for.
            capturedErrors.append(error)
        }
    }
}

private final class ErrorCaptureParentScope: Statostore, ObservableObject {
    @Subscope var child: ErrorCaptureChildScope?
    enum When { case noop }
    func update(_ when: When) throws { }
}

private final class ErrorCaptureChildScope: Statostore, ObservableObject {
    private(set) var succeededCount = 0
    enum When { case succeed, fail }
    func update(_ when: When) throws {
        switch when {
        case .succeed: succeededCount += 1
        case .fail: throw DeliberateTestError(context: "child failed")
        }
    }
}

final class HierarchicalMiddlewareErrorTests: XCTestCase {

    func testRootMiddlewareCapturesGrandchildThrownError() throws {
        let root = ErrorCaptureRootScope()
        root.parent = ErrorCaptureParentScope()
        root.parent?.child = ErrorCaptureChildScope()

        // Two levels below the root — the grandchild, not a direct child.
        root.parent?.child?.send(.fail)

        XCTAssertEqual(root.interceptionCount, 1, "Root's updateSubscope still runs for the failing event")
        XCTAssertEqual(root.capturedErrors.count, 1, "Root's own do/catch around forward() caught it")
        XCTAssertEqual(root.capturedErrors.first as? DeliberateTestError, DeliberateTestError(context: "child failed"))
    }

    func testRootMiddlewareSeesSuccessWithNoCapturedError() throws {
        let root = ErrorCaptureRootScope()
        root.parent = ErrorCaptureParentScope()
        root.parent?.child = ErrorCaptureChildScope()

        root.parent?.child?.send(.succeed)

        XCTAssertEqual(root.interceptionCount, 1)
        XCTAssertEqual(root.capturedErrors.count, 0)
        XCTAssertEqual(root.parent?.child?.succeededCount, 1)
    }
}
