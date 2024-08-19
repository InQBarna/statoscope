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
import Combine

private final class SampleScope:
    Statostore,
    ObservableObject {

    @Published var viewShowsLoadingMessage: String?
    @Published var viewShowsContent: String?

    enum When {
        case systemLoadsSampleScope
        case networkRespondsWithContent(String)
        case retry
    }

    func update(_ when: When) throws {
        viewShowsLoadingMessage = (viewShowsLoadingMessage ?? "") + "-"
    }
}

// This is the "normal" view pattern
private struct SampleView: View {
    @ObservedObject var model = SampleScope().scopeImpl
    var body: some View {
        /* ... */
        EmptyView()
    }
}

// This is the "Presented" view pattern
private struct SamplePresentedView: View, StoreViewProtocol {
    let model: SampleScope
    let send: (SampleScope.When) -> Void
    var body: some View {
        if let loadingText = model.viewShowsLoadingMessage {
            Text(LocalizedStringKey(loadingText))
        }
        if let viewShowsContent = model.viewShowsContent {
            Text(viewShowsContent)
        } else {
            EmptyView()
        }
        // Does not compile, so write-safe
        // .sheet(isPresented: $model.viewShowsContent) { EmptyView() }
        // .sheet(isPresented: model.$viewShowsContent) { EmptyView() }
    }
}

// And how it can be used with an ObservedObject == StoreView
final class PresentedViewPatternTests: XCTestCase {

    func testPresenterViewPatterns() {
        let willChangeObjectExp = expectation(description: "willChangeObject")
        willChangeObjectExp.assertForOverFulfill = false
        let scope = SampleScope()
        let cancellable = scope.objectWillChange.sink { _ in
            willChangeObjectExp.fulfill()
        }
        _ = scope.buildStoreView {
            SamplePresentedView(model: $0, send: $1)
        }
        scope.send(.retry)
        XCTAssertNotNil(cancellable)
        self.wait(for: [willChangeObjectExp], timeout: 1.0)
    }

    func testPresenterViewPatternsTypeInitializer() {
        let willChangeObjectExp = expectation(description: "willChangeObject")
        willChangeObjectExp.assertForOverFulfill = false
        let scope = SampleScope()
        let cancellable = scope.objectWillChange.sink { _ in
            willChangeObjectExp.fulfill()
        }
        _ = scope.buildStoreView(SamplePresentedView.self)
        scope.send(.retry)
        XCTAssertNotNil(cancellable)
        self.wait(for: [willChangeObjectExp], timeout: 1.0)
    }
}
