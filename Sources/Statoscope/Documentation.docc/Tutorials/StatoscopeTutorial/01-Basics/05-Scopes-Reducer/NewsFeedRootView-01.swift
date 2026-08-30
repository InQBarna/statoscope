import SwiftUI
import Statoscope

struct NewsFeedRootView: StoreViewProtocol {
    var model: NewsFeedReducer.State
    var send: (NewsFeedReducer.When) -> Void

    var body: some View {
        NavigationStack {
            if model.loadingFeatureToggles {
                ProgressView("Loading…")
            } else {
                // `atList` is only reachable once the parent has created the child —
                // AutoConnectedView reads it from the environment and renders nothing until then.
                AutoConnectedView<NewsFeedReducer.Store, NewsFeedListReducer.Store, NewsFeedListView>(\.children.atList)
            }
        }
    }
}

// At the app root:
// let store = NewsFeedReducer.Store(initialState: .init())
// ReducerStoreView<NewsFeedReducer.Store, NewsFeedRootView>(store: store)
