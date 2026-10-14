import SwiftUI
import Statoscope

struct NewsFeedListView: View {
    let model: NewsFeedListReducer.State
    let send: (NewsFeedListReducer.When) -> Void
    // Carried in from the root (see NewsFeedRootView) — this view navigates further, so it needs
    // its own position in the tree, not just `model`/`send`.
    let ownPath: ReducerKeyPath<NewsFeedReducer, NewsFeedListReducer>

    var body: some View {
        List(model.loadedDTO?.articles ?? [], id: \.id) { article in
            Button(article.title) {
                send(.navigateFromListToChild(id: article.id))
            }
        }
        .overlay { if model.loading { ProgressView() } }
        // Manually deriving a NavigationLink binding from `readingArticle` — the getter is easy,
        // but the setter needs a dismiss `When` case wired up by hand to clear it back to nil.
        .navigationDestination(
            isPresented: Binding(
                get: { model.readingArticle != nil },
                set: { isPresented in if !isPresented { /* send(.userDismissedArticle) */ } }
            )
        ) {
            ConnectedChild(ownPath.append(\.readingArticle, as: NewsFeedArticleReducer.self)) { state, send, _ in
                NewsFeedArticleView(model: state, send: send)
            }
        }
    }
}
