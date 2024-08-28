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

private enum SampleError: String, Error, Equatable {
    case someError
    case noConnection
}

private final class SampleScope:
    Statostore,
    ObservableObject {

    @Published var viewShowsLoadingMessage: String?
    @Published var viewShowsContent: Result<String, SampleError>?
    @Subscope var child: SampleChildScope? = SampleChildScope()

    enum When {
        case systemLoadsSampleScope
        case networkRespondsWithContent(Result<String, Error>)
        case retry
    }

    func update(_ when: When) throws {
        switch when {
        case .systemLoadsSampleScope, .retry:
            scopeImpl.viewShowsLoadingMessage = "Loading..."
        case .networkRespondsWithContent(let newContent):
            scopeImpl.viewShowsContent = newContent.mapError { _ in SampleError.someError }
            scopeImpl.viewShowsLoadingMessage = nil
        }
    }
}

private final class SampleChildScope:
    Statostore,
    ObservableObject {
    
    @Published var viewShowsLoadingMessage: String?
    @Subscope var grandson: SampleGrandsonScope? = SampleGrandsonScope()

    enum When {
        case defaultWhen
    }

    func update(_ when: When) throws {
        switch when {
        case .defaultWhen:
            scopeImpl.viewShowsLoadingMessage = "Loading..."
        }
    }
}

private final class SampleGrandsonScope:
    Statostore,
    ObservableObject {
    
    @Published var viewShowsLoadingMessage: String?
    
    enum When {
        case defaultWhen
    }

    func update(_ when: When) throws {
        switch when {
        case .defaultWhen:
            scopeImpl.viewShowsLoadingMessage = "Loading..."
        }
    }
}

final class StatoscopeTestingForkWithTests: XCTestCase {

    func testForkMainPathWithAndPop() throws {
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
        .WITH(\.child)
        .POP()
        .THEN { _ in
            mainCalled.fulfill()
        }
        .runTest()

        wait(for: [mainCalled, forkCalled], timeout: 1)
    }

    func testForkMainPathWithAndNoPop() throws {
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
        .WITH(\.child)
        .THEN { _ in
            mainCalled.fulfill()
        }
        .runTest()

        wait(for: [mainCalled, forkCalled], timeout: 1)
    }

    func testForkSecPathWithAndPop() throws {
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
                .WITH(\.child)
                .POP()
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
    
    func testForkSecPathWithAndNoPop() throws {
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
                .WITH(\.child)
                .THEN { _ in
                    forkCalled.fulfill()
                }
                .POP()
        }
        .WHEN(.networkRespondsWithContent(.success("new content")))
        .THEN(\.viewShowsContent, equals: .success("new content"))
        .THEN { _ in
            mainCalled.fulfill()
        }
        .runTest()

        wait(for: [mainCalled, forkCalled], timeout: 1)
    }
    
    func testForkMainPathDoubleWith() throws {
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
        .WITH(\.child)
        .WITH(\.grandson)
        .THEN { _ in
            mainCalled.fulfill()
        }
        .runTest()

        wait(for: [mainCalled, forkCalled], timeout: 1)
    }
    
    func testForkSecPathDoubleWith() throws {
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
                .WITH(\.child?.grandson)
                .THEN { _ in
                    forkCalled.fulfill()
                }
                .POP()
        }
        .WHEN(.networkRespondsWithContent(.success("new content")))
        .THEN(\.viewShowsContent, equals: .success("new content"))
        .THEN { _ in
            mainCalled.fulfill()
        }
        .runTest()

        wait(for: [mainCalled, forkCalled], timeout: 1)
    }
    
    func testWithBeforeForkSecPathDoubleWith() throws {
        let forkCalled = expectation(description: "forkCalled")
        let mainCalled = expectation(description: "mainCalled")

        try SampleScope.GIVEN {
            SampleScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading...")
        .WITH(\.child)
        .FORK(.defaultWhen) {
            try $0.THEN(\.viewShowsLoadingMessage, equals: "Loading...")
                .THEN { _ in
                    forkCalled.fulfill()
                }
        }
        .POP()
        .WHEN(.networkRespondsWithContent(.success("new content")))
        .THEN(\.viewShowsContent, equals: .success("new content"))
        .THEN { _ in
            mainCalled.fulfill()
        }
        .runTest()

        wait(for: [mainCalled, forkCalled], timeout: 1)
    }
}
