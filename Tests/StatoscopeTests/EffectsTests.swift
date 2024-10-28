//
//  EffectsTests.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import XCTest
@_spi(SCT) import Statoscope
import StatoscopeTesting

// swiftlint:disable nesting
class EffectsPristineEqualsTests: XCTestCase {

    private struct Effect1: Effect, Equatable {
        let param1: String
        func runEffect() async throws -> String {
            return "done"
        }
    }
    private struct Effect2: Effect, Equatable {
        let param1: String
        func runEffect() async throws -> String {
            return "done"
        }
    }

    func testEquatable() {
        let effectA = Effect1(param1: "param1")
        let effectB = Effect1(param1: "param1")
        let effectC = Effect1(param1: "param2")
        XCTAssertEqual(effectA, effectB)
        XCTAssertNotEqual(effectA, effectC)
    }

    func testEquatableAfterErasure() {
        let effectA = Effect1(param1: "param1")
        let effectB = Effect1(param1: "param1")
        let effectC = Effect1(param1: "param2")
        XCTAssert(effectA.eraseToAnyEffect().pristineEquals(effectB))
        XCTAssert(effectB.eraseToAnyEffect().pristineEquals(effectA))
        XCTAssertFalse(effectA.eraseToAnyEffect().pristineEquals(effectC))
        XCTAssertFalse(effectC.eraseToAnyEffect().pristineEquals(effectA))
    }

    func testEquatableAfterMap() {
        let effectA = Effect1(param1: "param1")
            .map { "\($0)-appended" }
        let effectB = Effect1(param1: "param1")
        let effectC = Effect1(param1: "param2")
        let effectD = Effect2(param1: "param1")
        XCTAssert(effectA.pristineEquals(effectB))
        XCTAssertFalse(effectA.pristineEquals(effectC))
        XCTAssertFalse(effectA.pristineEquals(effectD))
    }

    func testEquatableAfterMapError() {
        let effectA = Effect1(param1: "param1")
            .map { "\($0)-appended" }
            .mapToResultWithError { _ in InvalidStateError() }
        let effectB = Effect1(param1: "param1")
        let effectC = Effect1(param1: "param2")
        let effectD = Effect2(param1: "param1")
        XCTAssert(effectA.pristineEquals(effectB))
        XCTAssertFalse(effectA.pristineEquals(effectC))
        XCTAssertFalse(effectA.pristineEquals(effectD))
    }

    func testFindTestInArray() {
        struct MyEffect: Effect, Equatable {
            let param1: String
            func runEffect() async throws -> String {
                return "done"
            }
        }
        let effects = [MyEffect(param1: "One"), MyEffect(param1: "Two")]
        let effectOne = effects.first { $0.pristineEquals(MyEffect(param1: "One")) }
        XCTAssertNotNil(effectOne)
    }

    func testAnonymousEquatable() {
        let anonymousEffect1 = AnyEffect {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return "result"
        }
        let anonymousEffect2 = AnyEffect {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return "result2"
        }
        XCTAssertEqual(anonymousEffect1.debugDescription,
                       anonymousEffect2.debugDescription)
        // Can't compare both effects
        // XCTAssert(anonymousEffect1.pristineEquals(anonymousEffect2))
    }
    
    func testPristineIs() {
        let effect1Mapped = Effect1(param1: "param1")
            .map({ $0 + "-appended" })
        let effect1 = Effect1(param1: "param1")
        let effect2Mapped = Effect2(param1: "param2")
            .map({ $0 + "-appended" })
        let effect2 = Effect2(param1: "param2")
        XCTAssert(effect1.pristineIs(Effect1.self))
        XCTAssert(effect1Mapped.pristineIs(Effect1.self))
        XCTAssertFalse(effect1.pristineIs(Effect2.self))
        XCTAssertFalse(effect1Mapped.pristineIs(Effect2.self))
        XCTAssert(effect2.pristineIs(Effect2.self))
        XCTAssert(effect2Mapped.pristineIs(Effect2.self))
        XCTAssertFalse(effect2.pristineIs(Effect1.self))
        XCTAssertFalse(effect2Mapped.pristineIs(Effect1.self))
    }
}

class EffectsRunBlockCall: XCTestCase {
    
    func testAnonymousEffectsRun() async throws {
        let exp = expectation(description: "Effect ran")
        let anonymousEffect1 = AnyEffect {
            try await Task.sleep(nanoseconds: 100)
            exp.fulfill()
            return "result"
        }
        let res = try await anonymousEffect1.runEffect()
        await self.fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(res, "result")
    }
    
    private struct FailableEffect: Effect, Equatable {
        let fail: Bool
        func runEffect() async throws -> String {
            try await Task.sleep(nanoseconds: 100)
            if fail {
                throw InvalidStateError()
            } else {
                return "result"
            }
        }
    }
    
    private struct MyError: Error, Equatable { }
    
