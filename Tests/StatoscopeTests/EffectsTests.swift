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
        XCTAssertEqual(effectA, effectB)
    }
    
    func testEquatableAfterMap() {
        let effectA = Effect1(param1: "param1")
            .map { "\($0)-appended" }
        let effectB = Effect1(param1: "param1")
        XCTAssert(effectA.pristineEquals(effectB))
    }
    
    func testEquatableAfterMapError() {
        let effectA = Effect1(param1: "param1")
            .map { "\($0)-appended" }
            .mapToResultWithError { _ in InvalidStateError() }
        let effectB = Effect1(param1: "param1")
        XCTAssert(effectA.pristineEquals(effectB))
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
}
