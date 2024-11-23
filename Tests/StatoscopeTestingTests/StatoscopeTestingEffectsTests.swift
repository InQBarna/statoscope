//
//  StatoscopeTestingEffectsTests.swift
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
    var milliseconds: UInt64
    let result: T
    func runEffect() async throws -> T {
        try await Task.sleep(nanoseconds: milliseconds * 1000_000)
        return result
    }
}
private struct MyOtherEffect: Effect, Equatable {
    func runEffect() async throws -> String {
        ""
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
            viewShowsLoadingMessage = "Loading..."
            effectsState.enqueue(
                MyEffect(milliseconds: 1000, result: "Result")
                    .mapToResultWithErrorType(MyError.self)
                    .map(When.networkRespondsWithContent)
            )
        case .networkRespondsWithContent(let newContent):
            viewShowsContent = newContent
            viewShowsLoadingMessage = nil
        case .navigateToDetail:
            guard case .success(let success) = viewShowsContent else {
                child = MyChildScope(viewShowsDetail: "Not loaded")
                return
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
        case defaultWhen
        case networkRespondsWithContent(Result<String, MyError>)
        case userTappedOnNavigateBack
        case toggle
        case throwAnError
    }

    func update(_ when: When) throws {
        switch when {
        case .defaultWhen:
            effectsState.enqueue(
                MyEffect(milliseconds: 2000, result: "Result2")
                    .mapToResultWithErrorType(MyError.self)
                    .map(When.networkRespondsWithContent)
            )
        case .networkRespondsWithContent:
            break
        case .userTappedOnNavigateBack:
            try myScope._unsafeSendImplementation(.detailTappedBack)
        case .toggle:
            toggled = !toggled
        case .throwAnError:
            throw InvalidStateError()
        }
    }
}

final class StatoscopeTestingEffectsTests: XCTestCase {

    func testNoEffects() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .THEN_NoEffects()
        .runTest()
    }
    
