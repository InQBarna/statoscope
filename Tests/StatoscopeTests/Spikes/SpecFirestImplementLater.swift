//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 16/2/24.
//

import Foundation
import XCTest
import StatoscopeTesting
@testable import Statoscope

private enum SampleError: String, Error, Equatable {
    case someError
    case noConnection
}

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
}

extension SampleScope: Statostore {
    func update(_ when: When) throws {
        switch when {
        case .systemLoadsSampleScope, .retry:
            _storeState.viewShowsLoadingMessage = "Loading..."
        case .networkRespondsWithContent(let newContent):
            _storeState.viewShowsContent = newContent.mapError { _ in SampleError.someError }
            _storeState.viewShowsLoadingMessage = nil
        }
    }
}

final class SpecFirstTest: XCTestCase {

    func DISABLED_testSpec() throws {
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
