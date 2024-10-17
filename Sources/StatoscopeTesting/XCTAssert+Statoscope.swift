//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 17/10/24.
//

import Foundation
import XCTest
import Statoscope

func XCTFailForEffectSearchError<T: Effect, S: ScopeImplementation>(
    _ error: EffectTestError<T, S>,
    file: StaticString,
    line: UInt
) {
    switch error.type {
    case .notFound:
        XCTFail("No effect of type \(T.self) on sut \(type(of: error.sut)): " +
                "\(error.existingEffects)", file: file, line: line)
    case .tooMany:
        XCTFail("More than 1 effects of type \(T.self) on sut \(type(of: error.sut)): " +
                "\(error.existingEffects)", file: file, line: line)
    }
}

func XCTFailForEffectSearchSuccess<EffectType: Effect, T: ScopeImplementation>(
    foundEffects: [FoundEffect<EffectType>],
    sut: T,
    file: StaticString,
    line: UInt
) {
    XCTFail("Unexpected effect of type \(EffectType.self) on sut \(type(of: sut)): " +
            "\(foundEffects.map { $0.typed })", file: file, line: line)
}

func XCTFailForEffectSearchSuccess<T: ScopeImplementation>(
    erasedFoundEffects: [any Effect],
    sut: T,
    file: StaticString,
    line: UInt
) {
    XCTFail("Unexpected effects on sut \(type(of: sut)): " +
            "\(erasedFoundEffects)", file: file, line: line)
}

func XCTFailForMissingSubscope<S: ScopeImplementation, Subscope: ScopeImplementation>(
    keyPath: KeyPath<S, Subscope?>,
    file: StaticString,
    line: UInt
) {
    XCTFail("No subscope found on \(S.self) of type \(Subscope.self): " +
            "when looking for effects", file: file, line: line)
}

public func XCTAssertEffectsInclude<S: ScopeImplementation, T2: Effect & Equatable>(
    _ expression1: @autoclosure () throws -> S?,
    _ expression2: @autoclosure () throws -> T2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) where S: ScopeImplementation, T2: Effect & Equatable {
    do {
        let sut = try XCTUnwrap(try expression1(), file: file, line: line)
        let expected = try expression2()
        switch getSingleEffect(expected, sut: sut) {
        case .failure(let error):
            XCTFailForEffectSearchError(error, file: file, line: line)
        case .success:
            return
        }
        // sut?.cancelAllEffects()
    } catch {
        XCTFail("Thrown \(error)", file: file, line: line)
    }
}

public func XCTAssertEqualDiff<T>(
    _ expression1: @autoclosure () throws -> T,
    _ expression2: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws where T : Equatable {
    let val1 = try expression1()
    let val2 = try expression2()
    if val1 == val2 {
        return
    }
    var expected: String = ""
    dump(val1, to: &expected)
    var described2: String = ""
    dump(val2, to: &described2)
    let differences = expected
        .split(separator: "\n")
        .difference(from: described2.split(separator: "\n"))
        .sorted { lhs, rhs in
            lhs.offset < rhs.offset
        }
    XCTFail(message() + "\n" + differences
        .map {
            switch $0 {
            case .remove(_, let element, _):
                return "- " + element
            case .insert(_, let element, _):
                return "+ " + element
            }
        }
        .joined(separator: "\n"),
        file: file, line: line)
}
