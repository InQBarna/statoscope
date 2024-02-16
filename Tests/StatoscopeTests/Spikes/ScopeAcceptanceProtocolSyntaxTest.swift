//
//  ScopeAcceptanceStateSyntaxTest.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import XCTest
import SwiftUI
@testable import Statoscope
import StatoscopeTesting

// We can create a protocol so internal state vars are developer-chosen,
//  but acceptance naming are team/PO chosen
//  'acceptance' naming uses to have a sentence format: subjectVerbPredicate
private protocol ScopeAcceptance {
    var viewShowsLoadingMessage: String? { get }
    var viewShowsContent: String? { get }
}

private final class SampleScope: ObservableObject, Statostore {

    @Published var loading: Bool = true
    @Published var content: String?

    // 'When' naming uses to have also a sentence format: subjectVerbPredicate
    enum When {
        case systemLoadsSampleScope
        case networkRespondsWithContent(String)
    }
    func update(_ when: When) throws {
        switch when {
        case .systemLoadsSampleScope:
            loading = true
        case .networkRespondsWithContent(let newContent):
            content = newContent
        }
    }
}

extension SampleScope: ScopeAcceptance {
    var viewShowsLoadingMessage: String? { loading ? "Loading..." : nil }
    var viewShowsContent: String? { content }
}

private struct SampleView: View {
    @ObservedObject var model = SampleScope()
    var body: some View {
        // If view uses 'acceptance' explicitly it's not only used in tests, also in source code
        let acceptanceSnapshot = model as ScopeAcceptance
        if let loadingText = acceptanceSnapshot.viewShowsLoadingMessage {
            Text(LocalizedStringKey(loadingText))
        }
        Text(acceptanceSnapshot.viewShowsContent ?? "")
    }
}

final class ScopeAcceptanceProtocolSyntaxTest: XCTestCase {

    /*
    func testStateSyntax() throws {
        try SampleScope.GIVEN {
            SampleScope()
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.viewShowsLoadingMessage, equals: "Loading...")
        .THEN(\.viewShowsContent, equals: nil)
        .runTest()
    }
     */
}
