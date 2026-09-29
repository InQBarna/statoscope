//
//  RemoveOptionalDescriptionTests.swift
//  Statoscope
//
//  `String.removeOptionalDescription` (Sources/Statoscope/Helpers/String+removeOptionalDescription.swift)
//  strips the "Optional(...)" wrapper Swift adds when describing an optional *value*. It has a
//  second branch for the "Optional<...>" form Swift produces when describing an optional *type*
//  (e.g. `String(describing: Optional<Int>.self)`), used by injection-key naming
//  (`Sources/Statoscope/Injection/InjectionStore.swift`) so `SomeType?` and `SomeType` share a
//  key. No existing test exercises that second branch.
//

import Foundation
import XCTest
@testable import Statoscope

final class RemoveOptionalDescriptionTests: XCTestCase {

    func testRemovesAngleBracketOptionalWrapperFromTypeDescription() {
        let typeDescription = String(describing: Optional<Int>.self)
        XCTAssertEqual(typeDescription, "Optional<Int>")
        XCTAssertEqual(typeDescription.removeOptionalDescription, "Int")
    }

    func testRemovesParenthesesOptionalWrapperFromValueDescription() {
        let valueDescription = String(describing: Optional(42))
        XCTAssertEqual(valueDescription, "Optional(42)")
        XCTAssertEqual(valueDescription.removeOptionalDescription, "42")
    }

    func testLeavesNonOptionalDescriptionUnchanged() {
        XCTAssertEqual("Int".removeOptionalDescription, "Int")
    }
}
