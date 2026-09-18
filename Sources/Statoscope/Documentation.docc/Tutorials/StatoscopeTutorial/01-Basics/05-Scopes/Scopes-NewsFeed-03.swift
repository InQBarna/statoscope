final class NewsFeed: Statostore, ObservableObject, Injectable, HierarchialScopeMiddleWare {
    @Published var loadingFeatureToggles: Bool = true
    @Published var favorites: [Favorite] = []
    @Subscope var atList: NewsFeedList?

    enum When {
        case systemLoadedScope
        case featureTogglesLoaded(favoritesEnabled: Bool)
    }

    static var defaultValue: NewsFeed { NewsFeed() }

    @Injected var date: DateProvider
    @Injected var persistence: PersistenceProvider

    func update(_ when: When) throws {
        switch when {
        case .systemLoadedScope:
            loadingFeatureToggles = true
            // The root is now the single owner of `favorites` — load it once here,
            // instead of every child loading its own copy on its own systemLoadedScope.
            favorites = try persistence.get()
            // Simulate loading feature toggles
            effectsState.enqueue(
                AnyEffect { true }  // Simulate favoritesEnabled = true
                    .map { When.featureTogglesLoaded(favoritesEnabled: $0) }
            )

        case .featureTogglesLoaded(let favoritesEnabled):
            loadingFeatureToggles = false
            // Create child scope with feature toggle parameter
            atList = NewsFeedList(favoritesEnabled: favoritesEnabled)
        }
    }

    // Both NewsFeedList and NewsFeedArticle send `.favorite(id:)` — this single
    // updateSubscope catches it from either one, no matter how deep in the tree it
    // was sent from. Unlike the Reducer pattern's updateSubstate, this can mutate
    // `self` directly — no need to delegate through a returned When processed by a
    // separate update() call.
    func updateSubscope<Child: ScopeImplementation>(_ event: SubscopeEvent<Child>) throws {
        if let listEvent = event as? SubscopeEvent<NewsFeedList>,
           case .favorite(let id) = listEvent.when {
            try toggleFavorite(id: id)
            return  // consumed — the child has nothing left to do with .favorite
        }
        if let articleEvent = event as? SubscopeEvent<NewsFeedArticle>,
           case .favorite(let id) = articleEvent.when {
            try toggleFavorite(id: id)
            return  // consumed — never calls event.forward()
        }
        try event.forward()
    }

    private func toggleFavorite(id: String) throws {
        if let favIndex = favorites.firstIndex(where: { $0.id == id }) {
            favorites.remove(at: favIndex)
        } else {
            favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
        }
        try persistence.set(favorites)
    }
}
