//
//  ScopeForkTests.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import XCTest
import SwiftUI
@testable import Statoscope
import StatoscopeTesting

private enum SampleError: String, Error, Equatable {
    case someError
    case noConnection
}

private final class SampleScopeState:
    Scope,
    ObservableObject {
    @Published var viewShowsLoadingMessage: String?
    @Published var viewShowsContent: Result<String, SampleError>?

    // 'When' naming uses to have also a sentence format: subjectVerbPredicate
    enum When {
        case systemLoadsSampleScope
        case networkRespondsWithContent(Result<String, Error>)
        case retry
    }
}

// Prueba 1, scope es otro objeto
private final class SampleScope: StoreProtocol {

    typealias When = SampleScopeState.When
    typealias State = SampleScopeState

    private(set) var state = SampleScopeState()
    static func update(state: SampleScopeState, when: SampleScopeState.When, effects: inout EffectsState<When>) throws {
        switch when {
        case .systemLoadsSampleScope, .retry:
            state.viewShowsLoadingMessage = "Loading..."
        case .networkRespondsWithContent(let newContent):
            state.viewShowsContent = newContent.mapError { _ in SampleError.someError }
            state.viewShowsLoadingMessage = nil
        }
    }
}

private struct SampleView: View {
    @ObservedObject var model = SampleScope().state
    var body: some View {
        // If view uses 'acceptance' explicitly it's not only used in tests, also in source code
        if let loadingText = model.viewShowsLoadingMessage {
            Text(LocalizedStringKey(loadingText))
        }
        switch model.viewShowsContent {
        case .success(let content):
            Text(content)
        case .failure(let errorMsg):
            Text(errorMsg.rawValue)
                .foregroundColor(.red)
        case .none:
            EmptyView()
        }
    }
}

private struct SamplePresentedView: View, StoreViewProtocol {
    let model: SampleScopeState
    let send: (SampleScopeState.When) -> Void
    var body: some View {
        // If view uses 'acceptance' explicitly it's not only used in tests, also in source code
        if let loadingText = model.viewShowsLoadingMessage {
            Text(LocalizedStringKey(loadingText))
        }
        switch model.viewShowsContent {
        case .success(let content):
            Text(content)
        case .failure(let errorMsg):
            Text(errorMsg.rawValue)
                .foregroundColor(.red)
        case .none:
            EmptyView()
        }
    }
}

private let sampleView1 = SampleScope().buildStoreView { SamplePresentedView(model: $0, send: $1) }
private let sampleView2 = SampleScope().buildStoreView(view: SamplePresentedView.init)
private let sampleView3 = SampleScope().buildStoreView(SamplePresentedView.self)

final class ScopeForkTests: XCTestCase {

    func testForkTestSyntax() throws {
        let forkCalled = expectation(description: "forkCalled")
        let mainCalled = expectation(description: "mainCalled")

        try SampleScope.GIVEN {
            SampleScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading...")
        .THEN(\.viewShowsContent, equals: nil)
        .FORK(.networkRespondsWithContent(.failure(SampleError.noConnection))) {
            try $0.THEN(\.viewShowsContent, equals: .failure(SampleError.someError))
                .THEN { _ in
                    forkCalled.fulfill()
                }
        }
        .WHEN(.networkRespondsWithContent(.success("new content")))
        .THEN(\.viewShowsContent, equals: .success("new content"))
        .THEN { _ in
            mainCalled.fulfill()
        }
        .runTest()

        wait(for: [mainCalled, forkCalled], timeout: 1)
    }

    func doSomething() throws {
        try SampleScope.GIVEN {
            SampleScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading...")
    }

    func testForkTestSyntax2Levels() throws {
        let forkCalled = expectation(description: "forkCalled")
        let fork2Called = expectation(description: "fork2Called")
        let mainCalled = expectation(description: "mainCalled")

        try SampleScope.GIVEN {
            SampleScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading...")
        .THEN(\.viewShowsContent, equals: nil)
        .FORK(.networkRespondsWithContent(.failure(SampleError.someError))) {
            try $0
                .THEN(\.viewShowsContent, equals: .failure(SampleError.someError))
                .WHEN(.retry)
                .FORK(.networkRespondsWithContent(.failure(SampleError.noConnection))) {
                    try $0
                        .THEN(\.viewShowsContent, equals: .failure(SampleError.someError))
                        .FORK(.networkRespondsWithContent(.failure(SampleError.noConnection))) {
                            try $0.THEN(\.viewShowsContent, equals: .failure(SampleError.someError))
                                .THEN { _ in
                                    fork2Called.fulfill()
                                }
                        }
                }
                .THEN { _ in
                    forkCalled.fulfill()
                }
        }
        .WHEN(.networkRespondsWithContent(.success("new content")))
        .THEN(\.viewShowsContent, equals: .success("new content"))
        .THEN { _ in
            mainCalled.fulfill()
        }
        .runTest()

        wait(for: [mainCalled, forkCalled, fork2Called], timeout: 1)
    }
}
