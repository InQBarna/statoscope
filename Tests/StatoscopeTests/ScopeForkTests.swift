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

fileprivate final class SampleScope: ObservableObject, Scope {
    
    @Published var viewShowsLoadingMessage: String?
    @Published var viewShowsContent: Result<String, String>?
    
    // 'When' naming uses to have also a sentence format: subjectVerbPredicate
    enum When {
        case systemLoadsSampleScope
        case networkRespondsWithContent(Result<String, Error>)
        case retry
    }
    func update(_ when: When) throws {
        switch when {
        case .systemLoadsSampleScope, .retry:
            viewShowsLoadingMessage = "Loading..."
        case .networkRespondsWithContent(let newContent):
            viewShowsContent = newContent.mapError { _ in "An error happened" }
            viewShowsLoadingMessage = nil
        }
    }
}

fileprivate struct SampleView: View {
    @ObservedObject var model = SampleScope()
    var body: some View {
        // If view uses 'acceptance' explicitly it's not only used in tests, also in source code
        if let loadingText = model.viewShowsLoadingMessage {
            Text(LocalizedStringKey(loadingText))
        }
        switch model.viewShowsContent {
        case .success(let content):
            Text(content)
        case .failure(let errorMsg):
            Text(errorMsg)
                .foregroundColor(.red)
        case .none:
            EmptyView()
        }
    }
}

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
        .FORK(.networkRespondsWithContent(.failure("not connected"))) {
            try $0.THEN(\.viewShowsContent, equals: .failure("An error happened"))
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
        .FORK(.networkRespondsWithContent(.failure("not connected"))) {
            try $0
                .THEN(\.viewShowsContent, equals: .failure("An error happened"))
                .WHEN(.retry)
                .FORK(.networkRespondsWithContent(.failure("not connected"))) {
                    try $0
                        .THEN(\.viewShowsContent, equals: .failure("An error happened"))
                        .FORK(.networkRespondsWithContent(.failure("not connected"))) {
                            try $0.THEN(\.viewShowsContent, equals: .failure("An error happened"))
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
