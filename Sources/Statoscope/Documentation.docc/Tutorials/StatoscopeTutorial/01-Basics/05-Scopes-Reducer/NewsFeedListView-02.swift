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
        // The @Reducer macro generates this from `@SubState var readingArticle` on
        // NewsFeedListReducer.State — no manual Binding, no manual NavigationLink.
        // (Requires adding a `.userDismissedArticle` When case that sets
        // `state.readingArticle = nil` in update().)
        .background {
            NewsFeedListReducer.buildReadingArticlePresentedView(
                dismissWhen: .userDismissedArticle,
                content: NewsFeedArticleView.init
            )
        }
    }
}
