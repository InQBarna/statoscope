//
//  EffectsTests.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import XCTest
@testable import Statoscope
import StatoscopeTesting

#if swift(>=5.8)
// swiftlint:disable nesting
class StoreOngoingEffectsPropertyTests: XCTestCase {

    override func setUp() async throws {
        StatoscopeLogger.logLevel = [LogLevel.effects]
        scopeEffectsDisabledInUnitTests = false
    }

    override class func tearDown() {
        StatoscopeLogger.logLevel = Set()
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

    private final class SimpleScopeWithEffect: Statostore {
        var completeAnyEffect: () -> Void = { }
        enum When {
            case sendWaitEffect(UInt64)
            case anyEffectCompleted
        }
        func update(_ when: When) throws {
            switch when {
            case .sendWaitEffect(let milliseconds):
                effectsState.enqueue(WaitMillisecondsEffect(milliseconds: milliseconds).map {
                    .anyEffectCompleted
                })
            case .anyEffectCompleted:
                completeAnyEffect()
            }
        }
    }

    @MainActor
    func testSingleEffect() async throws {
        let sut = SimpleScopeWithEffect()
        let effectCompletionExpectation = expectation(description: #function)
        sut.completeAnyEffect = {
            effectCompletionExpectation.fulfill()
        }
        sut.send(.sendWaitEffect(Self.firstEffectMilliseconds))
        XCTAssertEffectsInclude(sut, WaitMillisecondsEffect(milliseconds: Self.firstEffectMilliseconds))
        await fulfillment(of: [effectCompletionExpectation], timeout: 5)
        XCTAssertEqual(sut.effects.count, 0)
    }

    @MainActor
    func testTwoEffects() async throws {
        let sut = SimpleScopeWithEffect()
        let effect1CompletionExpectation = expectation(description: #function)
        var effect1Fullfilled = false
        let effect2CompletionExpectation = expectation(description: #function)
        sut.completeAnyEffect = {
            if !effect1Fullfilled {
                effect1CompletionExpectation.fulfill()
                effect1Fullfilled = true
            } else {
                effect2CompletionExpectation.fulfill()
            }
        }
        sut.send(.sendWaitEffect(Self.firstEffectMilliseconds))
        XCTAssertEqual(sut.effects.count, 1)
        XCTAssertEffectsInclude(sut, WaitMillisecondsEffect(milliseconds: Self.firstEffectMilliseconds))
        sut.send(.sendWaitEffect(Self.secondEffectMilliseconds))
        XCTAssertEqual(sut.effects.count, 2)
        XCTAssertEffectsInclude(sut, WaitMillisecondsEffect(milliseconds: Self.firstEffectMilliseconds))
        XCTAssertEffectsInclude(sut, WaitMillisecondsEffect(milliseconds: Self.secondEffectMilliseconds))
        await fulfillment(of: [effect1CompletionExpectation], timeout: 5)
        XCTAssertEqual(sut.effects.count, 1)
        XCTAssertEffectsInclude(sut, WaitMillisecondsEffect(milliseconds: Self.secondEffectMilliseconds))
        await fulfillment(of: [effect2CompletionExpectation], timeout: 5)
        XCTAssertEqual(sut.effects.count, 0)
    }
}

class StoreEffectsCancellationTests: XCTestCase {

    override func setUp() async throws {
        StatoscopeLogger.logLevel = [LogLevel.effects]
        scopeEffectsDisabledInUnitTests = false
    }

    override class func tearDown() {
        StatoscopeLogger.logLevel = [LogLevel.effects]
        scopeEffectsDisabledInUnitTests = true
    }

    static var effectMilliseconds: UInt64 = 2000

    private struct WaitMillisecondsEffectReturnCancelled: Effect, Equatable {
        let milliseconds: UInt64
        func runEffect() async throws -> Bool {
            do {
                try await Task.sleep(nanoseconds: milliseconds * 1000_000)
                try Task.checkCancellation()
                XCTFail("This effect is meant to be cancelled")
                return false
            } catch is CancellationError {
                return true
            } catch {
                XCTFail("This effect is meant to be cancelled")
                return false
            }
        }
    }

    private final class SimpleScopeWithEffect: Statostore {
        var completeAnyEffect: (Bool) async -> Void = { _ in }
        enum When {
            case sendWaitEffect(UInt64)
            case anyEffectCompleted(Bool)
            case cancelAllEffects
            case cancelSingleEffectWithEqual(UInt64)
        }
        func update(_ when: When) throws {
            switch when {
            case .sendWaitEffect(let milliseconds):
                effectsState.enqueue(
                    WaitMillisecondsEffectReturnCancelled(milliseconds: milliseconds)
                        .map(When.anyEffectCompleted)
                )
            case .anyEffectCompleted(let cancelled):
                Task {
                    await completeAnyEffect(cancelled)
                }
            case .cancelAllEffects:
                effectsState.cancelEffect { effect in
                    effect is WaitMillisecondsEffectReturnCancelled
                }
            case .cancelSingleEffectWithEqual(let milliseconds):
                effectsState.cancelEffect { anyEffect in
                    if let effect = anyEffect as? WaitMillisecondsEffectReturnCancelled,
                       effect == WaitMillisecondsEffectReturnCancelled(milliseconds: milliseconds) {
                        return true
                    } else {
                        return false
                    }
                }
            }
        }
    }

    actor CancelledActor {
        var cancelled: Bool?
        func setCancelled(_ newCancelled: Bool) {
            self.cancelled = newCancelled
        }
    }

    func testSingleEffectCancelledOnDeinit() async throws {
        // When an scope is released, all effects should be cancelled
        let effectCompletionExpectation = expectation(description: #function)
        effectCompletionExpectation.isInverted = true
        let cancelledActor: CancelledActor = CancelledActor()
        await MainActor.run {
            autoreleasepool {
                var sut: SimpleScopeWithEffect? = SimpleScopeWithEffect()
                sut?.completeAnyEffect = { cancelled in
                    await cancelledActor.setCancelled(cancelled)
                    effectCompletionExpectation.fulfill()
                }
                sut?.send(.sendWaitEffect(Self.effectMilliseconds))
                sleep(1) // Wait so effect starts and can be cancelled
                sut = nil
            }
        }
        let cancelled = await cancelledActor.cancelled
        XCTAssertNil(cancelled, "completion should never be called")
        await fulfillment(of: [effectCompletionExpectation], timeout: 3)
    }

    @MainActor
    func testCancelAllEffectsProgrammatically() async throws {
        let effectCompletionExpectation = expectation(description: #function)
        effectCompletionExpectation.isInverted = true
        let sut = SimpleScopeWithEffect()
        let cancelledActor: CancelledActor = CancelledActor()
        sut.completeAnyEffect = { cancelled in
            await cancelledActor.setCancelled(cancelled)
            effectCompletionExpectation.fulfill()
        }
        sut.send(.sendWaitEffect(Self.effectMilliseconds))
        sut.send(.cancelAllEffects)
        let cancelled = await cancelledActor.cancelled
        XCTAssertNil(cancelled, "completion should never be called")
        await fulfillment(of: [effectCompletionExpectation], timeout: 3)
    }

    @MainActor
    func testCancelEffectProgrammatically() async throws {
        let effectCompletionExpectation = expectation(description: #function)
        effectCompletionExpectation.isInverted = true
        let sut = SimpleScopeWithEffect()
        let cancelledActor: CancelledActor = CancelledActor()
        sut.completeAnyEffect = { cancelled in
            await cancelledActor.setCancelled(cancelled)
            effectCompletionExpectation.fulfill()
        }
        sut.send(.sendWaitEffect(Self.effectMilliseconds))
        sut.send(.cancelSingleEffectWithEqual(Self.effectMilliseconds))
        let cancelled = await cancelledActor.cancelled
        XCTAssertNil(cancelled, "completion should never be called")
        await fulfillment(of: [effectCompletionExpectation], timeout: 3)
    }
}
// swiftlint:enable nesting
#endif
