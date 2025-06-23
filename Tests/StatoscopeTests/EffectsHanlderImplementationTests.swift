//
//  EffectsHanlderImplementationTests.swift
//  
//
//  Created by Sergi Hernanz on 10/2/24.
//

import Foundation
import XCTest
@testable import Statoscope

        // currentSnapshot = newSnapshot
class EffectsHanlderImplementationTests: XCTestCase {

    override func setUp() async throws {
        // StatoscopeLogger.logEnabled = true
        scopeEffectsDisabledInUnitTests = false
    }

    override class func tearDown() {
        // StatoscopeLogger.logEnabled = false
        scopeEffectsDisabledInUnitTests = true
    }

    static var firstEffectMilliseconds: UInt64 = 100
    static var secondEffectMilliseconds: UInt64 = 500

    private struct WaitMillisecondsEffect: Effect, Equatable {
        let milliseconds: UInt64
        func runEffect() async throws {
            try await Task.sleep(nanoseconds: milliseconds * 1000_000)
        }
    }

    private struct AutoCancelledEffect: Effect, Equatable {
        let milliseconds: UInt64
        func runEffect() async throws {
            try await Task.sleep(nanoseconds: milliseconds * 1000_000)
            throw CancellationError()
        }
    }

    func testEnqueueEmptySnapshot() async throws {
        let exp = expectation(description: "Wait for new snapshot")
        exp.isInverted = true
        var completedEffects: [AnyEffect<()>] = []
        let sut: EffectsHandlerImplementation<Void> =
        EffectsHandlerImplementation(logPrefix: #function) { _, effect, _ in
            completedEffects.append(effect)
            exp.fulfill()
        }
        let snapshot = await sut.buildSnapshot()
        let currentEffects = await sut.effects
        XCTAssert(currentEffects.isEmpty)
        try await sut.triggerNewEffectsState(newSnapshot: snapshot, injectionTreeNode: nil)
        let newState = await sut.effects
        XCTAssert(newState.isEmpty)
        await fulfillment(of: [exp], timeout: 1)
    }

    func testEnqueueOneEffect() async throws {
        let exp = expectation(description: "Wait for new snapshot")
        var completedEffects: [AnyEffect<()>] = []
        let sut: EffectsHandlerImplementation<Void> =
        EffectsHandlerImplementation(logPrefix: #function) { _, effect, _ in
            completedEffects.append(effect)
            exp.fulfill()
        }
        var snapshot = await sut.buildSnapshot()
        let effect = WaitMillisecondsEffect(milliseconds: Self.firstEffectMilliseconds)
        snapshot.enqueue(effect)
        try await sut.triggerNewEffectsState(newSnapshot: snapshot, injectionTreeNode: nil)
        let newEffects = await sut.effects
        XCTAssertEqual(newEffects.count, 1)
        XCTAssertEqual(newEffects.first as? WaitMillisecondsEffect, effect)
        await fulfillment(of: [exp], timeout: 1)
        let newEffectsAfterCompletion = await sut.effects
        XCTAssertEqual(newEffectsAfterCompletion.count, 0)
        XCTAssertEqual(completedEffects.first?.pristine as? WaitMillisecondsEffect, effect)
    }

