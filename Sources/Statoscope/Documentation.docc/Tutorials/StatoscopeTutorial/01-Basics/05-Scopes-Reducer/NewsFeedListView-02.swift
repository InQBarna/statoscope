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
        // `NewsFeedListReducer.bind` builds the Binding from `readingArticle` (requires adding a
        // `.userDismissedArticle` When case that sets `state.readingArticle = nil` in update());
        // the macro-generated `buildReadingArticleView` resolves the live child store — safe
        // here regardless of nesting depth, since it resolves through the shared registry
        // rather than a level-specific @EnvironmentObject.
        .navigationDestination(
            isPresented: NewsFeedListReducer.bind(\.readingArticle, in: model, dismissWhen: .userDismissedArticle, send: send)
        ) {
            NewsFeedListReducer.buildReadingArticleView(content: NewsFeedArticleView.init)
        }
    }
}
