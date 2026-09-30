//
//  EffectsHanlderImplementationTests.swift
//  
//
//  Created by Sergi Hernanz on 10/2/24.
//

import Foundation
import XCTest
@testable import Statoscope
@_spi(SCT) import Statoscope

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
        snapshot._updating = true
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
        snapshot._updating = true
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
        snapshot._updating = true
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
        snapshot._updating = true
        snapshot.enqueue(effect)
        snapshot._updating = false
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

/// Direct unit tests on the `EffectsState` struct itself (enqueue/cancelEffect/_cancelOlderEffect),
/// as opposed to `EffectsHanlderImplementationTests` above which drives it through the actor.
class EffectsStateDirectTests: XCTestCase {

    private struct DummyEffect: Effect, Equatable {
        let tag: String
        func runEffect() async throws { }
    }

    /// `cancelEffect` is documented to cancel "ongoing" effects. When an effect is enqueued and
    /// then cancelled within the *same* update (i.e. before the snapshot is ever flushed to the
    /// handler), it must also be removed from `enquedEffects` — otherwise it would still be
    /// triggered despite having just been cancelled.
    func testCancelEffectRemovesNewlyEnqueuedEffectFromEnquedEffects() {
        var state = EffectsState<Void>(snapshotEffects: [])
        state._updating = true
        state.enqueue(DummyEffect(tag: "a"))
        XCTAssertEqual(state.enquedEffects.count, 1)

        state.cancelEffect { ($0 as? DummyEffect)?.tag == "a" }

        XCTAssertEqual(state.enquedEffects.count, 0)
        XCTAssertEqual(state.currentRequestedEffects.count, 0)
        XCTAssertEqual(state.cancelledEffects.count, 1)
    }

    /// `cancelEffect` should leave unrelated newly-enqueued effects alone.
    func testCancelEffectKeepsNonMatchingNewlyEnqueuedEffectInEnquedEffects() {
        var state = EffectsState<Void>(snapshotEffects: [])
        state._updating = true
        state.enqueue(DummyEffect(tag: "keep"))
        state.enqueue(DummyEffect(tag: "cancel"))
        XCTAssertEqual(state.enquedEffects.count, 2)

        state.cancelEffect { ($0 as? DummyEffect)?.tag == "cancel" }

        XCTAssertEqual(state.enquedEffects.map { ($0.1.pristine as? DummyEffect)?.tag }, ["keep"])
        XCTAssertEqual(state.currentRequestedEffects.map { ($0.1.pristine as? DummyEffect)?.tag }, ["keep"])
        XCTAssertEqual(state.cancelledEffects.count, 1)
    }

    // MARK: - Fixed bug: `_cancelOlderEffect` used to pollute `enquedEffects`
    //
    // `_cancelOlderEffect()` (Sources/Statoscope/Effects/EffectsState.swift) is meant to remove
    // just the single oldest pending effect and hand it back — used by
    // `WHEN_OlderEffectCompletes` to simulate that one effect's completion while leaving any
    // other pending effects untouched. It used to reassign `enquedEffects` from
    // `currentRequestedEffects` (by that point already filtered down to every other
    // still-pending effect) instead of filtering `enquedEffects` itself — a no-op filter that
    // left `enquedEffects` containing every other in-flight effect, even ones never freshly
    // enqueued this cycle. That corrupted the invariant `_unsafeSendImplementation` asserts on
    // the next send (`assert(effectsState.enquedEffects.count == 0)`), so it wasn't just
    // cosmetic — it could crash the very next `send`/`sendUnsafe` call on a scope with 2+ pending
    // effects when `WHEN_OlderEffectCompletes` is used. See UNCOVERED_BY_UNIT_TESTS.md, Group D,
    // for the original writeup.
    func testCancelOlderEffectDoesNotPolluteEnquedEffectsWithOtherPendingEffects() throws {
        let effect1 = DummyEffect(tag: "older")
        let effect2 = DummyEffect(tag: "newer-but-not-freshly-enqueued")
        var state = EffectsState<Void>(snapshotEffects: [
            (1, AnyEffect(effect: effect1)),
            (2, AnyEffect(effect: effect2))
        ])
        XCTAssertEqual(state.enquedEffects.count, 0, "Nothing was enqueued this cycle yet")

        let removed = try state._cancelOlderEffect()

        XCTAssertEqual(removed.pristine as? DummyEffect, effect1)
        XCTAssertEqual(state.currentRequestedEffects.count, 1, "Only the untouched effect2 should remain")
        XCTAssertEqual(
            state.enquedEffects.count, 0,
            "enquedEffects should stay empty — effect2 was never freshly enqueued this cycle."
        )
    }
}
