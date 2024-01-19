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
class ScopeOngoingEffectsPropertyTests: XCTestCase {
    
    override func setUp() async throws {
        StatoscopeLogger.logEnabled = true
        scopeEffectsDisabledInUnitTests = false
    }
    
    override class func tearDown() {
        StatoscopeLogger.logEnabled = false
        scopeEffectsDisabledInUnitTests = true
    }
    
    static var firstEffectMilliseconds: UInt64 = 100
    static var secondEffectMilliseconds: UInt64 = 500
    
    private struct WaitMillisecondsEffect: Effect {
        let milliseconds: UInt64
        func runEffect() async throws -> Void {
            try await Task.sleep(nanoseconds: milliseconds * 1000_000)
        }
    }
        
    private final class SimpleScopeWithEffect: Scope {
        var completeAnyEffect: () -> Void = { }
        enum When {
            case sendWaitEffect(UInt64)
            case anyEffectCompleted
        }
        func update(_ when: When) throws {
            switch when {
            case .sendWaitEffect(let milliseconds):
                enqueue(WaitMillisecondsEffect(milliseconds: milliseconds).map {
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

class ScopeEffectsCancellationTests: XCTestCase {
    
    override func setUp() async throws {
        StatoscopeLogger.logEnabled = true
        scopeEffectsDisabledInUnitTests = false
    }
    
    override class func tearDown() {
        StatoscopeLogger.logEnabled = false
        scopeEffectsDisabledInUnitTests = true
    }
    
    static var effectMilliseconds: UInt64 = 2000
    
    private struct WaitMillisecondsEffectReturnCancelled: Effect {
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
        
    private final class SimpleScopeWithEffect: Scope {
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
                enqueue(
                    WaitMillisecondsEffectReturnCancelled(milliseconds: milliseconds)
                        .map(When.anyEffectCompleted)
                )
            case .anyEffectCompleted(let cancelled):
                Task {
                    await completeAnyEffect(cancelled)
                }
            case .cancelAllEffects:
                cancelEffect { effect in
                    effect is WaitMillisecondsEffectReturnCancelled
                }
            case .cancelSingleEffectWithEqual(let milliseconds):
                cancelEffect { anyEffect in
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

class ScopeEffectsThrowingTests: XCTestCase {
    
    enum ScopeEffectsThrowingTestsError: Error {
        case forcedError
    }
    
    override func setUp() async throws {
        StatoscopeLogger.logEnabled = true
        scopeEffectsDisabledInUnitTests = false
    }
    
    override class func tearDown() {
        StatoscopeLogger.logEnabled = false
        scopeEffectsDisabledInUnitTests = true
    }
    
    static var effectMilliseconds: UInt64 = 2000
    private struct WaitMillisecondsEffectThrowing<ErrorType: Error & Equatable>: Effect {
        let milliseconds: UInt64
        let throwError: ErrorType?
        func runEffect() async throws -> Void {
            if let throwError {
                throw throwError
            } else {
                try await Task.sleep(nanoseconds: milliseconds * 1000_000)
            }
        }
    }
        
    private final class SimpleScopeWithTypedThrowingEffect<EffectErrorType: Error & Equatable, ResultErrorType: Error & Equatable>: Scope {
        var effectCompleted: () -> Void = { }
        var effectThrowError: EffectErrorType?
        var mapToResultError: ((Error) -> ResultErrorType)?
        private(set) var mappingResult: Result<Void, ResultErrorType>?
        enum When {
            case sendWaitEffect(UInt64)
            case waitEffectCompleted(Result<Void, ResultErrorType>?)
        }
        func update(_ when: When) throws {
            switch when {
            case .sendWaitEffect(let milliseconds):
                if let mapToResultError {
                    enqueue(
                        WaitMillisecondsEffectThrowing(milliseconds: milliseconds, throwError: effectThrowError)
                            .mapToResult(error: { mapToResultError($0) })
                            .map(When.waitEffectCompleted)
                    )
                } else {
                    enqueue(
                        WaitMillisecondsEffectThrowing(milliseconds: milliseconds, throwError: effectThrowError)
                            .map { When.waitEffectCompleted(nil) }
                    )
                }
            case .waitEffectCompleted(let result):
                self.mappingResult = result
                effectCompleted()
            }
        }
    }
    
    // Effects errors are pretty hard to understand, they belong to third parties, we need some mapping into
    //  our domain errors, there are 2 different scenarios:
    // 1.- We don't know the error they may throw (Error)
    // 2.- We have an Error type (like EffectError)
    //
    enum EffectError: Error, Equatable {
        case completelyUnexpected     //
        case unusualCornerCase
        case unauthorized
    }
    
    enum UserError: Error, Equatable {
        case unknown
        case retriable
        case nonRetriable
        
        init(effectError: EffectError) {
            switch effectError {
            case .completelyUnexpected:
                self = .unknown
            case .unusualCornerCase:
                self = .retriable
            case .unauthorized:
                self = .nonRetriable
            }
        }
        
        init(anyThrownError: Error) {
            guard let effectError = anyThrownError as? EffectError else {
                self = .unknown
                return
            }
            self = Self(effectError: effectError)
        }
    }
    
    @MainActor
    func testNoErrorThrown() async throws {
        let effectCompletionExpectation = expectation(description: #function)
        let sut = SimpleScopeWithTypedThrowingEffect<EffectError, UserError>()
        sut.effectThrowError = nil
        sut.mapToResultError = nil
        sut.effectCompleted = {
            effectCompletionExpectation.fulfill()
        }
        sut.send(.sendWaitEffect(Self.effectMilliseconds))
        await fulfillment(of: [effectCompletionExpectation], timeout: 3)
        XCTAssertNil(sut.mappingResult)
    }
    
    @MainActor
    func testTypedUnhandledErrorThrownDoesSilentlyFail() async throws {
        let effectCompletionExpectation = expectation(description: #function)
        effectCompletionExpectation.isInverted = true
        let sut = SimpleScopeWithTypedThrowingEffect<EffectError, UserError>()
        sut.effectThrowError = .unusualCornerCase
        sut.mapToResultError = nil
        sut.effectCompleted = {
            effectCompletionExpectation.fulfill()
        }
        sut.send(.sendWaitEffect(Self.effectMilliseconds))
        await fulfillment(of: [effectCompletionExpectation], timeout: 3)
    }
    
    @MainActor
    func testTypedHandledErrorThrownDoesFailWithResultFailure() async throws {
        let effectCompletionExpectation = expectation(description: #function)
        let sut = SimpleScopeWithTypedThrowingEffect<EffectError, UserError>()
        sut.effectThrowError = .unusualCornerCase
        sut.mapToResultError = { UserError(anyThrownError: $0) }
        sut.effectCompleted = {
            effectCompletionExpectation.fulfill()
        }
        sut.send(.sendWaitEffect(Self.effectMilliseconds))
        await fulfillment(of: [effectCompletionExpectation], timeout: 3)
        let mappingResult = try XCTUnwrap(sut.mappingResult)
        switch mappingResult {
        case .success:
            XCTFail()
        case .failure(let failure):
            XCTAssertEqual(failure, .retriable)
        }
    }
    
    private struct WaitMillisecondsEffectThrowingUntypedError: Effect {
        let milliseconds: UInt64
        let throwError: Bool
        func runEffect() async throws -> Void {
            if throwError {
                throw ScopeEffectsThrowingTestsError.forcedError
            } else {
                try await Task.sleep(nanoseconds: milliseconds * 1000_000)
            }
        }
    }
    
    private final class SimpleScopeWithUntypedThrowingEffect<ResultErrorType: Error & Equatable>: Scope {
        var effectCompleted: () -> Void = { }
        var effectThrowError: Bool = false
        var mapToResultError: ((Error) -> ResultErrorType)?
        private(set) var mappingResult: Result<Void, ResultErrorType>?
        enum When {
            case sendWaitEffect(UInt64)
            case waitEffectCompleted(Result<Void, ResultErrorType>?)
        }
        func update(_ when: When) throws {
            switch when {
            case .sendWaitEffect(let milliseconds):
                if let mapToResultError {
                    enqueue(
                        WaitMillisecondsEffectThrowingUntypedError(milliseconds: milliseconds, throwError: effectThrowError)
                            .mapToResult(error: { mapToResultError($0) })
                            .map(When.waitEffectCompleted)
                    )
                } else {
                    enqueue(
                        WaitMillisecondsEffectThrowingUntypedError(milliseconds: milliseconds, throwError: effectThrowError)
                            .map { When.waitEffectCompleted(nil) }
                    )
                }
            case .waitEffectCompleted(let result):
                self.mappingResult = result
                effectCompleted()
            }
        }
    }
    
    @MainActor
    func testUntypedUnhandledErrorThrownDoesSilentlyFail() async throws {
        let effectCompletionExpectation = expectation(description: #function)
        effectCompletionExpectation.isInverted = true
        let sut = SimpleScopeWithUntypedThrowingEffect<UserError>()
        sut.effectThrowError = true
        sut.mapToResultError = nil
        sut.effectCompleted = {
            effectCompletionExpectation.fulfill()
        }
        sut.send(.sendWaitEffect(Self.effectMilliseconds))
        await fulfillment(of: [effectCompletionExpectation], timeout: 3)
    }
    
    @MainActor
    func testUntypedHandledErrorThrownDoesFailWithResultFailure() async throws {
        let effectCompletionExpectation = expectation(description: #function)
        let sut = SimpleScopeWithUntypedThrowingEffect<UserError>()
        sut.effectThrowError = true
        sut.mapToResultError = { UserError(anyThrownError: $0) }
        sut.effectCompleted = {
            effectCompletionExpectation.fulfill()
        }
        sut.send(.sendWaitEffect(Self.effectMilliseconds))
        await fulfillment(of: [effectCompletionExpectation], timeout: 3)
        let mappingResult = try XCTUnwrap(sut.mappingResult)
        switch mappingResult {
        case .success:
            XCTFail()
        case .failure(let failure):
            XCTAssertEqual(failure, .unknown)
        }
    }
}
#endif
