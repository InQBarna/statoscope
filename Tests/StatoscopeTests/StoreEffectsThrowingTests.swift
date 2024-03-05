//
//  StoreEffectsThrowingTests.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 5/3/24.
//

import Foundation
import XCTest
@testable import Statoscope
import StatoscopeTesting

#if swift(>=5.8)
// swiftlint:disable nesting
class StoreEffectsThrowingTests: XCTestCase {

    enum ScopeEffectsThrowingTestsError: Error {
        case forcedError
    }

    override func setUp() async throws {
        StatoscopeLogger.logLevel = [LogLevel.effects]
        scopeEffectsDisabledInUnitTests = false
    }

    override class func tearDown() {
        StatoscopeLogger.logLevel = Set()
        scopeEffectsDisabledInUnitTests = true
    }

    static var effectMilliseconds: UInt64 = 2000
    private struct WaitMillisecondsEffectThrowing<ErrorType: Error & Equatable>: Effect {
        let milliseconds: UInt64
        let throwError: ErrorType?
        func runEffect() async throws {
            if let throwError {
                throw throwError
            } else {
                try await Task.sleep(nanoseconds: milliseconds * 1000_000)
            }
        }
    }

    private final class SimpleScopeWithTypedThrowingEffect<
            EffectErrorType: Error & Equatable,
            ResultErrorType: Error & Equatable
        >: Statostore {
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
                    effectsState.enqueue(
                        WaitMillisecondsEffectThrowing(milliseconds: milliseconds, throwError: effectThrowError)
                            .mapToResultWithError { mapToResultError($0) }
                            .map(When.waitEffectCompleted)
                    )
                } else {
                    effectsState.enqueue(
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
            XCTFail("Should return failure")
        case .failure(let failure):
            XCTAssertEqual(failure, .retriable)
        }
    }

    private struct WaitMillisEffectThrowingUntypedError: Effect {
        let milliseconds: UInt64
        let throwError: Bool
        func runEffect() async throws {
            if throwError {
                throw ScopeEffectsThrowingTestsError.forcedError
            } else {
                try await Task.sleep(nanoseconds: milliseconds * 1000_000)
            }
        }
    }

    private final class SimpleScopeWithUntypedThrowingEffect<ResultErrorType: Error & Equatable>: Statostore {
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
                    effectsState.enqueue(
                        WaitMillisEffectThrowingUntypedError(
                            milliseconds: milliseconds,
                            throwError: effectThrowError
                        )
                        .mapToResultWithError { mapToResultError($0) }
                        .map(When.waitEffectCompleted)
                    )
                } else {
                    effectsState.enqueue(
                        WaitMillisEffectThrowingUntypedError(
                            milliseconds: milliseconds,
                            throwError: effectThrowError
                        )
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
            XCTFail("Should return failure")
        case .failure(let failure):
            XCTAssertEqual(failure, .unknown)
        }
    }
}
// swiftlint:enable nesting
#endif
