final class NewsFeedArticle: Statostore, ObservableObject {
    let favoritesEnabled: Bool
    let id: String

    @Published var loading: Bool = false
    @Published var loadedDTO: ArticleDTO?

    // Skips the direct parent (NewsFeedList) and reads the root two levels up —
    // always safe here, because @Superscope resolves to a LIVE REFERENCE to the
    // actual ancestor object, not a value snapshot copied at some point in time.
    // There's no equivalent of the Reducer pattern's "stale cached mirror" gotcha to
    // worry about — reading through it always reflects the ancestor's current state.
    @Superscope(observed: true) var newsFeed: NewsFeed

    enum When {
        case systemLoadedScope
        case networkDidFinish(ArticleDTO)
        case favorite(id: String)
    }

    init(favoritesEnabled: Bool, id: String) {
        self.favoritesEnabled = favoritesEnabled
        self.id = id
    }

    func update(_ when: When) throws {
        switch when {
        case .systemLoadedScope:
            loading = true
            effectsState.enqueue(
                AnyEffect {
                    ArticleDTO(id: self.id, title: "Article \(self.id)", content: "Content for \(self.id)")
                }
                .map(When.networkDidFinish)
            )

        case .networkDidFinish(let dto):
            loading = false
            loadedDTO = dto

        case .favorite:
            // Never reached: NewsFeed.updateSubscope consumes this event before it
            // gets here.
            break
        }
    }
}