    func testMapToError() async throws {
        let exp = expectation(description: "mapToError called")
        let effect = FailableEffect(fail: true)
            .mapToResultWithError { _ in
                exp.fulfill()
                return MyError()
            }
        let result = try await effect.runEffect()
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(result, .failure(MyError()))
    }
    
    func testMapToErrorSuccess() async throws {
        let exp = expectation(description: "mapToError not called")
        exp.isInverted = true
        let effect = FailableEffect(fail: false)
            .mapToResultWithError { _ in
                exp.fulfill()
                return MyError()
            }
        let result = try await effect.runEffect()
        await fulfillment(of: [exp], timeout: 0.1)
        XCTAssertEqual(result, .success("result"))
    }
    
    func testMapToResult() async throws {
        let effect = FailableEffect(fail: true)
            .mapToResult()
        let result = try await effect.runEffect()
        switch result {
        case .success: XCTFail("Should receive failure")
        case .failure(let error): XCTAssert(error is InvalidStateError)
        }
    }
    
    func testMapToResultSuccess() async throws {
        let effect = FailableEffect(fail: false)
            .mapToResult()
        let result = try await effect.runEffect()
        switch result {
        case .failure: XCTFail("Should receive success")
        default: break
        }
    }
    
    private struct FailableEffectTyped: Effect, Equatable {
        enum FailType {
            case controlledError
            case unexpectedError
        }
        let fail: FailType?
        func runEffect() async throws -> String {
            try await Task.sleep(nanoseconds: 100)
            switch fail {
            case .none:
                return "result"
            case .controlledError:
                throw MyErrorTyped.controlledError
            case .unexpectedError:
                throw InvalidStateError()
            }
        }
    }
    
    private enum MyErrorTyped: EffectError, Equatable {
        case unknown
        case controlledError
        
        static var unknownError: MyErrorTyped = .unknown
    }
    
    func testMapToErrorTyped() async throws {
        let effect = FailableEffectTyped(fail: .controlledError)
            .mapToResultWithErrorType(MyErrorTyped.self)
        let result = try await effect.runEffect()
        XCTAssertEqual(result, .failure(MyErrorTyped.controlledError))
    }
    
    func testMapToErrorTypedUnexpected() async throws {
        let effect = FailableEffectTyped(fail: .unexpectedError)
            .mapToResultWithErrorType(MyErrorTyped.self)
        let result = try await effect.runEffect()
        XCTAssertEqual(result, .failure(MyErrorTyped.unknown))
        XCTAssertEqual(result, .failure(MyErrorTyped.unknownError))
    }
    
    func testMapToErrorTypedSuccess() async throws {
        let effect = FailableEffectTyped(fail: nil)
            .mapToResultWithErrorType(MyErrorTyped.self)
        let result = try await effect.runEffect()
        XCTAssertEqual(result, .success("result"))
    }
}

extension String: Error { }
class EffectPristineCompletesOrFailsTests: XCTestCase {
    struct Effect1: Effect {
        let param: String
        func runEffect() async throws -> String {
            return "done"
        }
    }
    func testPristineCompletes() async throws {
        let effectA = Effect1(param: "param1")
            .map { "\($0)-appended" }
        let result = try effectA._pristineCompletes("fakeDone")
        XCTAssertEqual("fakeDone-appended", result)
    }
    func testPristineCompletesManyMaps() async throws {
        let effectA = Effect1(param: "param1")
            .map { "\($0)-appended" }
            .mapToResultWithErrorType(EquatableError.self)
        let result = try effectA._pristineCompletes("fakeDone")
        XCTAssertEqual(.success("fakeDone-appended"), result)
    }
    func testPristineCompletesNoMap() async throws {
        let effectA = Effect1(param: "param1")
        let result = try effectA._pristineCompletes("fakeDone")
        XCTAssertEqual("fakeDone", result)
    }
    
    func testPristineFails() async throws {
        let effectA = Effect1(param: "param1")
            .mapToResultWithError(EquatableError.init)
        let result = try effectA._pristineFails("failed")
        XCTAssertEqual(.failure("failed".toEquatableError()), result)
    }
    func testPristineFailsEquatable() async throws {
        let effectA = Effect1(param: "param1")
            .mapToResultWithErrorType(EquatableError.self)
        let result = try effectA._pristineFails("failed".toEquatableError())
        XCTAssertEqual(.failure("failed".toEquatableError()), result)
    }
    func testPristineFailsNoMap() async throws {
        let effectA = Effect1(param: "param1")
        XCTAssertThrowsError(try effectA._pristineFails("failed"))
    }
    func testPristineFailsNoEquatableError() async throws {
        let effectA = Effect1(param: "param1")
            .mapToResult()
        let result = try effectA._pristineFails("failed")
        XCTAssertEqual(result.toEquatableError(), .failure("failed".toEquatableError()))
    }
}
// swiftlint:enable nesting
