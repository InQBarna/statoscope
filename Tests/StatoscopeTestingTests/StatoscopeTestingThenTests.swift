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
    @Subscope var child: MyChildScope?
    @Subscope var nonOptionalChild: MyChildScope = MyChildScope(viewShowsDetail: "Non optional")

    enum When: Equatable {
        case systemLoadsSampleScope
        case networkRespondsWithContent(Result<String, MyError>)
        case retry
        case navigateToDetail
        case detailTappedBack
    }

    func update(_ when: When) throws {
        switch when {
        case .systemLoadsSampleScope, .retry:
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
        case .navigateToDetail:
            guard case .success(let success) = viewShowsContent else {
                throw InvalidStateError()
            }
            child = MyChildScope(viewShowsDetail: success)
        case .detailTappedBack:
            guard nil != child else {
                throw InvalidStateError()
            }
            child = nil
        }
    }
    
    static var defaultValue: MyScope = MyScope()
}

extension MyScope {
    var viewNavigatedToChild: Bool { child != nil }
}

private final class MyChildScope:
    Statostore,
    ObservableObject {
    
    @Published var viewShowsDetail: String
    @Published var toggled: Bool
    @Superscope var myScope: MyScope
    
    public init(viewShowsDetail: String) {
        self.viewShowsDetail = viewShowsDetail
        self.toggled = false
    }
    
    enum When {
        case userTappedOnNavigateBack
        case toggle
        case throwAnError
    }
    
    func update(_ when: When) throws {
        switch when {
        case .userTappedOnNavigateBack:
            try myScope.sendUnsafe(.detailTappedBack)
        case .toggle:
            toggled = !toggled
        case .throwAnError:
            throw InvalidStateError()
        }
    }
}

final class StatoscopeTestingThenTests: XCTestCase {

    // Just providing the highest coverage % to When.swift file here with several scenarios
    func testAllWhenSelfVariants() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .THEN(\.viewShowsLoadingMessage, equals: nil)
        .THEN(\.viewShowsContent, equals: nil)
        .throwsWHEN(.detailTappedBack)
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
        .WHEN(clearEffects: .none, .systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading #2 (2)...")
        .THEN { sut in
            // Previous effect has been cleared
            XCTAssertEqual(sut.effects.count, 2)
            XCTAssertEffectsInclude(sut, MyEffect(milliseconds: 1000, result: "Result 1"))
            XCTAssertEffectsInclude(sut, MyEffect(milliseconds: 1000, result: "Result 2"))
        }
        .WHEN(clearEffects: .some({ ($0 as? MyEffect)?.result == "Result 1" }),
              .networkRespondsWithContent(.success("Result 1")))
        .THEN(\.viewShowsLoadingMessage, equals: nil)
        .THEN(\.viewShowsContent, equals: .success("Result 1"))
        .WHEN(clearEffects: .some({ ($0 as? MyEffect)?.result == "Result 2" }),
              .networkRespondsWithContent(.success("Result 2")))
        .runTest()
    }
    
    func testAllWhenChildVariants() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .AND(.networkRespondsWithContent(.success("Result 1")))
        .AND(.navigateToDetail)
        .THEN(\.child?.toggled, equals: false)
        .WHEN(\.child, .toggle)
        .THEN(\.child?.toggled, equals: true)
        .WHEN(\.child, .toggle)
        .AND(\.child, .toggle)
        .THEN(\.child?.toggled, equals: true)
        .throwsWHEN(\.child, .throwAnError)
        .WHEN(\.child, .userTappedOnNavigateBack)
        .THEN(\.viewNavigatedToChild, equals: false)
        .THEN(\.nonOptionalChild.toggled, equals: false)
        .WHEN(\.nonOptionalChild, .toggle)
        .THEN(\.nonOptionalChild.toggled, equals: true)
        .WHEN(\.nonOptionalChild, .toggle)
        .AND(\.nonOptionalChild, .toggle)
        .THEN(\.nonOptionalChild.toggled, equals: true)
        .throwsWHEN(\.nonOptionalChild, .userTappedOnNavigateBack)
        .runTest()
    }
    
    func testAllWhenOptionalChildFailureWhen() throws {
        XCTExpectFailure("This should fail")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(\.child, .toggle)
        .runTest()
    }
    
    func testAllWhenOptionalChildFailureThrowsWhen() throws {
        XCTExpectFailure("This should fail")
        try MyScope.GIVEN {
            MyScope()
        }
        .throwsWHEN(\.child, .toggle)
        .runTest()
    }
    
    func testAllWhenOptionalChildFailureAND() throws {
        XCTExpectFailure("This should fail")
        try MyScope.GIVEN {
            MyScope()
        }
        .AND(\.child, .toggle)
        .runTest()
    }
}
