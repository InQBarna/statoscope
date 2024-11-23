//
//  StatoscopeTestingForkTests.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import XCTest
import SwiftUI
@testable import Statoscope
import StatoscopeTesting

private enum MyError: String, EffectError, Equatable {
    case someError
    case noConnection
    static var unknownError: MyError = .someError
}

private struct MyEffect<T: Equatable>: Effect, Equatable {
    let milliseconds: UInt64
    let result: T
    func runEffect() async throws -> T {
        try await Task.sleep(nanoseconds: milliseconds * 1000_000)
        return result
    }
}

/// Scope with all main features
/// - State
/// - Effects
private final class MyScope:
    Statostore,
    Injectable,
    ObservableObject {

    @Published var viewShowsLoadingMessage: String?
    @Published var viewShowsContent: Result<String, MyError>?
    private var effectIndex: Int = 0

    enum When: Equatable {
        case systemLoadsSampleScope
        case networkRespondsWithContent(Result<String, MyError>)
    }

    func update(_ when: When) throws {
        switch when {
        case .systemLoadsSampleScope:
            let simultaneousEffects = effectsState.effects.count
            viewShowsLoadingMessage = "Loading #\(effectIndex) (\(simultaneousEffects + 1))..."
            effectsState.enqueue(
                MyEffect(milliseconds: 1000, result: "Result \(effectIndex)")
                    .mapToResultWithErrorType(MyError.self)
                    .map(When.networkRespondsWithContent)
            )
            effectIndex += 1
        case .networkRespondsWithContent(let newContent):
            viewShowsContent = newContent.mapError { _ in MyError.someError }
            viewShowsLoadingMessage = nil
        }
    }

    static var defaultValue: MyScope = MyScope()
}

final class StatoscopeConfigureTests: XCTestCase {

    // Just providing the highest coverage % to When.swift file here with several scenarios
    func testAllWhenSelfVariants() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .all)
        .THEN(\.viewShowsLoadingMessage, equals: nil)
        .THEN(\.viewShowsContent, equals: nil)
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading #0 (1)...")
        .THEN { sut in
            XCTAssertEqual(sut.effects.count, 1)
            XCTAssertEffectsInclude(sut, MyEffect(milliseconds: 1000, result: "Result 0"))
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading #1 (1)...")
        .THEN { sut in
            // Previous effect has been cleared
            XCTAssertEqual(sut.effects.count, 1)
            XCTAssertEffectsInclude(sut, MyEffect(milliseconds: 1000, result: "Result 1"))
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .none)
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading #2 (2)...")
        .THEN { sut in
            // Previous effect has been cleared
            XCTAssertEqual(sut.effects.count, 2)
            XCTAssertEffectsInclude(sut, MyEffect(milliseconds: 1000, result: "Result 1"))
            XCTAssertEffectsInclude(sut, MyEffect(milliseconds: 1000, result: "Result 2"))
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .some({
            ($0 as? MyEffect<String>)?.result == "Result 1"
        }))
        .WHEN(.networkRespondsWithContent(.success("Result 1")))
        .THEN(\.viewShowsLoadingMessage, equals: nil)
        .THEN(\.viewShowsContent, equals: .success("Result 1"))
        .configure(clearEffectsOnEveryWhenOrEnd: .some({
            ($0 as? MyEffect<String>)?.result == "Result 2"
        }))
        .WHEN(.networkRespondsWithContent(.success("Result 2")))
        .runTest()
    }
}
