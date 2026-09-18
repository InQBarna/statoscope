final class NewsFeedList: Statostore, ObservableObject {
    let favoritesEnabled: Bool

    @Published var loading: Bool = false
    @Published var loadedDTO: FeedListDTO?
    @Subscope var readingArticle: NewsFeedArticle?

    // No more local `favorites` copy — reads the root's canonical list directly.
    // NewsFeedList implements no HierarchialScopeMiddleWare at all; it doesn't need
    // to, since the root intercepts `.favorite` from this scope's own When without any
    // relay code here (see the next type, where Article sends the same event two
    // levels further down and the root still catches it directly).
    @Superscope(observed: true) var newsFeed: NewsFeed

    enum When {
        case systemLoadedScope
        case networkListDidFinish(FeedListDTO)
        case navigateFromListToChild(id: String)
        case favorite(id: String)
    }

    init(favoritesEnabled: Bool) {
        self.favoritesEnabled = favoritesEnabled
    }

    func update(_ when: When) throws {
        switch when {
        case .systemLoadedScope:
            loading = true
            effectsState.enqueue(
                AnyEffect {
                    FeedListDTO(articles: [
                        ArticleDTO(id: "1", title: "Article 1", content: "Content 1"),
                        ArticleDTO(id: "2", title: "Article 2", content: "Content 2")
                    ])
                }
                .map(When.networkListDidFinish)
            )

        case .networkListDidFinish(let dto):
            loading = false
            loadedDTO = dto

        case .navigateFromListToChild(let id):
            // Create child article scope
            readingArticle = NewsFeedArticle(favoritesEnabled: favoritesEnabled, id: id)

        case .favorite:
            // Never reached: NewsFeed.updateSubscope consumes this event (never calls
            // event.forward() for it) — kept here only because `When` must stay
            // exhaustive. The case itself is still what the view sends.
            break
        }
    }
}
