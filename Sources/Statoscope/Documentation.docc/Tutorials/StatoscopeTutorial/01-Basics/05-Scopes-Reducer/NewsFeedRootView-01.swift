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
                // ConnectedChild resolves it via an explicit path from the root and renders
                // nothing until then.
                ConnectedChild(ReducerKeyPath<NewsFeedReducer, NewsFeedReducer>.root.append(\.atList, as: NewsFeedListReducer.self)) { state, send, path in
                    NewsFeedListView(model: state, send: send, ownPath: path)
                }
            }
        }
    }
}

// At the app root:
// let store = NewsFeedReducer.Store(initialState: .init())
// ReducerStoreView<NewsFeedReducer.Store, NewsFeedRootView>(store: store)
