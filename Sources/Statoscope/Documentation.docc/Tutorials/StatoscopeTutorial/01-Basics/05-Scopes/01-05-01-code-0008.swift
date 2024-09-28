final class NewsFeed: Statostore, ObservableObject {

    @Published var loadingFeatureToggles: Bool = true
    @Subscope var atList: NewsFeedList?
    
    enum When {
        case systemLoadedScope
        case networkReturnsFeatureToggle(Result<[String: String], EquatableError>)
    }
    
    @Injected var network: NetworkProvider
    func update(_ when: When) throws { }
}

final class NewsFeedList: Statostore, ObservableObject {
    
    let favoritesEnabled: Bool
    @Published var loading: Bool = false
    @Published var loadedDTO: DTO.FeedList?
    @Subscope var readingArticle: NewsFeedArticle?
    @Published var favorites: [Favorite] = []
    
    enum When {
        case networkListDidFinish(DTO.FeedList)
        case navigateFromListToChild(id: String)
        case favorite(id: String)
    }
    
    init(favoritesEnabled: Bool) { self.favoritesEnabled = favoritesEnabled }
    @Injected var date: DateProvider
    @Injected var persistence: PersistenceProvider
    @Injected var network: NetworkProvider
    func update(_ when: When) throws { }
}

final class NewsFeedArticle: Statostore, ObservableObject {
    
    let favoritesEnabled: Bool
    let id: String
    @Published var loading: Bool = false
    @Published var loadedDTO: DTO.Article?
    @Published var favorites: [Favorite] = []
    
    enum When {
        case networkDidFinish(DTO.Article)
        case favorite(id: String)
    }
    
    init(favoritesEnabled: Bool, id: String) {
        self.favoritesEnabled = favoritesEnabled
        self.id = id
    }
    @Injected var date: DateProvider
    @Injected var persistence: PersistenceProvider
    @Injected var network: NetworkProvider
    func update(_ when: When) throws { }
}
