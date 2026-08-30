import SwiftUI
import Statoscope

struct NewsFeedListView: StoreViewProtocol {
    var model: NewsFeedListReducer.State
    var send: (NewsFeedListReducer.When) -> Void

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
            AutoConnectedView<NewsFeedListReducer.Store, NewsFeedArticleReducer.Store, NewsFeedArticleView>(\.children.readingArticle)
        }
    }
}
