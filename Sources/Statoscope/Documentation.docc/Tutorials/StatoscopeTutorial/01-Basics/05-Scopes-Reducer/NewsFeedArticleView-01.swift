import SwiftUI
import Statoscope

struct NewsFeedArticleView: StoreViewProtocol {
    var model: NewsFeedArticleReducer.State
    var send: (NewsFeedArticleReducer.When) -> Void

    var body: some View {
        ScrollView {
            if let article = model.loadedDTO {
                Text(article.title).font(.title)
                Text(article.content)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            if model.favoritesEnabled {
                Button(model.favorites.contains { $0.id == model.id } ? "★" : "☆") {
                    send(.favorite(id: model.id))
                }
            }
        }
    }
}
