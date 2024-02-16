//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 16/2/24.
//

import Foundation
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

    enum When {
        case systemLoadsSampleScope
        case networkRespondsWithContent(Result<String, Error>)
        case retry
    }
}

private final class SampleScope: StoreProtocol {
    
    typealias When = SampleScopeState.When
    private(set) var state = SampleScopeState()
    
    func update(_ when: SampleScopeState.When) throws {
        switch when {
        case .systemLoadsSampleScope, .retry:
            state.viewShowsLoadingMessage = "Loading..."
        case .networkRespondsWithContent(let newContent):
            state.viewShowsContent = newContent.mapError { _ in SampleError.someError }
            state.viewShowsLoadingMessage = nil
        }
    }
}

final class StoreAndStateDifferentObjects: XCTestCase {

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
