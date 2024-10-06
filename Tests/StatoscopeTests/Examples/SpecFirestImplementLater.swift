//
//  SpecFirstTest.swift
//  
//
//  Created by Sergi Hernanz on 16/2/24.
//

import Foundation
import XCTest
import StatoscopeTesting
@testable import Statoscope

// This file demonstrates how to design first the
//  feature and the acceptance criteria, later you
//  can conform to Statostore and implement the
//  business logic

private final class SampleScope:
    Scope,
    ObservableObject {

    @Published var viewShowsLoadingMessage: String?
    @Published var viewShowsContent: Result<String, SampleError>?

    enum When {
        case systemLoadsSampleScope
        case networkRespondsWithContent(Result<String, Error>)
        case retry
    }

    enum SampleError: String, Error, Equatable {
        case someError
        case noConnection
    }
}

#if YOU_CAN_LATER_IMPLEMENT_NO_NEED_WHEN_USING_GIVEN_SPEC
extension SampleScope: Statostore {
    func update(_ when: When) throws {
        switch when {
        case .systemLoadsSampleScope, .retry:
            _scopeImpl.viewShowsLoadingMessage = "Loading..."
        case .networkRespondsWithContent(let newContent):
            _scopeImpl.viewShowsContent = newContent.mapError { _ in SampleError.someError }
            _scopeImpl.viewShowsLoadingMessage = nil
        }
    }
}
#endif

extension SampleScope: DummyScopeImplementation { }

final class SpecFirstTest: XCTestCase {

    func testSpec() throws {

        XCTExpectFailure()

        try SampleScope.GIVEN {
            SampleScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading...")
        .THEN(\.viewShowsContent, equals: nil)
        .WHEN(.networkRespondsWithContent(.success("new content")))
        .THEN(\.viewShowsContent, equals: .success("new content"))
        .runTest()
    }
}
