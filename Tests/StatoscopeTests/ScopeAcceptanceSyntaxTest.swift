//
//  ScopeAcceptanceSyntaxTest.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import XCTest
import SwiftUI
@testable import Statoscope

private final class SampleScope: ObservableObject, Statostore {

    // Internal scope state has developer syntax, we have 2 variables which are
    //  represented in the view (loaded, content) and another internal var
    //  so we will split state information into 2 different pieces view + internals
    @Published var loading: Bool = true
    @Published var content: String?
    var pushPermissionsAccepted: Bool?

    // We also split when into 2 different pieces: view + internals
    enum When {
        // View
        case view(ViewAction)
        enum ViewAction {
            case tapsOnRetry
            case tapsOnDetails
        }
        // Internals
        case systemLoadsSampleScope
        case networkRespondsWithContent(String)
        case pushPermissionsResponse(accepted: Bool)
    }

    struct PushPermissionsRequest: Effect {
        func runEffect() async throws -> Bool {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return false
        }
    }

    func update(_ when: When) throws {
        switch when {
        case .systemLoadsSampleScope:
            loading = true
            effectsHandler.enqueue(PushPermissionsRequest().map(When.pushPermissionsResponse))
        case .networkRespondsWithContent(let newContent):
            loading = false
            content = newContent
        case .pushPermissionsResponse(let accepted):
            pushPermissionsAccepted = accepted
        case .view(let viewAction):
            switch viewAction {
            case .tapsOnRetry:
                break
            case .tapsOnDetails:
                break
            }
        }
    }
}

// We can create an "Acceptance" artifact, so we abstract Acceptance from
//  underlying implementation
private struct SampleScopeViewModel: Equatable {
    let showsLoadingMessage: String?
    let showsContent: String?
    static let empty: Self = SampleScopeViewModel(showsLoadingMessage: nil, showsContent: nil)
}
private protocol ScopeAcceptance {
    var view: SampleScopeViewModel { get }
    // We may have other acceptances for unit/int tests: like ongoing effects, shared states
    var pushPermissionsAccepted: Bool? { get }
}

extension SampleScope: ScopeAcceptance {

    // The struct can be used as output for checking acceptance in a human-readable language
    var view: SampleScopeViewModel {
        SampleScopeViewModel(
            showsLoadingMessage: loading ? "Loading..." : nil,
            showsContent: content
        )
    }

    // And it can be used as input
    static var initialState = SampleScope()
    static var loadingState = SampleScope()
        .set(\.loading, true)
    static var loadedState = SampleScope()
        .set(\.loading, false)
        .set(\.content, "Item loaded")
}

private struct SampleView1: View {
    @ObservedObject var model = SampleScope()
    var body: some View {
        let viewModel = model.view
        if let loadingText = viewModel.showsLoadingMessage {
            Text(loadingText)
        }
        Text(viewModel.showsContent ?? "")
        Button("retry") {
            model.send(.view(.tapsOnRetry))
        }
    }
}

private struct SampleView2: View {
    @ObservedObject var model = SampleScope()
    @State var viewModel: SampleScopeViewModel = .empty
    var body: some View {
        if let loadingText = viewModel.showsLoadingMessage {
            Text(loadingText)
        }
        Text(viewModel.showsContent ?? "")
        Button("retry") {
            model.send(.view(.tapsOnRetry))
        }
            .onReceive(model.objectWillChange) { _ in
                // Here you can control animations for example
                viewModel = model.view
            }
    }
}

private struct SampleViewPresentationPattern: View {
    @ObservedObject var model = SampleScope()
    var body: some View {
        Presentation(viewModel: model.view, output: { model.send(.view($0)) })
    }
    struct Presentation: View {
        let viewModel: SampleScopeViewModel
        let output: (SampleScope.When.ViewAction) -> Void
        var body: some View {
            if let loadingText = viewModel.showsLoadingMessage {
                Text(loadingText)
            }
            Text(viewModel.showsContent ?? "")
            Button("retry") {
                output(.tapsOnRetry)
            }
        }
    }
}

class ScopeAcceptanceSyntaxTest: XCTestCase {
    func testViewModelSyntax() throws {
        try SampleScope.GIVEN {
            .initialState
        }
        .WHEN(.systemLoadsSampleScope)
        .THEN(\.view, equals:
                SampleScopeViewModel(
                    showsLoadingMessage: "Loading...", showsContent: nil
                )
        )
        .WHEN(.networkRespondsWithContent("string"))
        .THEN(\.view.showsContent, equals: "string")
        .THEN(\.pushPermissionsAccepted, equals: nil)
        .runTest()
    }
}