    func testNoEffectsFailsIfExisting() throws {
        XCTExpectFailure("THEN_NoEffects should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN_NoEffects()
        .runTest()
    }
    
    func testNoEffectsChild() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.navigateToDetail)
        .THEN_NoEffects(\.child)
        .runTest()
    }
    
    func testNoEffectsChildFailsIfExisting() throws {
        XCTExpectFailure("THEN_NoEffects on subscope should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.navigateToDetail)
        .WHEN(\.child, .defaultWhen)
        .THEN_NoEffects(\.child)
        .runTest()
    }
    
    func testNoEffectsChildFailsIfChildNil() throws {
        XCTExpectFailure("THEN_NoEffects on subscope should fail if unwrap fails")
        try MyScope.GIVEN {
            MyScope()
        }
        .THEN_NoEffects(\.child)
        .runTest()
    }
    
    func testThenEnqueued() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .all)
        .WHEN(.systemLoadsSampleScope)
        .THEN_EnquedEffect(
            MyEffect(milliseconds: 1000, result: "Result")
        )
        .runTest()
    }
    
    func testThenEnqueuedFailsIfNoExisting() throws {
        XCTExpectFailure("THEN_Enqueued should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .THEN_EnquedEffect(
            MyEffect(milliseconds: 1000, result: "Result")
        )
        .runTest()
    }

    // TODO: we should decide what to do if 2 equal effects enqueued
    func testThenEnqueuedFailsIfMany() throws {
        XCTExpectFailure("THEN_EnqueuedEffect should fail if there are many effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .none)
        .WHEN(.systemLoadsSampleScope)
        .WHEN(.systemLoadsSampleScope)
        .THEN_EnquedEffect(
            MyEffect(milliseconds: 1000, result: "Result")
        )
        .runTest()
    }
    
    func testThenEnqueuedOnOptSubscope() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .all)
        .WHEN(.navigateToDetail)
        .WHEN(\.child, .defaultWhen)
        .THEN_Enqued(
            \.child,
             effect: MyEffect(milliseconds: 2000, result: "Result2")
        )
        .runTest()
    }
    
    func testThenEnqueuedOnOptSubscopeFailsIfNoExisting() throws {
        XCTExpectFailure("THEN_Enqueued should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.navigateToDetail)
        .THEN_Enqued(
            \.child,
            effect: MyEffect(milliseconds: 2000, result: "Result2")
        )
        .runTest()
    }
    
    func testThenEnqueuedOnOptSubscopeFailsIfSubscopeNil() throws {
        XCTExpectFailure("THEN_Enqueued should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .THEN_Enqued(
            \.child,
            effect: MyEffect(milliseconds: 2000, result: "Result2")
        )
        .runTest()
    }
    
    func testThenEnqueuedOnSubscope() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .all)
        .WHEN(.navigateToDetail)
        .WHEN(\.nonOptionalChild, .defaultWhen)
        .THEN_Enqued(
            \.nonOptionalChild,
             effect: MyEffect(milliseconds: 2000, result: "Result2")
        )
        .runTest()
    }
    
    func testThenEnqueuedOnSubscopeFailsIfNoExisting() throws {
        XCTExpectFailure("THEN_Enqueued should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.navigateToDetail)
        .THEN_Enqued(
            \.nonOptionalChild,
            effect: MyEffect(milliseconds: 2000, result: "Result2")
        )
        .runTest()
    }
    
    func testThenNoEnqueued() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .THEN_NoEnquedEffect(MyEffect<String>.self)
        .runTest()
    }
    
    func testThenNoEnqueuedFailsIfExisting() throws {
        XCTExpectFailure("THEN_NoEnqueued should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN_NoEnquedEffect(MyEffect<String>.self)
        .runTest()
    }
    
    func testThenNoEnqueuedHavingManyTypes() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .all)
        .WHEN(.systemLoadsSampleScope)
        .THEN_NoEnquedEffect(MyOtherEffect.self)
        .runTest()
    }
    
    func testThenNoEnqueuedOnSubscope() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.navigateToDetail)
        .THEN_NoEnquedEffect(\.child, MyEffect<String>.self)
        .runTest()
    }
    
    func testThenNoEnqueuedFailsIfExistingOnSubscope() throws {
        XCTExpectFailure("THEN_NoEnqueued should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.navigateToDetail)
        .WHEN(\.child, .defaultWhen)
        .THEN_NoEnquedEffect(\.child, MyEffect<String>.self)
        .runTest()
    }
    
    func testThenNoEnqueuedHavingManyTypesOnSubscope() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .all)
        .WHEN(.navigateToDetail)
        .WHEN(\.child, .defaultWhen)
        .THEN_NoEnquedEffect(\.child, MyOtherEffect.self)
        .runTest()
    }

    func testThenNoEnqueuedFailsIfSubscopeNil() throws {
        XCTExpectFailure("THEN_NoEnqueued should fail if fails to unwrap subscope")
        try MyScope.GIVEN {
            MyScope()
        }
        .THEN_NoEnquedEffect(\.child, MyEffect<String>.self)
        .runTest()
    }
    
    func testThenEnqueuedParameter() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .all)
        .WHEN(.systemLoadsSampleScope)
        .THEN_EnquedEffect(parameter: \MyEffect<String>.milliseconds, equals: UInt64(1000))
        .runTest()
    }
    
    func testThenEnqueuedParameterFailsIfNoEqual() throws {
        XCTExpectFailure("THEN_Enqueued should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .THEN_EnquedEffect(parameter: \MyEffect<String>.milliseconds, equals: UInt64(1500))
        .runTest()
    }

    func testThenEnqueuedParameterFailsIfNoExisting() throws {
        XCTExpectFailure("THEN_Enqueued should fail if there are effects")
        try MyScope.GIVEN {
            MyScope()
        }
        .THEN_EnquedEffect(parameter: \MyEffect<String>.milliseconds, equals: UInt64(1000))
        .runTest()
    }
    
    func testEffectCompletes() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .WHEN_EffectCompletes(MyEffect<String>.self, with: "fakeComplete")
        .THEN(\.viewShowsContent, equals: .success("fakeComplete"))
        .runTest()
    }
    
    func testEffectCompletesFailsWhenMissing() throws {
        XCTExpectFailure("THEN_EffectCompletes should fail if there is no suitable effect")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN_EffectCompletes(MyEffect<String>.self, with: "fakeComplete")
        .runTest()
    }
    
    func testEffectCompletesFailsWhenInvalidType() throws {
        XCTExpectFailure("THEN_EffectCompletes should fail if there is no suitable effect")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .WHEN_EffectCompletes(MyOtherEffect.self, with: "")
        .runTest()
    }
    
    // TODO: we should decide what to do if 2 equal effects enqueued
    func testEffectCompletesFailsWhenManySuitable() throws {
        XCTExpectFailure("THEN_EffectCompletes should fail if there is no suitable effect")
        try MyScope.GIVEN {
            MyScope()
        }
        .configure(clearEffectsOnEveryWhenOrEnd: .none)
        .WHEN(.systemLoadsSampleScope)
        .WHEN(.systemLoadsSampleScope)
        .WHEN_EffectCompletes(MyEffect<String>.self, with: "")
        .runTest()
    }
    
    func testEffectFails() throws {
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .WHEN_EffectFails(MyEffect<String>.self, with: MyError.noConnection)
        .THEN(\.viewShowsContent, equals: .failure(MyError.noConnection))
        .runTest()
    }
    
    func testEffectFailsFailsIfNoExisting() throws {
        XCTExpectFailure("THEN_EffectFails should fail if there is no suitable effect")
        try MyScope.GIVEN {
            MyScope()
        }
        .WHEN_EffectFails(MyEffect<String>.self, with: MyError.noConnection)
        .runTest()
    }
}