    func testEnqueueTwoEffect() async throws {
        let exp = expectation(description: "Wait for new snapshot")
        exp.assertForOverFulfill = false
        let exp2 = expectation(description: "Wait for new snapshot")
        exp2.expectedFulfillmentCount = 2
        var completedEffects: [AnyEffect<()>] = []
        let sut: EffectsHandlerImplementation<Void> =
        EffectsHandlerImplementation(logPrefix: #function) { _, effect, _ in
            completedEffects.append(effect)
            exp.fulfill()
            exp2.fulfill()
        }
        var snapshot = await sut.buildSnapshot()
        let effect1 = WaitMillisecondsEffect(milliseconds: Self.firstEffectMilliseconds)
        let effect2 = WaitMillisecondsEffect(milliseconds: Self.secondEffectMilliseconds)
        snapshot.enqueue(effect1)
        snapshot.enqueue(effect2)
        try await sut.triggerNewEffectsState(newSnapshot: snapshot, injectionTreeNode: nil)
        let newEffects = await sut.effects
        XCTAssertEqual(newEffects.count, 2)
        XCTAssertEqual(newEffects.first as? WaitMillisecondsEffect, effect1)
        XCTAssertEqual(newEffects.last as? WaitMillisecondsEffect, effect2)

        await fulfillment(of: [exp], timeout: 1)
        let newEffectsAfterCompletion = await sut.effects
        XCTAssertEqual(newEffectsAfterCompletion.count, 1)
        XCTAssertEqual(newEffects.last as? WaitMillisecondsEffect, effect2)
        XCTAssertEqual(completedEffects.first?.pristine as? WaitMillisecondsEffect, effect1)

        await fulfillment(of: [exp2], timeout: 1)
        let newEffectsAfterCompletion2 = await sut.effects
        XCTAssertEqual(newEffectsAfterCompletion2.count, 0)
        XCTAssertEqual(completedEffects.last?.pristine as? WaitMillisecondsEffect, effect2)
    }

    func testEnqueueAutocancelledEffect() async throws {
        let exp = expectation(description: "Wait for new snapshot")
        var completedEffects: [(AnyEffect<()>, ()?)] = []
        let sut: EffectsHandlerImplementation<Void> =
        EffectsHandlerImplementation(logPrefix: #function) { _, effect, when in
            completedEffects.append((effect, when))
            exp.fulfill()
        }
        var snapshot = await sut.buildSnapshot()
        let effect = AutoCancelledEffect(milliseconds: Self.firstEffectMilliseconds)
        snapshot.enqueue(effect)
        try await sut.triggerNewEffectsState(newSnapshot: snapshot, injectionTreeNode: nil)
        let newEffects = await sut.effects
        XCTAssertEqual(newEffects.count, 1)
        XCTAssertEqual(newEffects.first as? AutoCancelledEffect, effect)
        await fulfillment(of: [exp], timeout: 1)
        let newEffectsAfterCompletion = await sut.effects
        XCTAssertEqual(newEffectsAfterCompletion.count, 0)
        XCTAssertEqual(completedEffects.first?.0.pristine as? AutoCancelledEffect, effect)
        XCTAssertNil(completedEffects.first?.1)
    }

    func testEnqueueAndCancelOneEffect() async throws {
        let exp = expectation(description: "Wait for new snapshot")
        var completedEffects: [(AnyEffect<()>, ()?)] = []
        let sut: EffectsHandlerImplementation<Void> =
        EffectsHandlerImplementation(logPrefix: #function) { _, effect, when in
            completedEffects.append((effect, when))
            exp.fulfill()
        }
        var snapshot = await sut.buildSnapshot()
        let effect = WaitMillisecondsEffect(milliseconds: Self.firstEffectMilliseconds)
        snapshot.enqueue(effect)
        try await sut.triggerNewEffectsState(newSnapshot: snapshot, injectionTreeNode: nil)
        let newEffects = await sut.effects
        XCTAssertEqual(newEffects.count, 1)
        XCTAssertEqual(newEffects.first as? WaitMillisecondsEffect, effect)

        var snapshot2 = await sut.buildSnapshot()
        snapshot2.cancelAllEffects()
        try await sut.triggerNewEffectsState(newSnapshot: snapshot2, injectionTreeNode: nil)
        await fulfillment(of: [exp], timeout: 1)
        let newEffectsAfterCompletion2 = await sut.effects
        XCTAssertEqual(newEffectsAfterCompletion2.count, 0)
        XCTAssertEqual(completedEffects.count, 1)
        XCTAssertEqual(completedEffects.first?.0.pristine as? WaitMillisecondsEffect, effect)
        XCTAssertNil(completedEffects.first?.1)
    }

}
