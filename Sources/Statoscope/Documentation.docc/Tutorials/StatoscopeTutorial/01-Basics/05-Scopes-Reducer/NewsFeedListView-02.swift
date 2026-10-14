import SwiftUI
import Statoscope

struct NewsFeedListView: View {
    let model: NewsFeedListReducer.State
    let send: (NewsFeedListReducer.When) -> Void
    let ownPath: ReducerKeyPath<NewsFeedReducer, NewsFeedListReducer>

    var body: some View {
        List(model.loadedDTO?.articles ?? [], id: \.id) { article in
            Button(article.title) {
                send(.navigateFromListToChild(id: article.id))
            }
        }
        .overlay { if model.loading { ProgressView() } }
        // `NewsFeedListReducer.bind` builds the Binding from `readingArticle` (requires adding a
        // `.userDismissedArticle` When case that sets `state.readingArticle = nil` in update()).
        // The child content itself is unchanged from the previous step: `ConnectedChild` resolves
        // the live child store through `ownPath` — safe here regardless of nesting depth, since
        // resolution never depends on where this view happens to be nested, only on the root
        // Store and the path carried in explicitly.
        .navigationDestination(
            isPresented: NewsFeedListReducer.bind(\.readingArticle, in: model, dismissWhen: .userDismissedArticle, send: send)
        ) {
            ConnectedChild(ownPath.append(\.readingArticle, as: NewsFeedArticleReducer.self)) { state, send, _ in
                NewsFeedArticleView(model: state, send: send)
            }
        }
    }
}
