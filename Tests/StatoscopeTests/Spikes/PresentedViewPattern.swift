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
        fatalError()
    }
}

// This is the "normal" view pattern
private struct SampleView: View {
    @ObservedObject var model = SampleScope().state
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
private let sampleView1 = SampleScope().buildStoreView { SamplePresentedView(model: $0, send: $1) }
private let sampleView2 = SampleScope().buildStoreView(view: SamplePresentedView.init)
private let sampleView3 = SampleScope().buildStoreView(SamplePresentedView.self)

